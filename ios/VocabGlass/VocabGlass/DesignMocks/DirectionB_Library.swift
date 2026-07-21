//
//  DirectionB_Library.swift
//  VocabGlass DesignMocks
//
//  Direction B: "Visual Library". Two tabs split the two postures:
//  Capture (out, glasses on) and Deck (home, phone only). Photos carry
//  the interface. Bets on the image being the memory hook.
//
//  Chosen direction, with two pieces merged in from direction A:
//  the status card (icon + Ready + one-line detail) on the Capture tab,
//  and the vertical flashcard layout (framed photo, Show answer button).
//
//  Fixed mock data. Not reachable from the production UI.
//

import SwiftUI

// MARK: - Root

struct LibraryRootView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        TabView {
            Tab("Capture", systemImage: "camera.viewfinder") {
                LibraryCaptureView(phase: phase)
            }
            Tab("Deck", systemImage: "square.grid.2x2") {
                LibraryDeckView(cards: MockData.cards)
            }
        }
    }
}

// MARK: - Capture tab

struct LibraryCaptureView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        ZStack {
            background

            VStack(spacing: 16) {
                statusCard
                    .padding(.top, 8)

                // Voice guidance shows only before the session starts:
                // once it runs, the phone is pocketed or locked, so idle
                // is the one moment the user is actually reading.
                if phase == .idle {
                    guidanceCard
                }

                Spacer()

                if phase == .active {
                    LibraryCapturedToast(card: MockData.cards[0])
                }

                captureButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
    }

    // Quiet gradient in every phase. The captured photo appears only in
    // the saved toast: a full-screen photo backdrop would be the *last*
    // capture, not the live view, and reads as a frozen screen.
    private var background: some View {
        LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    // Merged in from direction A: one card that says where the glasses
    // are at, with a symbol, a title, and one line of detail. Material
    // background so it stays readable over the active photo backdrop.
    private var statusCard: some View {
        VStack(spacing: 8) {
            Image(systemName: statusSymbol)
                .font(.largeTitle)
                .foregroundStyle(phase == .error ? Color.red : Color.accentColor)
                .symbolEffect(.pulse, isActive: phase == .starting)
            Text(statusTitle)
                .font(.headline)
            Text(statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if phase == .active {
                Text("09:12")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusSymbol: String {
        switch phase {
        case .idle: "eyeglasses"
        case .starting: "wave.3.right"
        case .active: "waveform"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusTitle: String {
        switch phase {
        case .idle: "Ready"
        case .starting: "Connecting…"
        case .active: "Listening"
        case .error: "Session ended"
        }
    }

    private var statusDetail: String {
        switch phase {
        case .idle: "Glasses connected."
        case .starting: "Camera and audio are warming up."
        case .active: "Say \u{201C}Capture this\u{201D} to save what you see."
        case .error: "The glasses closed the connection. Check they are worn, then retry."
        }
    }

    // What you can do by voice, and what to expect from a session.
    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            guidanceRow(symbol: "camera.fill",
                        text: "Say \u{201C}Capture this\u{201D} to save what you\u{2019}re looking at")
            guidanceRow(symbol: "stop.circle",
                        text: "Say \u{201C}End session\u{201D} when you\u{2019}re done")
            guidanceRow(symbol: "timer",
                        text: "Sessions end on their own after 10 minutes")
            guidanceRow(symbol: "lock.iphone",
                        text: "You can lock your phone or leave the app. The session keeps running.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func guidanceRow(symbol: String, text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
        }
    }

    private var captureButton: some View {
        VStack(spacing: 10) {
            Button {
            } label: {
                ZStack {
                    Circle()
                        .fill(phase == .active ? Color.red : Color.accentColor)
                        .frame(width: 84, height: 84)
                    if phase == .starting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: phase == .active ? "stop.fill" : "mic.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                }
            }
            .disabled(phase == .starting)

            Text(buttonCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonCaption: String {
        switch phase {
        case .idle: "Start a session, then say \u{201C}capture this\u{201D}"
        case .starting: "Warming up camera and audio"
        case .active: "Tap to end the session"
        case .error: "Tap to try again"
        }
    }
}

// A capture landing during the session: photo plus the new word.
struct LibraryCapturedToast: View {
    let card: MockData.Card

    var body: some View {
        HStack(spacing: 12) {
            MockPhoto()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(card.word)  \(card.pronunciation)")
                    .font(.headline)
                Text(card.meaning)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Deck tab

struct LibraryDeckView: View {
    let cards: [MockData.Card]
    @State private var selected: MockData.Card?
    @State private var isReviewing = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Captures from your sessions appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(cards) { card in
                                Button {
                                    selected = card
                                } label: {
                                    LibraryPhotoCard(card: card)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                    .safeAreaInset(edge: .bottom) {
                        Button {
                            isReviewing = true
                        } label: {
                            Label("Review \(cards.count) cards", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                    }
                }
            }
            .navigationTitle("Deck")
            .sheet(item: $selected) { card in
                LibraryCardSheet(card: card)
            }
            .fullScreenCover(isPresented: $isReviewing) {
                LibraryFlashcardView(cards: cards)
            }
        }
    }
}

// A photo tile: image first, word on a scrim.
struct LibraryPhotoCard: View {
    let card: MockData.Card

    var body: some View {
        MockPhoto()
            .frame(minHeight: 150)
            .aspectRatio(1, contentMode: .fill)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.word)
                        .font(.headline)
                    Text(card.pronunciation)
                        .font(.caption)
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.65)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// Detail as a sheet: photo on top, fields below, actions at the bottom.
struct LibraryCardSheet: View {
    let card: MockData.Card
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MockPhoto()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(card.word).font(.largeTitle.bold())
                        Text(card.pronunciation).font(.title3).foregroundStyle(.secondary)
                    }
                    Text(card.meaning).font(.headline)
                    Text(card.example).font(.body).foregroundStyle(.secondary)

                    HStack {
                        Button {
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button(role: .destructive) {
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle(card.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Flashcards
// Merged in from direction A: vertical layout with a framed photo and an
// explicit Show answer button, instead of full-bleed tap-to-reveal.
// Still presented as a fullScreenCover, so it keeps a Close button.

struct LibraryFlashcardView: View {
    let cards: [MockData.Card]
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int
    @State private var revealed: Bool

    init(cards: [MockData.Card], index: Int = 0, revealed: Bool = false) {
        self.cards = cards
        _index = State(initialValue: index)
        _revealed = State(initialValue: revealed)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProgressView(value: Double(min(index, cards.count)),
                             total: Double(cards.count))

                if index < cards.count {
                    let card = cards[index]

                    Text("\(index + 1) of \(cards.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MockPhoto()
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    if revealed {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(card.word).font(.largeTitle.bold())
                                    Text(card.pronunciation).font(.title3).foregroundStyle(.secondary)
                                }
                                Text(card.meaning).font(.headline)
                                Text(card.example).font(.body).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Spacer(minLength: 0)

                    if revealed {
                        Button {
                            index += 1
                            revealed = false
                        } label: {
                            Label("Next", systemImage: "arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        Button {
                            revealed = true
                        } label: {
                            Label("Show answer", systemImage: "eye")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    Spacer()
                    ContentUnavailableView {
                        Label("All done", systemImage: "checkmark.circle")
                    } description: {
                        Text("You reviewed \(cards.count) cards.")
                    } actions: {
                        Button("Start over") {
                            index = 0
                            revealed = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("B · Capture · idle") {
    LibraryRootView(phase: .idle)
}

#Preview("B · Capture · starting") {
    LibraryRootView(phase: .starting)
}

#Preview("B · Capture · active") {
    LibraryRootView(phase: .active)
}

#Preview("B · Capture · error") {
    LibraryRootView(phase: .error)
}

#Preview("B · Capture · XXL type") {
    LibraryRootView(phase: .active)
        .environment(\.dynamicTypeSize, .accessibility2)
}

#Preview("B · Deck") {
    LibraryDeckView(cards: MockData.cards)
}

#Preview("B · Deck · empty") {
    LibraryDeckView(cards: [])
}

#Preview("B · Card sheet") {
    LibraryCardSheet(card: MockData.cards[0])
}

#Preview("B · Flashcard · front") {
    LibraryFlashcardView(cards: MockData.cards)
}

#Preview("B · Flashcard · revealed") {
    LibraryFlashcardView(cards: MockData.cards, revealed: true)
}

#Preview("B · Flashcard · finished") {
    LibraryFlashcardView(cards: MockData.cards, index: MockData.cards.count)
}
