//
//  GeminiLiveClient.swift
//  VocabGlass
//
//  Talks to the Gemini Live API over a raw WebSocket: fetches an ephemeral
//  token from the worker, opens the session, and routes what comes back
//  (voice audio, tool calls, shutdown warnings). Knows nothing about DAT
//  or storage; the session controller wires those together in M9.
//

import Foundation
import Combine 

@MainActor 
final class GeminiLiveClient: ObservableObject {

    // MARK: - State the UI reads 

    @Published var status = "disconnected"
    @Published var isConnected = false
    @Published var lastToolCall: String?
    @Published var pendingToolCall: (id: String, name: String)?

    // Wired up by the owner: called when Gemini asks the app to act 
    var onToolCall: ((_ id: String, _ name: String) -> Void)?

    // Raw 24 kHz PCM16 reply audio, played by the audio engine 
    var onAudioChunk: ((Data) -> Void)?

    // Fired when the user talks over the model. The audio engine must
    // flush its playback queue or the conversation drifts behind.
    var onInterrupted: (() -> Void)?

    // Fired when the server announces it will close the connection soon
    // (connection lifetime is about 10 minutes).
    var onGoAway: (() -> Void)?

    // Fired when the socket dies unexpectedly mid-session.
    var onDisconnect: (() -> Void)?

    // MARK: - Private 

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var audioChunksSent = 0
    private var droppedChunks = 0

    // Transcription fragments accumulate here and flush to the session
    // log on turn boundaries, so the log reads as whole sentences.
    private var inputTranscript = ""
    private var outputTranscript = ""

    // Audio sends waiting for the socket to confirm them. Each chunk is
    // about 100 ms of audio, so 8 in flight is roughly a second of lag.
    private var inFlightSends = 0
    private let maxInFlightSends = 8

    private struct TokenResponse: Decodable {
        let token: String
        let model: String
    }

    // MARK: - Connect / Disconnect

    // Connect to the Gemini Live API with an ephemeral token fetched from the worker
    func connect() {
        guard socket == nil else { return }  // already connected
        status = "fetching token"
        Task {
            do {
                // Fetch an ephemeral token from the worker, then open the WebSocket
                let token = try await fetchToken()
                openSocket(token)
            } catch {
                status = "connect failed: \(error.localizedDescription)"
            }
        }

    }

    // Disconnect from the Gemini Live API and clean up state
    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        isConnected = false
        status = "disconnected"
    }

    // Fetch an ephemeral Gemini Live token from the worker
    private func fetchToken() async throws -> TokenResponse {
        var request = URLRequest(url: WorkerConfig.endpoint("token"))
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "GeminiLive", code: 1, 
                          userInfo: [NSLocalizedDescriptionKey: body])
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // Open a WebSocket to the Gemini Live API with the ephemeral token
    private func openSocket(_ token: TokenResponse) {
        // Ephemeral tokens use their own method (BidiGenerateContentConstrained)
        // on the v1alpha surface, with the token in the access_token query
        // parameter. The plain BidiGenerateContent method only takes API keys.
        var components = URLComponents(string:"wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContentConstrained")!
        components.queryItems = [URLQueryItem(name: "access_token", value: token.token)]

        let socket = URLSession.shared.webSocketTask(with: components.url!)
        self.socket = socket
        status = "connecting"
        socket.resume()
        listen()
        sendSetup(model: token.model)
    }


    // MARK: - Setup

    // With a constrained ephemeral token, the system prompt, tools, and
    // response modality are baked into the token by the worker (the
    // constrained method ignores them if sent from here). The setup
    // message only names the model.
    private func sendSetup(model: String) {
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
            ],
        ]
        sendJSON(setup)
    }

    // MARK: - Sending 

    // Called by the audio engine with 16kHz PCM16 mono chunks.
    func sendAudioChunk(_ pcm: Data) {
        // Backpressure: when the uplink cannot drain in real time (weak
        // network, radio contention with the DAT stream), queueing every
        // chunk delays the whole conversation and it never recovers.
        // Dropping keeps the session realtime at the cost of small gaps.
        guard inFlightSends < maxInFlightSends else {
            droppedChunks += 1
            #if DEBUG
            if droppedChunks % 20 == 1 {
                print("gemini -> uplink congested, dropped \(droppedChunks) chunks so far")
            }
            #endif
            return
        }
        inFlightSends += 1

        #if DEBUG
        audioChunksSent += 1
        if audioChunksSent % 20 == 1 {
            print("gemini -> audio chunk #\(audioChunksSent), \(pcm.count) bytes, in flight: \(inFlightSends)")
        }
        #endif
        sendJSON([
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcm.base64EncodedString(),
                ],
            ],
        ], onSent: { [weak self] in
            self?.inFlightSends -= 1
        })
    }

    // Send the result of an app action back so Gemini can speak it.
    // scheduling: INTERRUPT asks the async model to speak the result right
    // away; it sits next to id and name, not inside response.
    func sendToolResponse(id: String, name: String, result: [String: Any]) {
        sendJSON([
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": id,
                        "name": name,
                        "response": result,
                        "scheduling": "INTERRUPT",
                    ],
                ]
            ]
        ])
    }

    // Send a JSON object over the WebSocket. Errors are surfaced to the
    // UI; onSent fires on the main actor when the socket confirms the
    // send (used for audio backpressure accounting).
    private func sendJSON(_ object: [String: Any], onSent: (() -> Void)? = nil) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else {
            onSent?()
            return
        }
        socket.send(.string(text)) { error in
            Task { @MainActor [weak self] in
                onSent?()
                if let error {
                    self?.status = "send failed: \(error.localizedDescription)"
                }
            }
        }
    }


    // MARK: - Receiving

    // Start the receive loop: waits for messages one at a time and
    // routes each to handle(). Returns immediately; the loop runs
    // until disconnect or a socket error.
    private func listen() {
        // Task starts running as soon as it is created. The loop exits
        // when the client is deallocated, the socket is cleared, or
        // disconnect() cancels this task.
        receiveTask = Task { [weak self] in
            while let self, let socket = self.socket, !Task.isCancelled {
                do {
                    let message = try await socket.receive()
                    switch message {
                    case .data(let data):
                        self.handle(data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) { self.handle(data) }
                    @unknown default:
                        break
                    }
                } catch {
                    if !Task.isCancelled {
                        // The server explains rejects (bad token, bad setup)
                        // in the close reason. Surface it.
                        let code = self.socket?.closeCode.rawValue ?? -1
                        let reason = self.socket?.closeReason
                            .flatMap { String(data: $0, encoding: .utf8) } ?? error.localizedDescription
                        self.status = "socket closed (code \(code)): \(reason)"
                        self.isConnected = false
                        self.onDisconnect?()
                    }
                    return
                }
            }
        }
    }

    // Handle Gemini response 
    private func handle (_ data: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        #if DEBUG
        // See what kinds of messages arrive (toolCall, serverContent...).
        print("gemini <- keys:", Array(message.keys))
        #endif

        // First reply after setup: the session is live
        if message["setupComplete"] != nil {
            isConnected = true
            status = "connected, listening"
            Diag.event("gem", "setupComplete")
            return
        }

        // Gemini wants the app to do something
        if let toolCall = message["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            // Flush transcripts first so the log shows what triggered it.
            flushTranscripts()
            for call in calls {
                guard let id = call["id"] as? String,
                      let name = call["name"] as? String else { continue }
                lastToolCall = name
                status = "tool call: \(name)"
                Diag.event("tool", "toolCall received: \(name)")
                pendingToolCall = (id, name)
                onToolCall?(id, name)
            }
            return
        }

        // Voice reply audio arrives in parts as inline base64 PCM
        if let serverContent = message["serverContent"] as? [String: Any] {
            // The user talked over the model: stop playing the stale reply.
            if serverContent["interrupted"] != nil {
                Diag.event("gem", "interrupted")
                flushTranscripts()
                onInterrupted?()
                return
            }

            // Transcriptions arrive as fragments; collect them and log
            // whole sentences on turn boundaries.
            if let tx = serverContent["inputTranscription"] as? [String: Any],
               let text = tx["text"] as? String {
                inputTranscript += text
            }
            if let tx = serverContent["outputTranscription"] as? [String: Any],
               let text = tx["text"] as? String {
                outputTranscript += text
            }
            if serverContent["turnComplete"] != nil {
                Diag.event("gem", "turnComplete")
                flushTranscripts()
            }

            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inline = part["inlineData"] as? [String: Any],
                       let base64 = inline["data"] as? String,
                       let audio = Data(base64Encoded: base64) {
                        onAudioChunk?(audio)
                    }
                }
            }
            return
        }

        // The server closes the connection soon (10 mins)
        if let goAway = message["goAway"] as? [String: Any] {
            status = "server closing soon: \(goAway["timeLeft"] ?? "?")"
            Diag.event("gem", "goAway: \(goAway["timeLeft"] ?? "?")")
            onGoAway?()
            return
        }
    }

    // Write accumulated transcript fragments to the session log as full
    // lines: what Gemini heard (you) and what it said (gem).
    private func flushTranscripts() {
        if !inputTranscript.isEmpty {
            Diag.debug("you", inputTranscript)
            inputTranscript = ""
        }
        if !outputTranscript.isEmpty {
            Diag.debug("gem", outputTranscript)
            outputTranscript = ""
        }
    }
}