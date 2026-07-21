//
//  CardStore.swift
//  VocabGlass
//
//  Holds the saved deck and persists it locally: card metadata as one JSON
//  file, each image as a JPEG, both in the app's Documents directory.
//

import Foundation
import Combine
import UIKit

@MainActor
final class CardStore: ObservableObject {
    @Published private(set) var cards: [SavedCard] = []

    // Where the index and images live. Documents in the app; tests
    // inject a temp directory so they never touch real data.
    private let directory: URL
    private let indexURL: URL

    init(directory: URL = CardStore.documents) {
        self.directory = directory
        indexURL = directory.appendingPathComponent("cards.json")
        load()
    }

    // Save a freshly generated card plus its photo into the deck.
    func save(_ card: LearningCard, image: UIImage) {
        let fileName = "\(card.id).jpg"
        if let jpeg = image.jpegData(compressionQuality: 0.8) {
            try? jpeg.write(to: directory.appendingPathComponent(fileName))
        }
        let saved = SavedCard(
            id: card.id,
            word: card.word,
            pinyin: card.pinyin,
            translation: card.translation,
            example: card.example,
            imageFileName: fileName,
            createdAt: Date()
        )
        cards.insert(saved, at: 0)   // newest first
        persist()
    }

    // Replace the text of an existing card. Unknown ids are ignored.
    // Identity, image, and creation date are left alone.
    func update(_ card: SavedCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards[index] = card
        persist()
    }

    // Remove a card and its photo. Unknown ids are ignored.
    func delete(_ card: SavedCard) {
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return }
        cards.remove(at: index)
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(card.imageFileName)
        )
        persist()
    }

    // Convenience for List.onDelete, which hands back row offsets.
    func delete(at offsets: IndexSet) {
        for card in offsets.map({ cards[$0] }) {
            delete(card)
        }
    }

    // Load the image for a saved card from disk.
    func image(for card: SavedCard) -> UIImage? {
        let url = directory.appendingPathComponent(card.imageFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        cards = (try? JSONDecoder().decode([SavedCard].self, from: data)) ?? []
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cards) else { return }
        try? data.write(to: indexURL)
    }

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
