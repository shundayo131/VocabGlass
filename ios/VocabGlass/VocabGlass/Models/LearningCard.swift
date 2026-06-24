//
//  LearningCard.swift
//  VocabGlass
//
//  One vocabulary card. Decoded from the worker's /generate response.
//

import Foundation

struct LearningCard: Codable, Identifiable {
    var id = UUID()
    let word: String         // hanzi
    let pinyin: String
    let translation: String  // English
    let example: String      // example sentence in Chinese

    // The worker returns only these four fields; id is generated locally.
    enum CodingKeys: String, CodingKey {
        case word, pinyin, translation, example
    }
}
