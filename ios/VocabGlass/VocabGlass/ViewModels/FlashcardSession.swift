//
//  FlashcardSession.swift
//  VocabGlass
//
//  One pass through a deck of saved cards. The image comes first, then the
//  learner reveals the word, pronunciation, meaning, and example.
//
//  This holds review state only. Nothing here is persisted, and there is no
//  scheduling: spaced repetition is out of scope.
//

import Foundation
import Combine

@MainActor
final class FlashcardSession: ObservableObject {
    @Published private(set) var index = 0
    @Published private(set) var isRevealed = false

    private let cards: [SavedCard]

    // Takes the deck in the order it should be reviewed. Shuffling is the
    // caller's job, which keeps this predictable.
    init(cards: [SavedCard]) {
        self.cards = cards
    }

    // The card being shown, or nil once the deck is done.
    var current: SavedCard? {
        index < cards.count ? cards[index] : nil
    }

    var isFinished: Bool {
        index >= cards.count
    }

    var total: Int {
        cards.count
    }

    // 1-based position for display, clamped to the deck size.
    var position: Int {
        min(index + 1, cards.count)
    }

    // Show the answer for the current card.
    func reveal() {
        guard !isFinished else { return }
        isRevealed = true
    }

    // Move to the next card, hiding the answer again.
    func next() {
        guard !isFinished else { return }
        index += 1
        isRevealed = false
    }

    // Start the same deck over from the first card.
    func restart() {
        index = 0
        isRevealed = false
    }
}
