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
    @Published var isReady = false       // stream is streaming, capture allowed
    @Published var status = "starting"
    @Published var lastError: String?

    // MARK: - DAT handles

    private let wearables = Wearables.shared
    private lazy var selector = AutoDeviceSelector(wearables: wearables)
    private var session: DeviceSession?
    private var stream: MWDATCamera.Stream?
    private var didStart = false
    private var streamStarted = false

    // Listener tokens must be retained, or the SDK drops the listeners.
    private var photoToken: (any AnyListenerToken)?
    private var stateToken: (any AnyListenerToken)?
    private var registrationTask: Task<Void, Never>?

    // MARK: - Start

    func start() {
        guard !didStart else { return }
        didStart = true
        #if targetEnvironment(simulator)
        setUpMockDevice()
        observeRegistration()
        Task { await startStream() }
        #else
        // Real device: stream starts once registered (see observeRegistration).
        observeRegistration()
        #endif
    }

    // MARK: - Registration (real device)

    private func observeRegistration() {
        registrationState = wearables.registrationState
        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                self.registrationState = state
                #if !targetEnvironment(simulator)
                if state == .registered, !self.streamStarted {
                    self.streamStarted = true
                    await self.startStream()
                }
                #endif
            }
        }
        #if !targetEnvironment(simulator)
        if wearables.registrationState == .registered, !streamStarted {
            streamStarted = true
            Task { await startStream() }
        } else if wearables.registrationState != .registered {
            status = "not registered — tap Connect glasses"
        }
        #endif
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

            stateToken = stream.statePublisher.listen { [weak self] state in
                Task { @MainActor in
                    self?.status = "stream: \(state)"
                    self?.isReady = (state == .streaming)   // capture only while streaming
                }
            }
            photoToken = stream.photoDataPublisher.listen { [weak self] photo in
                Task { @MainActor in
                    self?.capturedImage = UIImage(data: photo.data)
                    self?.status = "photo captured"
                }
            }

            await stream.start()
        } catch {
            lastError = "\(error.localizedDescription)"
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
        let device = MockDeviceKit.shared.pairRaybanMeta()

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
    }
    #endif
}
