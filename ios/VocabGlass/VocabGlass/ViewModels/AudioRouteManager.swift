//
//  AudioRouteManager.swift
//  VocabGlass
//
//  Owns the OS audio session for a voice session: claims play-and-record
//  with Bluetooth HFP, points the input at the glasses, and re-points it
//  when something (like Hey Meta) steals the route.
//

import Foundation 
import AVFoundation 
import Combine 

@MainActor
final class AudioRouteManager: ObservableObject {

    // MARK: - State the UI reads 

    @Published var routeText = "audio not configured"
    @Published var isOnGlasses = false

    // Fired when the route changes while active after the recovery attempt
    // The session controller uses it to update its status 
    var onRouteChange: ((_ isOnGlasses: Bool) -> Void)?

    private var routeObserver: NSObjectProtocol?
    private var isActive = false
    
    // MARK: - Activate / deactivate 

    // Claim the audio session for two-way voice with Bluetooth allowed,
    // and prefer the glasses mic when one is connected. Falls back to the
    // iPhone mic and speaker (useful for glasses-free testing)
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                        mode: .voiceChat,
                        options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true)
        preferGlassesInput()
        startMonitoring()
        isActive = true
        updateRoute()
    }

    func deactivate() {
        if let observer = routeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeObserver = nil
        }
        isActive = false 
        // notifyOthersOnDeactivation lets music or Meta AI resume clearnly 
        try? AVAudioSession.sharedInstance()
          .setActive(false, options: [.notifyOthersOnDeactivation])
        routeText = "audio not configured"
        isOnGlasses = false
    }

    // MARK: - Route handling 

    // Point the input at the glasses HFP port if one is available 
    // Returns whether the glasses were found 
    @discardableResult 
    private func preferGlassesInput() -> Bool {
        let session = AVAudioSession.sharedInstance()
        guard let hfp = session.availableInputs?
          .first(where: { $0.portType == .bluetoothHFP }) else { return false }
        try? session.setPreferredInput(hfp)
        return true
    }

    // Watch for the route moving while a session is active. 
    // If the glasses come back (Hey Meta released the mic, glasses reconnected)
    // re-point the input at them. 
    private func startMonitoring() {
        guard routeObserver == nil else { return }
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.preferGlassesInput()
                self.updateRoute()
                self.onRouteChange?(self.isOnGlasses)
            }
        }
    }

    private func updateRoute() {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs
            .map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
        let outputs = route.outputs
            .map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
        routeText = "in: \(inputs.isEmpty ? "none" : inputs)\nout: \(outputs.isEmpty ? "none" : outputs)"
        isOnGlasses = route.inputs.contains { $0.portType == .bluetoothHFP }
    }
}