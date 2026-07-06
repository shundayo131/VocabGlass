//
//  AVAudioSession.swift
//  VocabGlass
//
//  Throwaway spike - verify glasses mic/speaker over Bluetooth HFP, 
//  Alongside the DAT camera stream. Will be thrown away once we've verified the audio path workes  

import Foundation 
import AVFoundation
import Combine

@MainActor 
final class AudioSpike: NSObject, ObservableObject {

    // MARK: - State the UI reads 

    @Published var routeText = "audio not configured"
    @Published var status = "idle"
    @Published var isRecording = false     

    // MARK: - Private 

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var routeObserver: NSObjectProtocol? 

    // One scratch file in tmp, overwritten on every recording 
    private let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("spike.m4a") 

    // MARK: - Audio session 

    // Shared audio session for two-way audio with Bluetooth headsets allowed,
    // then point the input at the glasses
    //
    // AVAudioSession is a process wide singleton owned by the OS.
    // We don't talk to Bluetooth directly
    // We declare what we need (record+play, HFP allowed) and the OS picks the route
    func configureAudio() {
        // session instance
        let session = AVAudioSession.sharedInstance() 
        do {
            // .voiceChat mode tunes the session for two-way speach and enables echo cancellation. 
            // On older SDKs the option is named .allowBluetooth instead of .allowBluetoothHFP 
            try session.setCategory(.playAndRecord, 
                                    mode: .voiceChat, 
                                    options: [.allowBluetoothHFP]
            )
            // Activate the session with the defined category and mode 
            try session.setActive(true)

            // The category option only permits HFP. 
            // To make sure the input is the glasses and not the iPhone mic, 
            // set it exlicitly 
            if let hfp = session.availableInputs?
                .first(where: { $0.portType == .bluetoothHFP }) {
                try session.setPreferredInput(hfp)
                status = "audio configured, input: \(hfp.portName)"
            } else {
                status = "no Bluetooth HFP input found. Are the glasses connected as a headset?"
            }
            updateRouteText()
        } catch {
            status = "audio error: \(error.localizedDescription)"
        }
    }

    // Watch for the route moving (glasses disconnect, another app grabbing the mic)
    // Fires on any change while testing 
    func observeRouteChanges() {
        // Only one observer at a time 
        guard routeObserver == nil else { return }

        // Observe route changes and update the UI
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                self?.updateRouteText()
                self?.status = "audio route changed" // trigger a UI update
            }
        }
    }

    // Stop observing route changes
    private func updateRouteText() {
        let route = AVAudioSession.sharedInstance().currentRoute 
        let inputs = route.inputs
            .map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
        let outputs = route.outputs
            .map { "\($0.portName) [\($0.portType.rawValue)]" }
            .joined(separator: ", ")
        routeText = "in: \(inputs.isEmpty ? "none" : inputs)\nout: \(outputs.isEmpty ? "none" : outputs)"
    }

    // MARK: - Record

    // Default 5 seconds for the loopback check. Pass 60 for the
    // lock-the-phone background test.
     func startRecording(seconds: TimeInterval = 5) {
        // Don't start a new recording if one is already in progress
        guard !isRecording else { return }

        Task {
            // iOS 17+ permission API. This class is @MainActor, so after
            // the await we are back on the main actor automatically.
            guard await AVAudioApplication.requestRecordPermission() else {
                status = "microphone permission denied"
                return
            }
            record(seconds: seconds)
        }
    }

    
    private func record(seconds: TimeInterval) {
        do {
            // AAC mono at 16kHz - more than enough to judge HFP quality 
            // which tops out at 8 kHz anyway 
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
            ]

            // Create the recorder and start recording for the specified duration
            let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: seconds)
            self.recorder = recorder
            isRecording = true 
            status = "recording for \(Int(seconds)) seconds..."
        } catch {
            status = "record error: \(error.localizedDescription)"
        }
    }

    // MARK: - Play back 

    // WIth HFP active this should come out of the glasses speaker, 
    // not the iPhone speaker 
    func playRecording() {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.play()
            self.player = player
            status = "playing back..."
            updateRouteText()
        } catch {
            status = "playback error: \(error.localizedDescription)"
        }
    }
}


// MARK: - AVAudioRecorderDelegate 

extension AudioSpike: AVAudioRecorderDelegate {
    // Delegate callbacks arrive off the main actor, so hop back before
    // touching @Published state.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder,
                                                    successfully flag: Bool) {
        Task { @MainActor in
            self.isRecording = false
            self.status = flag ? "recording done, tap Play back" : "recording failed"
        }
    }
}
