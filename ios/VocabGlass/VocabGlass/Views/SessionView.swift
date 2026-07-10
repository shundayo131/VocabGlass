//
//  SessionView.swift
//  VocabGlass
//
//  The live voice session screen: state, time left, last saved card,
//  and the start/end buttons. Reads SessionController and renders it.
//

import SwiftUI

struct SessionView: View {
    @ObservedObject var controller: SessionController
    @ObservedObject var store: CardStore

    var body: some View {
        VStack(spacing: 16) {
            Text(controller.state.rawValue)
                .font(.headline)
            Text(controller.statusLine)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if controller.state == .active {
                Text(timeLeft)
                    .font(.system(.title, design: .monospaced))
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            // The newest card, so the demo shows each capture landing.
            if let card = store.cards.first {
                VStack(alignment: .leading, spacing: 4) {
                    if let image = store.image(for: card) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    Text("\(card.word)  \(card.pinyin)")
                        .font(.headline)
                    Text(card.translation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if controller.state == .idle {
                Button {
                    controller.startSession()
                } label: {
                    Label("Start session", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button(role: .destructive) {
                    controller.endSession()
                } label: {
                    Label("End session", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(controller.state != .active)
            }
        }
        .padding()
        .navigationTitle("Voice session")
    }

    private var timeLeft: String {
        String(format: "%02d:%02d",
               controller.remainingSeconds / 60,
               controller.remainingSeconds % 60)
    }
}