//
//  SessionController.swift
//  VocabGlass
//
//  The conductor of a voice session: starts and stops the DAT camera,
//  audio route, and OpenAI Realtime connection as one unit, and turns
//  tool calls into real app actions. The only class that knows all the
//  other components.
//

import Foundation
import Combine
import AVFoundation

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

    // MARK: - Dependencies

    // Shared with v1 screens. injected.
    private let glasses: GlassesClient
    private let store: CardStore

    // Session only, owned here.
    private let realtime = RealtimeClient()
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
        wireCallbacks()

        // 1. Mic permission, then the audio route, so WebRTC finds the
        //    glasses mic already selected when it starts capturing.
        guard await AVAudioApplication.requestRecordPermission() else {
            fail("microphone permission denied")
            return
        }
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

        // 3. OpenAI. connect() also kicks off an async chain; audio
        //    flows both ways over WebRTC once the session is created.
        statusLine = "connecting to OpenAI"
        realtime.connect()
        guard await waitUntil(timeoutSeconds: 15, { self.realtime.isConnected }) else {
            fail("OpenAI did not connect: \(realtime.status)")
            return
        }

        // 4. The 10 minute session timer.
        startTimer()

        state = .active
        statusLine = route.isOnGlasses ? "listening (glasses)" : "listening (iPhone mic)"
    }

    // MARK: - End

    // The single exit, reached from every path: the UI button, the voice
    // command, the timer, a lost connection, or the device itself.
    func endSession() {
        guard state == .active || state == .starting else { return }
        state = .ending
        statusLine = "ending session"

        sessionTimer?.cancel()
        sessionTimer = nil
        remainingSeconds = 0

        // Tear down in reverse order of startup.
        realtime.disconnect()
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
        // Tool calls into app actions.
        realtime.onToolCall = { [weak self] callId, name in
            self?.handleToolCall(callId: callId, name: name)
        }

        // Route moves (Hey Meta, glasses off) update the status line.
        route.onRouteChange = { [weak self] isOnGlasses in
            guard let self, self.state == .active else { return }
            self.statusLine = isOnGlasses ? "listening (glasses)" : "listening (iPhone mic)"
        }

        realtime.onDisconnect = { [weak self] in
            guard let self, self.state == .active else { return }
            self.lastError = "OpenAI connection lost"
            self.endSession()
        }
        glasses.onDeviceSessionEnded = { [weak self] in
            guard let self, self.state == .active else { return }
            self.lastError = "glasses ended the session"
            self.endSession()
        }
    }

    // MARK: - Tool Calls

    private func handleToolCall(callId: String, name: String) {
        switch name {
        case "capture_object":
            Task { await handleCapture(callId: callId) }

        case "end_session":
            // Answer first so the model can say goodbye, then tear down.
            realtime.sendToolResult(callId: callId, result: ["status": "ending"])
            endSession()

        default:
            realtime.sendToolResult(callId: callId, result: [
                "status": "error",
                "message": "unknown tool \(name)",
            ])
        }
    }

    // photo -> card -> save -> spoken confirmation.
    // Always answers the tool call, success or failure,
    // so the model never waits forever.
    private func handleCapture(callId: String) async {
        do {
            statusLine = "capturing photo"
            let image = try await glasses.captureAndWait()

            statusLine = "generating card"
            let card = try await CardAPI.generate(from: image)

            store.save(card, image: image)
            statusLine = "saved: \(card.word)"

            realtime.sendToolResult(callId: callId, result: [
                "status": "saved",
                "word": card.word,
                "pronunciation": card.pinyin,
                "translation": card.translation,
                "example": card.example,
            ])
        } catch {
            statusLine = "capture failed"
            lastError = "capture: \(error.localizedDescription)"
            realtime.sendToolResult(callId: callId, result: [
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
