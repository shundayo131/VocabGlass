//
//  FlashcardSessionTests.swift
//  VocabGlassTests
//
//  FlashcardSession state machine: reveal, next, finish, restart, and
//  the empty deck edge case.
//

import Testing
import Foundation
@testable import VocabGlass

@MainActor
struct FlashcardSessionTests {

    private func card(_ word: String) -> SavedCard {
        SavedCard(id: UUID(), word: word, pinyin: "pin", translation: "meaning",
                  example: "example", imageFileName: "x.jpg", createdAt: Date())
    }

    private var deck: [SavedCard] {
        [card("一"), card("二"), card("三")]
    }

    @Test func startsAtFirstCardUnrevealed() {
        let session = FlashcardSession(cards: deck)
        #expect(session.current?.word == "一")
        #expect(!session.isRevealed)
        #expect(!session.isFinished)
        #expect(session.position == 1)
        #expect(session.total == 3)
    }

    @Test func revealShowsTheAnswer() {
        let session = FlashcardSession(cards: deck)
        session.reveal()
        #expect(session.isRevealed)
        #expect(session.current?.word == "一")
    }

    @Test func nextAdvancesAndHidesTheAnswer() {
        let session = FlashcardSession(cards: deck)
        session.reveal()
        session.next()
        #expect(session.current?.word == "二")
        #expect(!session.isRevealed)
    }

    @Test func finishesAfterTheLastCard() {
        let session = FlashcardSession(cards: deck)
        for _ in 0..<3 { session.next() }
        #expect(session.isFinished)
        #expect(session.current == nil)
        // Calls past the end stay put instead of trapping.
        session.next()
        session.reveal()
        #expect(session.isFinished)
        #expect(!session.isRevealed)
    }

    @Test func emptyDeckIsFinishedImmediately() {
        let session = FlashcardSession(cards: [])
        #expect(session.isFinished)
        #expect(session.current == nil)
        #expect(session.total == 0)
        session.reveal()
        #expect(!session.isRevealed)
    }

    @Test func restartGoesBackToTheFirstCardUnrevealed() {
        let session = FlashcardSession(cards: deck)
        session.reveal()
        session.next()
        session.next()
        session.restart()
        #expect(session.current?.word == "一")
        #expect(!session.isRevealed)
        #expect(session.position == 1)
    }
}
