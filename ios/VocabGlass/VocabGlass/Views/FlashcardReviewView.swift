//
//  FlashcardReviewView.swift
//  VocabGlass
//
//  One pass through the deck as flashcards, Quiet style. The image comes
//  first; Show answer reveals the word, pronunciation, meaning, and
//  example. All review state lives in FlashcardSession; this view only
//  renders it. Cards come in deck order (newest first).
//

import SwiftUI

struct FlashcardReviewView: View {
    @ObservedObject var store: CardStore
    @StateObject private var session: FlashcardSession
    @Environment(\.dismiss) private var dismiss

    init(store: CardStore, cards: [SavedCard]) {
        self.store = store
        _session = StateObject(wrappedValue: FlashcardSession(cards: cards))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProgressView(value: Double(min(session.index, session.total)),
                             total: Double(max(session.total, 1)))

                if let card = session.current {
                    Text("\(session.position) of \(session.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    photo(for: card)

                    if session.isRevealed {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(card.word).font(.largeTitle.bold())
                                    Text(card.pinyin).font(.title3).foregroundStyle(.secondary)
                                }
                                Text(card.translation).font(.headline)
                                Text(card.example).font(.body).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityIdentifier("review.answer")
                    }

                    Spacer(minLength: 0)

                    if session.isRevealed {
                        Button {
                            session.next()
                        } label: {
                            Label("Next", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("review.nextButton")
                    } else {
                        Button {
                            session.reveal()
                        } label: {
                            Label("Show answer", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .accessibilityIdentifier("review.showAnswerButton")
                    }
                } else {
                    Spacer()
                    ContentUnavailableView {
                        Label("All done", systemImage: "checkmark.circle")
                    } description: {
                        Text("You reviewed \(session.total) cards.")
                    } actions: {
                        Button("Start over") {
                            session.restart()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("review.restartButton")
                    }
                    .accessibilityIdentifier("review.finished")
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("review.closeButton")
                }
            }
            #if DEBUG
            .onAppear {
                if UITestSupport.autoReveal { session.reveal() }
            }
            #endif
        }
    }

    private func photo(for card: SavedCard) -> some View {
        Group {
            if let image = store.image(for: card) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.2)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("review.photo")
    }
}
