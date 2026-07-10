//
//  SessionController.swift
//  VocabGlass
//
//  The conductor of a voice session: starts and stops the DAT camera,
//  audio route, audio engine, and Gemini connection as one unit, and
//  turns Gemini tool calls into real app actions. The only class that
//  knows all the other components.
//

import Foundation 
import Combine 
import UIKit 

@MainActor 
final class SessionController: ObservableObject {

    enum SessionState: String{
        case idle, starting, active, ending 
    }

    // MARK: - State the UI reads
    @Published private(set) var state: SessionState = .idle
    @Published var statusLine = "no session"
    @Published var lastError: String? 
    
    // MARK: - Dependencies 

    // Shared with v1 screens. injected. 
    private let glasses: GlassesClient
    private let store: CardStore

    // Session only, owned here. 
    private let gemini = GeminiLiveClient()
    private let audioEngine = LiveAudioEngine()
    private let route = AudioRouteManager()

    init(glasses: GlassesClient, store: CardStore) {
        self.glasses = glasses
        self.store = store
    }


    func startSession() {
        guard state == .idle else { return } 
        state = .starting
        lastError = nil
        Task { await start() }
    }

    private func start() async {
        // wireing 
        wireCallbacks()

        // Audio route 
        statusLine = "configuring audio"
        do {
            try route.activate()
        } catch {
            fail("audio route: \(error.localizedDescription)")
            return
        }

        // Camera: startCamera kicks off an async chain; wait for the
        // stream to actually reach streaming.
        statusLine = "starting camera"
        glasses.startCamera()
        guard await waitUntil(timeoutSeconds: 20, { self.glasses.isReady }) else {
            fail("camera did not reach streaming: \(glasses.lastError ?? "no error")")
            return
        }

        // 3. Gemini. connect() also kicks off an async chain.
        statusLine = "connecting to Gemini"
        gemini.connect()
        guard await waitUntil(timeoutSeconds: 15, { self.gemini.isConnected }) else {
            fail("Gemini did not connect: \(gemini.status)")
            return
        }

        // 4. Audio engine last, when everything it feeds is up.
        do {
            try audioEngine.start()
        } catch {
            fail("audio engine: \(error.localizedDescription)")
            return
        }

        // TODO: start the 10 minute timer here.

        state = .active
        statusLine = route.isOnGlasses ? "listening (glasses)" : "listening (iPhone mic)"
    }
    
    // MARK: - End 
    func endSession() {
        guard state == .active || state == .starting else { return }
        state = .ending
        statusLine = "ending session"

        // TODO: cancel the timer here.

        // deactivate audio, gemini, glasses
        audioEngine.stop()
        gemini.disconnect()
        route.deactivate()
        glasses.stopCamera()

        state = .idle
        statusLine = "no session"
    }

    // A failed start is just an end with a reason.
    private func fail(_ message: String) {
        lastError = message
        endSession()
    }


    // MARK: - Wiring 
    
    // Connect the component each other. Call once per session start;
    // closure replace the previous session's wiring 
    private func wireCallbacks() {
        // Mic chunks up to Gemini (audio thread -> main actor hop).
        audioEngine.onMicChunk = { [weak self] data in
            Task { @MainActor in self?.gemini.sendAudioChunk(data) }
        }
        // Reply audio down to the speaker.
        gemini.onAudioChunk = { [weak self] data in
            self?.audioEngine.play(data)
        }

        // Tool calls into app actions.
        gemini.onToolCall = { [weak self] id, name in
            self?.handleToolCall(id: id, name: name)
        }

        // Route moves (Hey Meta, glasses off) update the status line.
        route.onRouteChange = { [weak self] isOnGlasses in
            guard let self, self.state == .active else { return }
            self.statusLine = isOnGlasses ? "listening (glasses)" : "listening (iPhone mic)"
        }
    }

    // MARK: - Tool Calls 

    // handle Gemini's toolcall request 
    private func handleToolCall(id: String, name: String) {
        switch name {
        case "capture_object":
            // The flow is async; run it outside the callback
            // so audio and further messages keep flowing while we work
            Task { await handleCapture(id: id, name: name)} 

        case "end_session":
            // Answer first so Gemini can say goodbye, then tear down.
            gemini.sendToolResponse(id: id, name: name, result: ["status": "ending"])
            endSession()

        default:
            gemini.sendToolResponse(id: id, name: name, result: [
                "status": "error",
                "message": "unknown tool \(name)",
            ])
        }
    }

    // photo -> card -> save -> spoken confirmation.
    // Always answers the tool call, success or failure, 
    // so Gemini never waits forever.
    private func handleCapture(id: String, name: String) async {
        do {
            statusLine = "capturing photo"
            let image = try await glasses.captureAndWait()

            statusLine = "generating card"
            let card = try await CardAPI.generate(from: image)

            store.save(card, image: image)
            statusLine = "saved: \(card.word)"

            // respond to Gemini's tool call request 
            gemini.sendToolResponse(id: id, name: name, result: [
                "status": "saved",
                "word": card.word,
                "pronunciation": card.pinyin,
                "translation": card.translation,
                "example": card.example,
            ])
        } catch {
            statusLine = "capture failed"
            gemini.sendToolResponse(id: id, name: name, result: [
                "status": "error",
                "message": error.localizedDescription,
            ])
        }
    }

    // MARK: - Helpers 
    
    // Poll a condition until it holds or the deadline passes. The same
    // missed-event-proof pattern as GlassesClient's session wait.
    private func waitUntil(timeoutSeconds: Double,
                           _ condition: @escaping () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(timeoutSeconds))
        while !condition() {
            if ContinuousClock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }
}
