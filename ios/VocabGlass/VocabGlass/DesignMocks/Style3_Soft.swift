//
//  Style3_Soft.swift
//  VocabGlass DesignMocks
//
//  Style 3: "Soft". Structure is direction B; this file explores the
//  visual style only. Grouped background canvas, white cards with a
//  faint shadow, generous 24pt corners, rounded type for Latin text,
//  and indigo as the single accent. Friendlier than Quiet and Ink
//  without tipping into toy territory.
//
//  Covers the three signature screens: Capture, Deck, Flashcard.
//

import SwiftUI

private let softRadius: CGFloat = 24
private let softAccent = Color.indigo

// White card with a faint shadow, the signature surface of this style.
private struct SoftCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: softRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - Root

struct SoftRootView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        TabView {
            Tab("Capture", systemImage: "camera.viewfinder") {
                SoftCaptureView(phase: phase)
            }
            Tab("Deck", systemImage: "square.grid.2x2") {
                SoftDeckView(cards: MockData.cards)
            }
        }
        .tint(softAccent)
    }
}

// MARK: - Capture

struct SoftCaptureView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 16) {
                statusCard
                    .padding(.top, 8)

                if phase == .idle {
                    guidanceCard
                }

                Spacer()

                if phase == .active {
                    SoftToast(card: MockData.cards[0])
                }

                captureButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
        .fontDesign(.rounded)
    }

    private var statusCard: some View {
        VStack(spacing: 8) {
            Image(systemName: phase == .active ? "waveform" : "eyeglasses")
                .font(.largeTitle)
                .foregroundStyle(phase == .error ? Color.red : softAccent)
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if phase == .active {
                Text("09:12").font(.title3.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .modifier(SoftCard())
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            row("camera.fill", "Say \u{201C}Capture this\u{201D} to save what you\u{2019}re looking at")
            row("stop.circle", "Say \u{201C}End session\u{201D} when you\u{2019}re done")
            row("timer", "Sessions end on their own after 10 minutes")
            row("lock.iphone", "You can lock your phone. The session keeps running.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SoftCard())
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(softAccent)
                .frame(width: 24)
        }
    }

    private var captureButton: some View {
        VStack(spacing: 12) {
            Button {
            } label: {
                ZStack {
                    Circle()
                        .fill(phase == .active ? Color.red : softAccent)
                        .frame(width: 92, height: 92)
                        .shadow(color: (phase == .active ? Color.red : softAccent).opacity(0.35),
                                radius: 14, y: 6)
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

struct SoftToast: View {
    let card: MockData.Card

    var body: some View {
        HStack(spacing: 12) {
            MockPhoto()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved").font(.caption).foregroundStyle(softAccent)
                Text("\(card.word)  \(card.pronunciation)").font(.headline)
                Text(card.meaning).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .modifier(SoftCard())
    }
}

// MARK: - Deck

struct SoftDeckView: View {
    let cards: [MockData.Card]

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(cards) { card in
                        SoftTile(card: card)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                } label: {
                    Label("Review \(cards.count) cards", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .clipShape(Capsule())
                .tint(softAccent)
                .shadow(color: softAccent.opacity(0.3), radius: 10, y: 4)
                .padding(.bottom, 8)
            }
            .navigationTitle("Deck")
        }
        .fontDesign(.rounded)
        .tint(softAccent)
    }
}

// Photo on top, words below, all inside one soft white card.
struct SoftTile: View {
    let card: MockData.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MockPhoto()
                .frame(minHeight: 130)
                .aspectRatio(1.2, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: softRadius - 8, style: .continuous))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(card.word).font(.headline)
                Text(card.pronunciation).font(.caption).foregroundStyle(.secondary)
            }
            Text(card.meaning).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: softRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

// MARK: - Flashcard

struct SoftFlashcardView: View {
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
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView(value: Double(min(index, cards.count)),
                                 total: Double(cards.count))
                        .tint(softAccent)

                    let card = cards[min(index, cards.count - 1)]

                    Text("\(min(index + 1, cards.count)) of \(cards.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 12) {
                        MockPhoto()
                            .frame(maxWidth: .infinity)
                            .frame(height: 250)
                            .clipShape(RoundedRectangle(cornerRadius: softRadius - 8,
                                                        style: .continuous))
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
                        }
                    }
                    .modifier(SoftCard())

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
                    .tint(softAccent)
                }
                .padding()
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {}
                        .tint(softAccent)
                }
            }
        }
        .fontDesign(.rounded)
    }
}

// MARK: - Previews

#Preview("S3 Soft · Capture · idle") {
    SoftRootView(phase: .idle)
}

#Preview("S3 Soft · Capture · active") {
    SoftRootView(phase: .active)
}

#Preview("S3 Soft · Deck") {
    SoftDeckView(cards: MockData.cards)
}

#Preview("S3 Soft · Flashcard · front") {
    SoftFlashcardView(cards: MockData.cards)
}

#Preview("S3 Soft · Flashcard · revealed") {
    SoftFlashcardView(cards: MockData.cards, revealed: true)
}
