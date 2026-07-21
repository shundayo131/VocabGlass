//
//  RealtimeClient.swift
//  VocabGlass
//
//  Talks to the OpenAI Realtime API over WebRTC: fetches an ephemeral
//  key from the worker, does the SDP offer/answer exchange, and routes
//  events on the data channel (tool calls, session lifecycle). WebRTC
//  itself carries the mic audio up and the voice reply down, so there
//  is no audio code here. Knows nothing about DAT or storage; the
//  session controller wires those together.
//

import Foundation
import Combine
import WebRTC

@MainActor
final class RealtimeClient: NSObject, ObservableObject {

    // MARK: - State the UI reads

    @Published var status = "disconnected"
    @Published var isConnected = false
    @Published var lastToolCall: String?

    // Wired up by the owner: called when the model asks the app to act.
    var onToolCall: ((_ callId: String, _ name: String) -> Void)?

    // Fired when the connection dies mid-session.
    var onDisconnect: (() -> Void)?

    // MARK: - Private

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    private var peerConnection: RTCPeerConnection?
    private var dataChannel: RTCDataChannel?
    private var connectTask: Task<Void, Never>?

    private struct TokenResponse: Decodable {
        let token: String
        let model: String
    }

    // MARK: - Connect / Disconnect

    // Fetch an ephemeral key from the worker, then run the WebRTC
    // offer/answer exchange with OpenAI.
    func connect() {
        guard peerConnection == nil else { return }
        status = "fetching token"
        connectTask = Task {
            do {
                let token = try await fetchToken()
                try await openConnection(token)
                status = "waiting for session"
            } catch {
                guard !Task.isCancelled else { return }
                status = "connect failed: \(error.localizedDescription)"
                teardown()
                onDisconnect?()
            }
        }
    }

    func disconnect() {
        connectTask?.cancel()
        connectTask = nil
        teardown()
        status = "disconnected"
    }

    private func teardown() {
        dataChannel?.close()
        dataChannel = nil
        peerConnection?.close()
        peerConnection = nil
        isConnected = false
    }

    // Fetch an ephemeral OpenAI Realtime key from the worker.
    private func fetchToken() async throws -> TokenResponse {
        var request = URLRequest(url: WorkerConfig.endpoint("token"))
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Realtime", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // The standard WebRTC handshake from the OpenAI docs: peer
    // connection with a mic track and an "oai-events" data channel,
    // local SDP offer, POST it to /v1/realtime/calls with the ephemeral
    // key, apply the answer SDP that comes back.
    private func openConnection(_ token: TokenResponse) async throws {
        status = "connecting"

        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil,
                                              optionalConstraints: nil)
        guard let pc = Self.factory.peerConnection(with: config,
                                                   constraints: constraints,
                                                   delegate: self) else {
            throw NSError(domain: "Realtime", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "could not create peer connection"])
        }
        peerConnection = pc

        // Mic audio up. The reply audio track OpenAI adds on their side
        // plays automatically through the active audio route.
        let audioSource = Self.factory.audioSource(with: constraints)
        let audioTrack = Self.factory.audioTrack(with: audioSource, trackId: "mic")
        pc.add(audioTrack, streamIds: ["local"])

        // All JSON events (tool calls, session lifecycle) ride this
        // channel. The name is fixed by the OpenAI docs.
        let channel = pc.dataChannel(forLabel: "oai-events",
                                     configuration: RTCDataChannelConfiguration())
        channel?.delegate = self
        dataChannel = channel

        let offer = try await pc.offer(for: constraints)
        try await pc.setLocalDescription(offer)

        let answerSdp = try await exchangeSDP(offer: offer.sdp, key: token.token)
        try await pc.setRemoteDescription(
            RTCSessionDescription(type: .answer, sdp: answerSdp))
    }

    // POST the offer SDP to OpenAI, get the answer SDP back.
    private func exchangeSDP(offer: String, key: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = offer.data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let sdp = String(data: data, encoding: .utf8) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Realtime", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "SDP exchange failed: \(body)"])
        }
        return sdp
    }

    // MARK: - Sending events

    // Answer a tool call: add the function_call_output item, then ask
    // the model to respond to it. The two-event sequence is the
    // documented function calling flow.
    func sendToolResult(callId: String, result: [String: Any]) {
        let output = (try? JSONSerialization.data(withJSONObject: result))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        sendEvent([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output,
            ],
        ])
        sendEvent(["type": "response.create"])
    }

    private func sendEvent(_ event: [String: Any]) {
        guard let channel = dataChannel,
              let data = try? JSONSerialization.data(withJSONObject: event) else { return }
        channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    // MARK: - Receiving events

    private func handleEvent(_ data: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }

        switch type {
        case "session.created":
            isConnected = true
            status = "connected, listening"

        case "response.done":
            // Function calls arrive as output items on the finished
            // response; arguments are ignored since our tools take none.
            guard let response = event["response"] as? [String: Any],
                  let output = response["output"] as? [[String: Any]] else { return }
            for item in output where item["type"] as? String == "function_call" {
                guard let callId = item["call_id"] as? String,
                      let name = item["name"] as? String else { continue }
                lastToolCall = name
                status = "tool call: \(name)"
                onToolCall?(callId, name)
            }

        case "error":
            let message = (event["error"] as? [String: Any])?["message"] as? String ?? "unknown"
            status = "server error: \(message)"

        default:
            break
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

// WebRTC callbacks arrive on its own threads; hop to the main actor
// before touching state.
extension RealtimeClient: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection,
                                    didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if newState == .failed || newState == .disconnected {
                let wasConnected = self.isConnected
                self.isConnected = false
                self.status = "connection lost"
                if wasConnected { self.onDisconnect?() }
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - RTCDataChannelDelegate

extension RealtimeClient: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {}

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel,
                                 didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        Task { @MainActor [weak self] in
            self?.handleEvent(data)
        }
    }
}
