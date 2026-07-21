//
//  Style2_Ink.swift
//  VocabGlass DesignMocks
//
//  Style 2: "Ink". Structure is direction B; this file explores the
//  visual style only. Monochrome: black, white, and grays. The photos
//  are the only color on screen. Hairline borders instead of fills,
//  sharp 10pt corners, tracked uppercase labels, monospaced pinyin.
//  Reads like a gallery catalog. Adapts to dark mode for free because
//  everything is Color.primary against the system background.
//
//  Covers the three signature screens: Capture, Deck, Flashcard.
//

import SwiftUI

private let inkRadius: CGFloat = 10

// A tracked uppercase caption, the signature label of this style.
private struct InkLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.medium))
            .kerning(1.4)
            .foregroundStyle(.secondary)
    }
}

// Hairline-bordered box, the signature surface of this style.
private struct InkBox: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .overlay(
                RoundedRectangle(cornerRadius: inkRadius)
                    .strokeBorder(.separator, lineWidth: 1)
            )
    }
}

// MARK: - Root

struct InkRootView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        TabView {
            Tab("Capture", systemImage: "camera.viewfinder") {
                InkCaptureView(phase: phase)
            }
            Tab("Deck", systemImage: "square.grid.2x2") {
                InkDeckView(cards: MockData.cards)
            }
        }
        .tint(.primary)
    }
}

// MARK: - Capture

struct InkCaptureView: View {
    let phase: MockData.SessionPhase

    var body: some View {
        VStack(spacing: 20) {
            statusBlock
                .padding(.top, 8)

            if phase == .idle {
                guidanceBlock
            }

            Spacer()

            if phase == .active {
                InkToast(card: MockData.cards[0])
            }

            captureButton
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 20)
        .background(Color(.systemBackground))
    }

    private var statusBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: phase == .active ? "waveform" : "eyeglasses")
                .font(.largeTitle)
                .foregroundStyle(phase == .error ? Color.red : Color.primary)
            InkLabel(text: label)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if phase == .active {
                Text("09:12")
                    .font(.title3.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity)
        .modifier(InkBox())
    }

    private var guidanceBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkLabel(text: "Voice commands")
            row("\u{201C}Capture this\u{201D} saves what you\u{2019}re looking at")
            row("\u{201C}End session\u{201D} finishes")
            Divider()
            row("Sessions end on their own after 10 minutes")
            row("You can lock your phone. The session keeps running.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(InkBox())
    }

    private func row(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var captureButton: some View {
        VStack(spacing: 10) {
            Button {
            } label: {
                ZStack {
                    Circle()
                        .fill(phase == .error ? Color.red : Color.primary)
                        .frame(width: 84, height: 84)
                    Image(systemName: phase == .active ? "stop.fill" : "mic.fill")
                        .font(.title)
                        .foregroundStyle(Color(.systemBackground))
                }
            }
            InkLabel(text: phase == .active ? "End session" : "Start session")
        }
    }

    private var label: String {
        switch phase {
        case .idle: "Ready"
        case .starting: "Connecting"
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

struct InkToast: View {
    let card: MockData.Card

    var body: some View {
        HStack(spacing: 12) {
            MockPhoto()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: inkRadius - 4))
            VStack(alignment: .leading, spacing: 3) {
                InkLabel(text: "Saved")
                HStack(spacing: 8) {
                    Text(card.word).font(.headline)
                    Text(card.pronunciation)
                        .font(.subheadline)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                Text(card.meaning).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .overlay(RoundedRectangle(cornerRadius: inkRadius).strokeBorder(.separator, lineWidth: 1))
    }
}

// MARK: - Deck

struct InkDeckView: View {
    let cards: [MockData.Card]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(cards) { card in
                        InkTile(card: card)
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .safeAreaInset(edge: .bottom) {
                Button {
                } label: {
                    Text("Review \(cards.count) cards".uppercased())
                        .font(.footnote.weight(.semibold))
                        .kerning(1.2)
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.primary, in: Capsule())
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("Deck")
        }
    }
}

// Gallery caption: the photo stands alone, the words sit under it.
struct InkTile: View {
    let card: MockData.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MockPhoto()
                .frame(minHeight: 150)
                .aspectRatio(1, contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: inkRadius))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.word).font(.headline)
                Text(card.pronunciation)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
            }
            Text(card.meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Flashcard

struct InkFlashcardView: View {
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
            VStack(spacing: 20) {
                let card = cards[min(index, cards.count - 1)]

                HStack {
                    InkLabel(text: "Card \(min(index + 1, cards.count)) of \(cards.count)")
                    Spacer()
                }

                MockPhoto()
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: inkRadius))

                if revealed {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(card.word).font(.largeTitle.bold())
                            Text(card.pronunciation)
                                .font(.title3)
                                .fontDesign(.monospaced)
                                .foregroundStyle(.secondary)
                        }
                        Text(card.meaning).font(.headline)
                        Text(card.example).font(.body).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)

                Button {
                    if revealed { index += 1; revealed = false } else { revealed = true }
                } label: {
                    Text((revealed ? "Next" : "Show answer").uppercased())
                        .font(.footnote.weight(.semibold))
                        .kerning(1.2)
                        .foregroundStyle(Color(.systemBackground))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.primary, in: Capsule())
                }
            }
            .padding(20)
            .background(Color(.systemBackground))
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {}
                        .tint(.primary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("S2 Ink · Capture · idle") {
    InkRootView(phase: .idle)
}

#Preview("S2 Ink · Capture · active") {
    InkRootView(phase: .active)
}

#Preview("S2 Ink · Deck") {
    InkDeckView(cards: MockData.cards)
}

#Preview("S2 Ink · Flashcard · front") {
    InkFlashcardView(cards: MockData.cards)
}

#Preview("S2 Ink · Flashcard · revealed") {
    InkFlashcardView(cards: MockData.cards, revealed: true)
}
