//
//  CardDetailView.swift
//  VocabGlass
//
//  A saved card in full, shown as a sheet from the deck. Edit opens a
//  form; delete asks for confirmation first. Both go straight through
//  CardStore's update and delete.
//

import SwiftUI

struct CardDetailView: View {
    @ObservedObject var store: CardStore
    let card: SavedCard

    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var isConfirmingDelete = false

    // The live version of the card, so an edit shows up immediately.
    private var current: SavedCard {
        store.cards.first(where: { $0.id == card.id }) ?? card
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photo

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(current.word).font(.largeTitle.bold())
                        Text(current.pinyin).font(.title3).foregroundStyle(.secondary)
                    }
                    Text(current.translation).font(.headline)
                    Text(current.example).font(.body).foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete card", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("detail.deleteButton")
                }
                .padding()
            }
            .navigationTitle(current.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("detail.doneButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { isEditing = true }
                        .accessibilityIdentifier("detail.editButton")
                }
            }
            .sheet(isPresented: $isEditing) {
                EditCardSheet(store: store, card: current)
            }
            .confirmationDialog(
                "Delete \u{201C}\(current.word)\u{201D}?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    store.delete(current)
                    dismiss()
                }
                .accessibilityIdentifier("detail.confirmDeleteButton")
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The card and its photo will be removed.")
            }
        }
        .accessibilityIdentifier("detail.view")
        .presentationDetents([.medium, .large])
    }

    private var photo: some View {
        Group {
            if let image = store.image(for: current) {
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
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// The four text fields, editable. Save goes through CardStore.update.
struct EditCardSheet: View {
    @ObservedObject var store: CardStore
    let card: SavedCard

    @Environment(\.dismiss) private var dismiss
    @State private var word: String
    @State private var pinyin: String
    @State private var translation: String
    @State private var example: String

    init(store: CardStore, card: SavedCard) {
        self.store = store
        self.card = card
        _word = State(initialValue: card.word)
        _pinyin = State(initialValue: card.pinyin)
        _translation = State(initialValue: card.translation)
        _example = State(initialValue: card.example)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Word", text: $word)
                        .accessibilityIdentifier("edit.wordField")
                    TextField("Pronunciation", text: $pinyin)
                        .accessibilityIdentifier("edit.pinyinField")
                }
                Section("Meaning") {
                    TextField("Meaning", text: $translation)
                        .accessibilityIdentifier("edit.translationField")
                }
                Section("Example") {
                    TextField("Example", text: $example, axis: .vertical)
                        .accessibilityIdentifier("edit.exampleField")
                }
            }
            .navigationTitle("Edit card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("edit.cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = card
                        updated.word = word
                        updated.pinyin = pinyin
                        updated.translation = translation
                        updated.example = example
                        store.update(updated)
                        dismiss()
                    }
                    .accessibilityIdentifier("edit.saveButton")
                }
            }
        }
    }
}
