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
        // so wait until the selector reports one.
        status = "waiting for device"
        for await device in selector.activeDeviceStream() {
            if device != nil { break }
        }

        do {
            let session = try wearables.createSession(deviceSelector: selector)
            try session.start()
            status = "starting session"

            // stateStream does not buffer, so check the current state first.
            if session.state != .started {
                for await state in session.stateStream() {
                    if state == .started { break }
                }
            }

            let config = StreamConfiguration(videoCodec: .raw, resolution: .medium, frameRate: 24)
            guard let stream = try session.addStream(config: config) else {
                lastError = "could not add stream"
                return
            }
            self.session = session
            self.stream = stream

            // Surface why the device stops the session, if it does.
            observeSessionErrors(session)

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
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() {
        card = nil
        stream?.capturePhoto(format: .jpeg)
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
