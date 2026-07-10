//
//  GlassesClient.swift
//  VocabGlass
//
//  Owns the DAT session and stream, and the captured photo.
//

import Foundation
import Combine
import UIKit
import MWDATCore
import MWDATCamera
import MWDATMockDevice   // simulator-only mock. Removed around M5.

@MainActor
final class GlassesClient: ObservableObject {

    // MARK: - State the UI reads

    @Published var capturedImage: UIImage?
    @Published var card: LearningCard?
    @Published var isGenerating = false
    @Published var registrationState: RegistrationState = .unavailable
    @Published var cameraOn = false      // user asked for the camera
    @Published var isReady = false       // stream is streaming, capture allowed
    @Published var status = "starting"
    @Published var lastError: String?

    // Fired when the device ends the DAT session on its own (thermal,
    // battery, glasses folded). The session controller ends the whole
    // voice session in response.
    var onDeviceSessionEnded: (() -> Void)?

    // MARK: - DAT handles

    private let wearables = Wearables.shared
    private lazy var selector = AutoDeviceSelector(wearables: wearables)
    private var session: DeviceSession?
    private var stream: MWDATCamera.Stream?
    private var didStart = false

    // Listener tokens must be retained, or the SDK drops the listeners.
    private var photoToken: (any AnyListenerToken)?
    private var stateToken: (any AnyListenerToken)?
    private var errorToken: (any AnyListenerToken)?
    private var registrationTask: Task<Void, Never>?

    // MARK: - Start

    func start() {
        guard !didStart else { return }
        didStart = true
        #if targetEnvironment(simulator)
        setUpMockDevice()
        #endif
        observeRegistration()
        status = "tap Start camera"
    }

    // On-demand: open the camera stream when the user asks for it.
    func startCamera() {
        guard !cameraOn else { return }
        cameraOn = true
        Task { await startStream() }
    }

    // Close the stream and session, back to idle.
    func stopCamera() {
        stateToken = nil
        errorToken = nil
        photoToken = nil
        stream?.stop()
        stream = nil
        session?.stop()
        session = nil
        isReady = false
        cameraOn = false
        status = "tap Start camera"
    }

    // MARK: - Registration (real device)

    private func observeRegistration() {
        registrationState = wearables.registrationState
        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                self.registrationState = state
            }
        }
    }

    // Open the Meta AI app to register. Result returns via handleUrl(_:).
    func connectGlasses() {
        guard registrationState != .registering else { return }
        Task {
            do {
                try await wearables.startRegistration()
            } catch {
                lastError = "registration: \(error.localizedDescription)"
            }
        }
    }

    // Called from the app's onOpenURL when Meta AI returns to us.
    func handleUrl(_ url: URL) {
        Task { _ = try? await wearables.handleUrl(url) }
    }

    // Open the Meta AI app on the update screen for the glasses-side DAT
    // app. Needed when the session dies with an update-required error.
    func openGlassesAppUpdate() {
        Task {
            do {
                try await wearables.openDATGlassesAppUpdate()
            } catch {
                lastError = "update navigation: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Streaming

    private func startStream() async {
        // Camera permission must be granted first, or the device ends the
        // session the moment we try to stream. On the mock it is already granted.
        do {
            status = "checking camera permission"
            var permission = try await wearables.checkPermissionStatus(.camera)
            if permission != .granted {
                permission = try await wearables.requestPermission(.camera)
            }
            guard permission == .granted else {
                lastError = "camera permission not granted"
                cameraOn = false
                status = "tap Start camera"
                return
            }
        } catch {
            lastError = "permission: \(error.localizedDescription)"
            cameraOn = false
            status = "tap Start camera"
            return
        }

        // AutoDeviceSelector resolves an eligible device asynchronously.
        // Creating a session before a device is active throws noEligibleDevice,
        // so wait until the selector reports one. Check the current value
        // first: the stream only delivers changes, and the device may
        // already be active.
        if selector.activeDevice == nil {
            status = "waiting for device"
            for await device in selector.activeDeviceStream() {
                if device != nil { break }
            }
        }

        do {
            let session = try wearables.createSession(deviceSelector: selector)

            // Watch for session errors before start(), not after addStream:
            // if the device kills the session during startup, the reason
            // only shows up here.
            observeSessionErrors(session)

            try session.start()
            status = "starting session (now: \(session.state))"

            // Wait for .started by polling the live state. Waiting on
            // stateStream() can hang forever if the transition happens
            // before the subscription (seen on device with DAT 0.8):
            // the event is gone and no new one ever comes. Polling the
            // property cannot miss anything, and a timeout turns a
            // silent hang into a visible error.
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while session.state != .started {
                if session.state == .stopped {
                    // The device killed the session during startup. The
                    // reason arrives on the error stream; give it a beat
                    // to land before giving up.
                    try await Task.sleep(for: .milliseconds(500))
                    if lastError == nil { lastError = "session stopped during start (no error reported)" }
                    cameraOn = false
                    status = "tap Start camera"
                    return
                }
                if ContinuousClock.now > deadline {
                    lastError = "session never reached started (state: \(session.state))"
                    session.stop()
                    cameraOn = false
                    status = "tap Start camera"
                    return
                }
                status = "session state: \(session.state)"
                try await Task.sleep(for: .milliseconds(200))
            }

            let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 24)
            guard let stream = try session.addStream(config: config) else {
                lastError = "could not add stream"
                return
            }
            self.session = session
            self.stream = stream

            stateToken = stream.statePublisher.listen { state in
                Task { @MainActor [weak self] in
                    self?.status = "stream: \(state)"
                    self?.isReady = (state == .streaming)   // capture only while streaming
                }
            }
            errorToken = stream.errorPublisher.listen { error in
                Task { @MainActor [weak self] in
                    self?.lastError = "stream error: \(error.localizedDescription)"
                }
            }
            photoToken = stream.photoDataPublisher.listen { photo in
                Task { @MainActor [weak self] in
                    self?.capturedImage = UIImage(data: photo.data)
                    self?.status = "photo captured"
                }
            }

            stream.start()
        } catch {
            lastError = "\(error.localizedDescription)"
            cameraOn = false
            status = "tap Start camera"
        }
    }

    private func observeSessionErrors(_ session: DeviceSession) {
        Task {
            for await error in session.errorStream() {
                self.lastError = "session error: \(error.localizedDescription)"
                // The device ended the session. Go back to idle so the user can
                // start the camera again when ready.
                self.stopCamera()
                self.onDeviceSessionEnded?()
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        card = nil
        stream?.capturePhoto(format: .jpeg)
    }

    // One-shot capture continuation. Non-nil while a captureAndWait is in fight
    // finishCapture empties it, which is what guarantees the continuation is resumed exactly once
    private var pendingCapture: CheckedContinuation<UIImage, Error>?
    private var pendingCaptureToken: (any AnyListenerToken)?
    private var pendingCaptureTimeout: Task<Void, Never>? 

    // Capture a photo and wait for it to arrive. 
    // Bridges the fire-and-forget capturePhoto + publisher pair into one awaitable call for the session controller
    func captureAndWait(timeoutSeconds: TimeInterval = 10) async throws -> UIImage{
        guard let stream, isReady else {
            throw NSError(domain: "GlassesClient", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "camera is not streaming"])
        }
        guard pendingCapture == nil else {
            throw NSError(domain: "GlassesClient", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "capture already in progress"])
        }

        return try await withCheckedThrowingContinuation { continuation in 
            pendingCapture = continuation 

            // Subscribe before triggering, so a fast photo cannot slip past 
            pendingCaptureToken = stream.photoDataPublisher.listen { photo in
                Task { @MainActor [weak self] in
                    self?.capturedImage = UIImage(data: photo.data)
                    self?.status = "photo captured"
                    self?.finishCapture(with: .success(photo.data))
                }
            }

            // The photo and this timeout race
            // finishCapture decides the winner and ignores the loser 
            pendingCaptureTimeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                self?.finishCapture(with: .failure(NSError(
                    domain: "GlassesClient", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "capture timed out"])))
            }

            status = "capturing..."
            stream.capturePhoto(format: .jpeg)
        }
    }

    // The single exit for a pending capture.
    // First caller wins; everyone after finds pendingCapture nil and does nothing
    private func finishCapture(with result: Result<Data, Error>) {
        guard let continuation = pendingCapture else { return }
        pendingCapture = nil
        pendingCaptureToken = nil
        pendingCaptureTimeout?.cancel()
        pendingCaptureTimeout = nil

        switch result {
        case .success(let data):
            if let image = UIImage(data: data) {
                continuation.resume(returning: image)
            } else {
                continuation.resume(throwing: NSError(
                    domain: "GlassesClient", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "photo data was not an image"]))
            }
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Card generation

    func generateCard() {
        guard let image = capturedImage, !isGenerating else { return }
        isGenerating = true
        lastError = nil
        Task {
            do {
                card = try await CardAPI.generate(from: image)
            } catch {
                lastError = "card: \(error.localizedDescription)"
            }
            isGenerating = false
        }
    }

    // MARK: - Mock (simulator only)

    #if targetEnvironment(simulator)
    private func setUpMockDevice() {
        MockDeviceKit.shared.enable()
        do {
            let device = try MockDeviceKit.shared.pairGlasses(model: .rayBanMeta)

            // Drive the device to a worn, available state, like the sample's debug menu.
            device.powerOn()
            device.unfold()
            device.don()

            // Feed the mock a video so the stream actually streams, and a still so
            // capturePhoto returns an image. These are Meta's sample test resources.
            let camera = device.services.camera
            if let videoURL = Bundle.main.url(forResource: "plant", withExtension: "mp4") {
                camera.setCameraFeed(fileURL: videoURL)
            }
            if let imageURL = Bundle.main.url(forResource: "plant", withExtension: "png") {
                camera.setCapturedImage(fileURL: imageURL)
            }
        } catch {
            lastError = "mock setup: \(error.localizedDescription)"
        }
    }
    #endif
}
