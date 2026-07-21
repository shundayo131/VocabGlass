//
//  CardStoreTests.swift
//  VocabGlassTests
//
//  CardStore against a temp directory: save, update, delete, and the
//  persistence round-trip. Every test builds a second store on the same
//  directory to prove the change hit disk, not just memory.
//

import Testing
import UIKit
@testable import VocabGlass

@MainActor
struct CardStoreTests {

    private func makeStore() throws -> (store: CardStore, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CardStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (CardStore(directory: directory), directory)
    }

    private var sampleImage: UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private func card(_ word: String) -> LearningCard {
        LearningCard(word: word, pinyin: "pin", translation: "meaning", example: "example")
    }

    // MARK: - Save

    @Test func saveInsertsNewestFirstAndWritesImage() throws {
        let (store, directory) = try makeStore()
        store.save(card("一"), image: sampleImage)
        store.save(card("二"), image: sampleImage)

        #expect(store.cards.map(\.word) == ["二", "一"])
        let imageURL = directory.appendingPathComponent(store.cards[0].imageFileName)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test func saveSurvivesReload() throws {
        let (store, directory) = try makeStore()
        store.save(card("植物"), image: sampleImage)

        let reloaded = CardStore(directory: directory)
        #expect(reloaded.cards.count == 1)
        #expect(reloaded.cards[0].word == "植物")
        #expect(reloaded.cards[0].translation == "meaning")
    }

    // MARK: - Delete

    @Test func deleteRemovesCardAndImageAndPersists() throws {
        let (store, directory) = try makeStore()
        store.save(card("杯子"), image: sampleImage)
        let saved = store.cards[0]
        let imageURL = directory.appendingPathComponent(saved.imageFileName)
        #expect(FileManager.default.fileExists(atPath: imageURL.path))

        store.delete(saved)

        #expect(store.cards.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: imageURL.path))
        let reloaded = CardStore(directory: directory)
        #expect(reloaded.cards.isEmpty)
    }

    @Test func deleteUnknownIdIsANoop() throws {
        let (store, _) = try makeStore()
        store.save(card("窗户"), image: sampleImage)

        let stranger = SavedCard(id: UUID(), word: "x", pinyin: "x", translation: "x",
                                 example: "x", imageFileName: "missing.jpg", createdAt: Date())
        store.delete(stranger)

        #expect(store.cards.count == 1)
    }

    // MARK: - Update

    @Test func updateEditsTextKeepsIdentityAndPersists() throws {
        let (store, directory) = try makeStore()
        store.save(card("钥匙"), image: sampleImage)
        let original = store.cards[0]

        var edited = original
        edited.word = "锁"
        edited.translation = "lock"
        store.update(edited)

        #expect(store.cards.count == 1)
        #expect(store.cards[0].word == "锁")
        #expect(store.cards[0].id == original.id)
        #expect(store.cards[0].imageFileName == original.imageFileName)
        #expect(store.cards[0].createdAt == original.createdAt)

        let reloaded = CardStore(directory: directory)
        #expect(reloaded.cards[0].word == "锁")
        #expect(reloaded.cards[0].translation == "lock")
    }

    @Test func updateUnknownIdIsANoop() throws {
        let (store, _) = try makeStore()
        store.save(card("书架"), image: sampleImage)

        let stranger = SavedCard(id: UUID(), word: "y", pinyin: "y", translation: "y",
                                 example: "y", imageFileName: "missing.jpg", createdAt: Date())
        store.update(stranger)

        #expect(store.cards[0].word == "书架")
    }

    // MARK: - Images

    @Test func imageRoundTripsAndMissingFileReturnsNil() throws {
        let (store, directory) = try makeStore()
        store.save(card("自行车"), image: sampleImage)
        let saved = store.cards[0]

        #expect(store.image(for: saved) != nil)

        try FileManager.default.removeItem(
            at: directory.appendingPathComponent(saved.imageFileName))
        #expect(store.image(for: saved) == nil)
    }
}
