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

    enum SessionState: String {
        case idle, starting, active, ending
    }

    // MARK: - State the UI reads
    @Published private(set) var state: SessionState = .idle
    @Published var statusLine = "no session"
    @Published var lastError: String? 
    @Published private(set) var remainingSeconds = 0

    private var sessionTimer: Task<Void, Never>?
    static let sessionLimitSeconds = 10 * 60

    // Captures running in the background. Bounded so the spoken
    // narration stays followable (spec: Voice UX design, M9).
    private var activeCaptureJobs = 0
    static let maxCaptureJobs = 3
    
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

        // Observability: correlate session trouble with the app moving
        // to and from the background (screen lock, app switch).
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main
        ) { _ in Diag.event("app", "background") }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { _ in Diag.event("app", "foreground") }
    }


    func startSession() {
        guard state == .idle else { return }
        Diag.resetDebugLog()
        Diag.event("sess", "starting")
        state = .starting
        lastError = nil
        Task { await start() }
    }

    private func start() async {
        wireCallbacks()

        // 1. Audio route first (M7: both orders worked, but this order
        //    also matches the documented recommendation).
        statusLine = "configuring audio"
        do {
            try route.activate()
        } catch {
            fail("audio route: \(error.localizedDescription)")
            return
        }

        // 2. Camera: startCamera kicks off an async chain; wait for the
        //    stream to actually reach streaming.
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

        // 5. The 10 minute session timer.
        startTimer()

        state = .active
        statusLine = route.isOnGlasses ? "listening (glasses)" : "listening (iPhone mic)"
        Diag.event("sess", "active, \(route.isOnGlasses ? "glasses" : "iPhone mic")")
    }
    
    // MARK: - End

    // The single exit, reached from every path: the UI button, the voice
    // command, the timer, GoAway, a lost socket, or the device itself.
    func endSession() {
        guard state == .active || state == .starting else { return }
        Diag.event("sess", "ending (\(lastError ?? "normal"))")
        state = .ending
        statusLine = "ending session"

        sessionTimer?.cancel()
        sessionTimer = nil
        remainingSeconds = 0

        // Tear down in reverse order of startup.
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

    // Connect the components to each other. Called once per session
    // start; the closures replace the previous session's wiring.
    private func wireCallbacks() {
        // Mic chunks up to Gemini (audio thread -> main actor hop).
        audioEngine.onMicChunk = { [weak self] data in
            Task { @MainActor in self?.gemini.sendAudioChunk(data) }
        }
        // Reply audio down to the speaker.
        gemini.onAudioChunk = { [weak self] data in
            self?.audioEngine.play(data)
        }
        // User talked over the model: drop the stale reply audio.
        gemini.onInterrupted = { [weak self] in
            self?.audioEngine.flushPlayback()
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

        gemini.onGoAway = { [weak self] in
            guard let self, self.state == .active else { return }
            self.lastError = "Gemini closed the connection (10 min limit)"
            self.endSession()
        }
        gemini.onDisconnect = { [weak self] in
            guard let self, self.state == .active else { return }
            self.lastError = "Gemini connection lost"
            self.endSession()
        }
        glasses.onDeviceSessionEnded = { [weak self] in
            guard let self, self.state == .active else { return }
            self.lastError = "glasses ended the session"
            self.endSession()
        }
    }

    // MARK: - Tool Calls 

    // handle Gemini's toolcall request 
    private func handleToolCall(id: String, name: String) {
        switch name {
        case "capture_object":
            guard activeCaptureJobs < Self.maxCaptureJobs else {
                Diag.event("tool", "busy: \(activeCaptureJobs) captures in flight")
                gemini.sendToolResponse(id: id, name: name, result: [
                    "status": "busy",
                    "message": "Too many captures are already processing. Ask the user to wait a moment.",
                ])
                return
            }
            activeCaptureJobs += 1

            // Two-phase response: the intermediate ack frees the model
            // within a second, so conversation and further captures keep
            // flowing while this one runs in the background.
            gemini.sendToolResponse(id: id, name: name,
                                    result: ["status": "capturing"],
                                    willContinue: true,
                                    scheduling: "SILENT")
            Task {
                await handleCapture(id: id, name: name)
                activeCaptureJobs -= 1
            }

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
            Diag.event("tool", "capture begin")
            let image = try await glasses.captureAndWait()
            Diag.event("tool", "photo ok")

            statusLine = "generating card"
            let card = try await CardAPI.generate(from: image)
            Diag.event("tool", "card ok: \(card.word)")

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
            Diag.event("tool", "toolResponse sent (saved)")
        } catch {
            statusLine = "capture failed"
            lastError = "capture: \(error.localizedDescription)"
            Diag.event("tool", "error: \(error.localizedDescription)")
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

    // Count down once a second so the UI can show time left, then end
    // the session at zero. Cancelled by endSession.
    private func startTimer() {
        remainingSeconds = Self.sessionLimitSeconds
        sessionTimer = Task { [weak self] in
            while let self, self.remainingSeconds > 0, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self.remainingSeconds -= 1
            }
            if let self, !Task.isCancelled, self.state == .active {
                self.statusLine = "time limit reached"
                self.endSession()
            }
        }
    }
}
