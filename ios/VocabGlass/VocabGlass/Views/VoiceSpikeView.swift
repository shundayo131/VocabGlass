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
    @StateObject private var gemini = GeminiLiveClient()
    @ObservedObject var client: GlassesClient 

    private let audio = LiveAudioEngine()

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
                  if let error = client.lastError {
                      Text(error)
                          .font(.footnote)
                          .foregroundStyle(.red)
                  }
                  Button(client.cameraOn ? "Stop camera" : "Start camera") {
                      client.cameraOn ? client.stopCamera() : client.startCamera()
                  }
                  Button("Capture photo") { client.capturePhoto() }
                      .disabled(!client.isReady)
                  Button("Update glasses DAT app") { client.openGlassesAppUpdate() }
                  if let image = client.capturedImage {
                      Image(uiImage: image)
                          .resizable()
                          .scaledToFit()
                          .frame(maxHeight: 160)
                  }
              }
              Section("Gemini Live") {
                Text(gemini.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let tool = gemini.lastToolCall {
                    Text("last tool call: \(tool)").font(.footnote)
                }
                Button(gemini.isConnected ? "Disconnect Gemini" : "Connect Gemini") {
                    gemini.isConnected ? gemini.disconnect() : gemini.connect()
                }
                // Voice chat 
                Button(audio.isRunning ? "Stop voice chat" : "Start voice chat") {
                    if audio.isRunning {
                        audio.stop()
                    } else {
                        // Mic chunks go up, reply chunks come back down.
                        audio.onMicChunk = { data in
                            Task { @MainActor in gemini.sendAudioChunk(data) }
                        }
                        gemini.onAudioChunk = { data in audio.play(data) }
                        do {
                            try audio.start()
                        } catch {
                            gemini.status = "audio engine failed: \(error.localizedDescription)"
                        }
                    }
                }
                .disabled(!gemini.isConnected)

                if let pending = gemini.pendingToolCall {
                    Button("Send dummy result for \(pending.name)") {
                        gemini.sendToolResponse(id: pending.id, name: pending.name, result: [
                            "status": "saved",
                            "word": "苹果",
                            "pronunciation": "píngguǒ",
                            "translation": "apple",
                            "example": "我想吃苹果。",
                        ])
                        gemini.pendingToolCall = nil
                    }
                }
            }
        }
        .navigationTitle("Voice Spike")
        .onAppear { spike.observeRouteChanges() }
    }
}
#endif 