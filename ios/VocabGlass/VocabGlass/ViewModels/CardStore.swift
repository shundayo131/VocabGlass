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

    private let indexURL: URL

    init() {
        indexURL = Self.documents.appendingPathComponent("cards.json")
        load()
    }

    // Save a freshly generated card plus its photo into the deck.
    func save(_ card: LearningCard, image: UIImage) {
        let fileName = "\(card.id).jpg"
        if let jpeg = image.jpegData(compressionQuality: 0.8) {
            try? jpeg.write(to: Self.documents.appendingPathComponent(fileName))
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

    // Load the image for a saved card from disk.
    func image(for card: SavedCard) -> UIImage? {
        let url = Self.documents.appendingPathComponent(card.imageFileName)
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

    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}
