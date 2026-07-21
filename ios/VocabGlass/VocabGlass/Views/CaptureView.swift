//
//  CaptureView.swift
//  VocabGlass
//
//  The voice session screen, home of the Capture tab. Reads
//  SessionController and GlassesClient and renders them in the Quiet
//  style: one status card, voice guidance while idle, the newest card as
//  a toast while active, and a single round session button. Replaces
//  SessionView.
//

import SwiftUI
import MWDATCore

struct CaptureView: View {
    @ObservedObject var controller: SessionController
    @ObservedObject var client: GlassesClient
    @ObservedObject var store: CardStore

    // Debug-only: render the active-session look without a live session,
    // for screenshots. Never set in release builds.
    var demoActive = false

    private static let cornerRadius: CGFloat = 18

    // The one state the screen renders. Derived, never stored.
    private enum Phase {
        case disconnected, idle, starting, active, ending, error
    }

    private var phase: Phase {
        if demoActive { return .active }
        if client.registrationState != .registered { return .disconnected }
        switch controller.state {
        case .idle: return controller.lastError == nil ? .idle : .error
        case .starting: return .starting
        case .active: return .active
        case .ending: return .ending
        }
    }

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

                if phase == .active, let card = store.cards.first {
                    latestCardToast(card)
                }

                primaryButton
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Status

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
                Text(timeLeft)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture.statusCard")
    }

    private var statusSymbol: String {
        switch phase {
        case .disconnected: "eyeglasses.slash"
        case .idle: "eyeglasses"
        case .starting: "wave.3.right"
        case .active: "waveform"
        case .ending: "stop.circle"
        case .error: "exclamationmark.triangle"
        }
    }

    private var statusTitle: String {
        switch phase {
        case .disconnected: "Glasses not connected"
        case .idle: "Ready"
        case .starting: "Connecting…"
        case .active: "Listening"
        case .ending: "Ending…"
        case .error: "Session ended"
        }
    }

    private var statusDetail: String {
        switch phase {
        case .disconnected:
            "Connect your Meta glasses to get started."
        case .idle:
            "Glasses connected."
        case .starting, .active, .ending:
            // The controller's live progress: "starting camera",
            // "capturing photo", "saved: ...". Real feedback, keep it.
            demoActive ? "listening (glasses)" : controller.statusLine
        case .error:
            controller.lastError ?? "The last session did not finish."
        }
    }

    private var timeLeft: String {
        if demoActive { return "08:42" }
        return String(format: "%02d:%02d",
                      controller.remainingSeconds / 60,
                      controller.remainingSeconds % 60)
    }

    // MARK: - Guidance

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            guidanceRow("camera.fill", "Say \u{201C}Capture this\u{201D} to save what you\u{2019}re looking at")
            guidanceRow("stop.circle", "Say \u{201C}End session\u{201D} when you\u{2019}re done")
            guidanceRow("timer", "Sessions end on their own after 10 minutes")
            guidanceRow("lock.iphone", "You can lock your phone. The session keeps running.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityIdentifier("capture.guidance")
    }

    private func guidanceRow(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)   // fixed width so the text column lines up
        }
    }

    // MARK: - Latest card

    private func latestCardToast(_ card: SavedCard) -> some View {
        HStack(spacing: 12) {
            Group {
                if let image = store.image(for: card) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Saved")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(card.word)  \(card.pinyin)")
                    .font(.headline)
                Text(card.translation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityIdentifier("capture.latestCard")
    }

    // MARK: - Session button

    @ViewBuilder
    private var primaryButton: some View {
        switch phase {
        case .disconnected:
            Button {
                client.connectGlasses()
            } label: {
                Label("Connect glasses", systemImage: "link")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("capture.connectButton")

        default:
            VStack(spacing: 10) {
                Button {
                    if phase == .active {
                        controller.endSession()
                    } else if phase == .idle || phase == .error {
                        controller.startSession()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(phase == .active ? Color.red : Color.accentColor)
                            .frame(width: 84, height: 84)
                        if phase == .starting || phase == .ending {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: phase == .active ? "stop.fill" : "mic.fill")
                                .font(.title)
                                .foregroundStyle(.white)
                        }
                    }
                }
                .disabled(phase == .starting || phase == .ending)
                .accessibilityIdentifier("capture.sessionButton")
                .accessibilityLabel(phase == .active ? "End session" : "Start session")

                Text(buttonCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var buttonCaption: String {
        switch phase {
        case .disconnected: ""
        case .idle: "Start a session"
        case .starting: "Warming up camera and audio"
        case .active: "Tap to end the session"
        case .ending: "Ending the session"
        case .error: "Tap to try again"
        }
    }
}
