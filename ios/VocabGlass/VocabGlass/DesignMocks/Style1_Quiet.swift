//
//  Style1_Quiet.swift
//  VocabGlass DesignMocks
//
//  Style 1: "Quiet". Structure is direction B; this file explores the
//  visual style only. Stock iOS materials done carefully: glass cards,
//  the system accent as the single color, continuous 18pt corners,
//  unmodified SF type. The style disappears behind the content.
//
//  Covers the three signature screens: Capture, Deck, Flashcard.
//

import SwiftUI

private let quietRadius: CGFloat = 18

// MARK: - Root

struct QuietRootView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        TabView {
            Tab("Capture", systemImage: "camera.viewfinder") {
                QuietCaptureView(phase: phase)
            }
            Tab("Deck", systemImage: "square.grid.2x2") {
                QuietDeckView(cards: MockData.cards)
            }
        }
    }
}

// MARK: - Capture

struct QuietCaptureView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                statusCard
                    .padding(.top, 8)

                if phase == .idle {
                    guidanceCard
                }

                Spacer()

                if phase == .active {
                    QuietToast(card: MockData.cards[0])
                }

                captureButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            Image(systemName: phase == .active ? "waveform" : "eyeglasses")
                .font(.largeTitle)
                .foregroundStyle(phase == .error ? Color.red : Color.accentColor)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if phase == .active {
                Text("09:12").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: quietRadius, style: .continuous))
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("camera.fill", "Say \u{201C}Capture this\u{201D} to save what you\u{2019}re looking at")
            row("stop.circle", "Say \u{201C}End session\u{201D} when you\u{2019}re done")
            row("timer", "Sessions end on their own after 10 minutes")
            row("lock.iphone", "You can lock your phone. The session keeps running.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: quietRadius, style: .continuous))
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
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
                    Image(systemName: phase == .active ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }
            Text(phase == .active ? "Tap to end the session" : "Start a session")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        switch phase {
        case .idle: "Ready"
        case .starting: "Connecting…"
        case .active: "Listening"
        case .error: "Session ended"
        }
    }

    private var detail: String {
        switch phase {
        case .idle: "Glasses connected."
        case .starting: "Camera and audio are warming up."
        case .active: "Say \u{201C}Capture this\u{201D} to save what you see."
        case .error: "The glasses closed the connection. Check they are worn, then retry."
        }
    }
}

struct QuietToast: View {
    let card: MockData.Card

    var body: some View {
        HStack(spacing: 12) {
            MockPhoto()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved").font(.caption).foregroundStyle(.secondary)
                Text("\(card.word)  \(card.pronunciation)").font(.headline)
                Text(card.meaning).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: quietRadius, style: .continuous))
    }
}

// MARK: - Deck

struct QuietDeckView: View {
    let cards: [MockData.Card]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(cards) { card in
                        QuietTile(card: card)
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
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
            .navigationTitle("Deck")
        }
    }
}

// Photo tile with a glass caption bar instead of a dark scrim.
struct QuietTile: View {
    let card: MockData.Card

    var body: some View {
        MockPhoto()
            .frame(minHeight: 150)
            .aspectRatio(1, contentMode: .fill)
            .overlay(alignment: .bottom) {
                HStack(spacing: 6) {
                    Text(card.word).font(.subheadline.weight(.semibold))
                    Text(card.pronunciation).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
            }
            .clipShape(RoundedRectangle(cornerRadius: quietRadius, style: .continuous))
    }
}

// MARK: - Flashcard

struct QuietFlashcardView: View {
    let cards: [MockData.Card]
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

                let card = cards[min(index, cards.count - 1)]

                Text("\(min(index + 1, cards.count)) of \(cards.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                MockPhoto()
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: quietRadius, style: .continuous))

                if revealed {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(card.word).font(.largeTitle.bold())
                            Text(card.pronunciation).font(.title3).foregroundStyle(.secondary)
                        }
                        Text(card.meaning).font(.headline)
                        Text(card.example).font(.body).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.regularMaterial,
                                in: RoundedRectangle(cornerRadius: quietRadius, style: .continuous))
                }

                Spacer(minLength: 0)

                Button {
                    if revealed { index += 1; revealed = false } else { revealed = true }
                } label: {
                    Label(revealed ? "Next" : "Show answer",
                          systemImage: revealed ? "arrow.right" : "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {}
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("S1 Quiet · Capture · idle") {
    QuietRootView(phase: .idle)
}

#Preview("S1 Quiet · Capture · active") {
    QuietRootView(phase: .active)
}

#Preview("S1 Quiet · Deck") {
    QuietDeckView(cards: MockData.cards)
}

#Preview("S1 Quiet · Flashcard · front") {
    QuietFlashcardView(cards: MockData.cards)
}

#Preview("S1 Quiet · Flashcard · revealed") {
    QuietFlashcardView(cards: MockData.cards, revealed: true)
}
