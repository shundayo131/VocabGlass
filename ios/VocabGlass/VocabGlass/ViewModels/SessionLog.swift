//
//  SessionLog.swift
//  VocabGlass
//
//  Timestamped event log for voice session debugging: what the mic heard,
//  what Gemini transcribed and said, when tools fired, how deep the
//  playback queue is. Shown on the session screen and copyable for
//  analysis. Debug tooling, removed in M13.
//

import Foundation
import Combine

@MainActor
final class SessionLog: ObservableObject {

    static let shared = SessionLog()

    @Published private(set) var lines: [String] = []

    private var t0 = Date()

    // Called at session start so times read as seconds into the session.
    func reset() {
        t0 = Date()
        lines.removeAll()
        add("log", "reset")
    }

    // tag is a short source label: sess, mic, you, gem, tool, play.
    func add(_ tag: String, _ message: String) {
        let t = Date().timeIntervalSince(t0)
        let line = String(format: "%7.2f [%@] %@", t, tag, message)
        lines.append(line)
        print("SESSIONLOG \(line)")
    }

    // Entry point for callers off the main actor (the audio thread).
    nonisolated func addAsync(_ tag: String, _ message: String) {
        Task { @MainActor in self.add(tag, message) }
    }

    var text: String { lines.joined(separator: "\n") }
}
