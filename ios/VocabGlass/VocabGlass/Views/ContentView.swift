//
//  ContentView.swift
//  VocabGlass
//

import SwiftUI
import MWDATCore

struct ContentView: View {
    @ObservedObject var client: GlassesClient
    @ObservedObject var store: CardStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {

            Group {
                if let image = client.capturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.gray.opacity(0.15))
                        .overlay(Text("No photo yet").foregroundStyle(.secondary))
                }
            }
            .frame(maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(client.status)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if client.registrationState != .registered {
                Button {
                    client.connectGlasses()
                } label: {
                    Label("Connect glasses", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else if !client.cameraOn {
                Button {
                    client.startCamera()
                } label: {
                    Label("Start camera", systemImage: "video.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Button(role: .destructive) {
                    client.stopCamera()
                } label: {
                    Label("Stop camera", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Button {
                client.capturePhoto()
            } label: {
                Label("Capture photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!client.isReady)

            if client.capturedImage != nil {
                Button {
                    client.generateCard()
                } label: {
                    Label(client.isGenerating ? "Generating…" : "Generate card",
                          systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(client.isGenerating)
            }

            if let card = client.card {
                CardView(card: card)
                Button {
                    if let image = client.capturedImage {
                        store.save(card, image: image)
                        client.card = nil
                    }
                } label: {
                    Label("Save to deck", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if let error = client.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()
            }
            .padding()
            .navigationTitle("VocabGlass")
            .toolbar {
                #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink("Spike") { VoiceSpikeView(client: client) }
                }
                #endif
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        HistoryView(store: store)
                    } label: {
                        Label("Deck", systemImage: "rectangle.stack")
                    }
                }
            }
            .onAppear { client.start() }
            .onOpenURL { url in client.handleUrl(url) }
        }
    }
}

struct CardView: View {
    let card: LearningCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(card.word).font(.largeTitle.bold())
                Text(card.pinyin).font(.title3).foregroundStyle(.secondary)
            }
            Text(card.translation).font(.headline)
            Text(card.example).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
