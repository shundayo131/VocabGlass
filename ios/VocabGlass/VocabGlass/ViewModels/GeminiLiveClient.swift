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

    // MARK: - Private 

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var audioChunksSent = 0

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

    // NON_BLOCKING lets the model keep talking while the app runs the tool. 
    private func sendSetup(model: String) {
        let setup: [String: Any] = [
            "setup": [
                "model": "models/\(model)",
                "generationConfig": [
                    "responseModalities": ["AUDIO"],
                ],
                "systemInstruction": [
                    "parts": [["text": Self.systemPrompt]],
                ],
                "tools": [[
                        "functionDeclarations": [
                            [
                                "name": "capture_object",
                                "description": "Capture a photo of what the user is looking at and save it as a vocabulary entry. Call this when the user asks to capture, save, or learn the thing they see.",
                                "behavior": "NON_BLOCKING",
                            ],
                            [
                                "name": "end_session",
                                "description": "End the current learning session. Call this when the user says they are done or asks to end the session.",
                                "behavior": "NON_BLOCKING",
                            ],
                        ],
                ]],
            ],
        ]
        sendJSON(setup)
    }

    static let systemPrompt = """
        You are VocabGlass, a voice assistant for a language learning session. The user wears camera glasses and looks at real objects. \
        Keep every reply to one short sentence. When the user asks to capture something, acknowledge briefly and call capture_object. \
        When a tool result with a saved entry arrives, tell the user the word and its meaning. When the user wants to stop, call end_session and say goodbye.
    """

    // MARK: - Sending 

    // Called by the audio engine with 16kHz PCM16 mono chunks
    func sendAudioChunk(_ pcm: Data) {
        #if DEBUG
        audioChunksSent += 1
        if audioChunksSent % 20 == 1 {
            print("gemini -> audio chunk #\(audioChunksSent), \(pcm.count) bytes, socket: \(socket == nil ? "nil" : "open")")
        }
        #endif
        sendJSON([
            "realtimeInput": [
                "audio": [
                    "mimeType": "audio/pcm;rate=16000",
                    "data": pcm.base64EncodedString(),
                ],
            ],
        ])
    }

    // Send the result of an app action back so Gemini can speak it 
    func sendToolResponse(id: String, name: String, result: [String: Any]) {
        var response = result
        // Ask the async model to speak the result right away. Sync models ignore this. 
        // Field placement to be confirmed while testing.
        response["scheduling"] = "INTERRUPT"
        // send JSON object over the WebSocket to Gemini Live
        sendJSON([
            "toolResponse": [
                "functionResponses": [
                    ["id": id, "name": name, "response": response],
                ]
            ]
        ])
    }

    // Send a JSON object over the WebSocket. Errors are surfaced to the UI.
    private func sendJSON(_ object: [String: Any]) {
        guard let socket,
              let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        socket.send(.string(text)) { error in
            if let error {
                Task { @MainActor [weak self] in
                    self?.status = "send failed: \(error.localizedDescription)"
                }
            }  
        }
    }


    // MARK: - Receiving

    // Listen to Gemini response and take actions 
    private func listen() {
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
            return
        }

        // Gemini wants the app to do something
        if let toolCall = message["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in calls {
                guard let id = call["id"] as? String,
                      let name = call["name"] as? String else { continue }
                lastToolCall = name
                status = "tool call: \(name)"
                pendingToolCall = (id, name)
                onToolCall?(id, name)
            }
            return
        }

        // Voice reply audio arrives in parts as inline base64 PCM
        if let serverContent = message["serverContent"] as? [String: Any] {
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
            return 
        }
    }
}