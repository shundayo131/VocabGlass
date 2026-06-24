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
    let word: String
    let pinyin: String
    let translation: String
    let example: String
    let imageFileName: String
    let createdAt: Date
}
