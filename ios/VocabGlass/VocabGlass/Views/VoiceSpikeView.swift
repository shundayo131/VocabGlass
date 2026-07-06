//
//  VoiceSpikeView.swift
//  VocabGlass
//
//  Debug-only control panel for the M7 audio spike. Deleted after the spike.
//

#if DEBUG
import SwiftUI

struct VoiceSpikeView: View {
    @StateObject private var spike = AudioSpike()
    @ObservedObject var client: GlassesClient 

    var body: some View {
        List {
            Section("Audio (Bluetooth HFP)") {
                  Text(spike.routeText)
                      .font(.footnote)
                  Text(spike.status)
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                  Button("1. Configure audio") { spike.configureAudio() }
                  Button("2. Record 5 seconds") { spike.startRecording() }
                  Button("3. Play back") { spike.playRecording() }
                  Button("Record 60 s (lock test)") { spike.startRecording(seconds: 60) }
              }

              Section("Camera (DAT)") {
                  Text(client.status)
                      .font(.footnote)
                      .foregroundStyle(.secondary)
                  Button(client.cameraOn ? "Stop camera" : "Start camera") {
                      client.cameraOn ? client.stopCamera() : client.startCamera()
                  }
                  Button("Capture photo") { client.capturePhoto() }
                      .disabled(!client.isReady)
                  if let image = client.capturedImage {
                      Image(uiImage: image)
                          .resizable()
                          .scaledToFit()
                          .frame(maxHeight: 160)
                  }
              }
        }
        .navigationTitle("Voice Spike")
        .onAppear { spike.observeRouteChanges() }
    }
}
#endif 