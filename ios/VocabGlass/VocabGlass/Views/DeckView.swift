//
//  DeckView.swift
//  VocabGlass
//
//  The saved deck as a photo grid, Quiet style. Replaces HistoryView.
//  Four display states: loading, empty, error, populated. Loading and
//  error cannot occur with the current synchronous CardStore, but the
//  UI supports them so async storage can slot in later, and debug
//  builds can force them for screenshots.
//

import SwiftUI

enum DeckDisplayState: Equatable {
    case loading
    case empty
    case error(String)
    case populated
}

struct DeckView: View {
    @ObservedObject var store: CardStore

    // Debug-only override so screenshots and previews can show states
    // the live store never produces.
    private let forcedState: DeckDisplayState?

    @State private var selected: SavedCard?
    @State private var pendingDelete: SavedCard?
    @State private var isReviewing = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]
    private static let cornerRadius: CGFloat = 18

    init(store: CardStore, forcedState: DeckDisplayState? = nil) {
        self.store = store
        self.forcedState = forcedState
    }

    private var displayState: DeckDisplayState {
        if let forcedState { return forcedState }
        return store.cards.isEmpty ? .empty : .populated
    }

    var body: some View {
        NavigationStack {
            Group {
                switch displayState {
                case .loading:
                    ProgressView("Loading deck…")
                        .accessibilityIdentifier("deck.loading")

                case .empty:
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Captures from your sessions appear here.")
                    )
                    .accessibilityIdentifier("deck.empty")

                case .error(let message):
                    ContentUnavailableView(
                        "Couldn\u{2019}t load your deck",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                    .accessibilityIdentifier("deck.error")

                case .populated:
                    grid
                }
            }
            .navigationTitle("Deck")
            .sheet(item: $selected) { card in
                CardDetailView(store: store, card: card)
            }
            .fullScreenCover(isPresented: $isReviewing) {
                FlashcardReviewView(store: store, cards: store.cards)
            }
            .confirmationDialog(
                "Delete \u{201C}\(pendingDelete?.word ?? "")\u{201D}?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let card = pendingDelete { store.delete(card) }
                    pendingDelete = nil
                }
                .accessibilityIdentifier("deck.confirmDeleteButton")
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The card and its photo will be removed.")
            }
            #if DEBUG
            .onAppear {
                if UITestSupport.autoOpenReview { isReviewing = true }
            }
            #endif
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(store.cards) { card in
                    Button {
                        selected = card
                    } label: {
                        DeckTile(store: store, card: card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deck.tile.\(card.word)")
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = card
                        }
                    }
                }
            }
            .padding()
        }
        .accessibilityIdentifier("deck.grid")
        .safeAreaInset(edge: .bottom) {
            Button {
                isReviewing = true
            } label: {
                Label("Review \(store.cards.count) cards", systemImage: "play.fill")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .clipShape(Capsule())
            .padding(.bottom, 8)
            .accessibilityIdentifier("deck.reviewButton")
        }
    }
}

// Photo tile with a glass caption bar.
private struct DeckTile: View {
    let store: CardStore
    let card: SavedCard

    var body: some View {
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
        .frame(minHeight: 150)
        .aspectRatio(1, contentMode: .fill)
        .overlay(alignment: .bottom) {
            HStack(spacing: 6) {
                Text(card.word)
                    .font(.subheadline.weight(.semibold))
                Text(card.pinyin)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.word), \(card.translation)")
    }
}
