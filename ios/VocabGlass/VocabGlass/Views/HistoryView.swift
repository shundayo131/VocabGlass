//
//  HistoryView.swift
//  VocabGlass
//
//  Lists the saved deck with thumbnails.
//

import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: CardStore

    var body: some View {
        Group {
            if store.cards.isEmpty {
                Text("No saved cards yet")
                    .foregroundStyle(.secondary)
            } else {
                List(store.cards) { card in
                    HStack(spacing: 12) {
                        thumbnail(for: card)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(card.word).font(.headline)
                                Text(card.pinyin).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(card.translation).font(.subheadline)
                        }
                    }
                }
            }
        }
        .navigationTitle("Deck")
    }

    @ViewBuilder
    private func thumbnail(for card: SavedCard) -> some View {
        if let image = store.image(for: card) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
                .frame(width: 56, height: 56)
        }
    }
}
