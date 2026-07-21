//
//  SavedCard.swift
//  VocabGlass
//
//  A card saved to the local deck. Unlike LearningCard (the network shape),
//  this carries an id, the local image file name, and a created date.
//

import Foundation

struct SavedCard: Codable, Identifiable {
    let id: UUID
    // The four text fields are editable. Identity, image, and creation date
    // are not: editing a card must not change which photo it points at.
    var word: String
    var pinyin: String
    var translation: String
    var example: String
    let imageFileName: String
    let createdAt: Date
}
