//
//  Diagnostics.swift
//  VocabGlass
//
//  Two-tier logging facade. Call sites pick the tier; nothing else in
//  the app talks to a logger directly.
//
//  - event(): production observability. Lifecycle, state transitions,
//    tool timings, errors. Goes to os.Logger (visible in Console.app,
//    kept in release builds). Never contains user content.
//  - debug(): debug-only instrumentation, such as speech transcripts and
//    mic levels. Compiled out of release builds.
//
//  In debug builds both tiers also feed the on-screen SessionLog viewer.
//

import Foundation
import os

enum Diag {

    private static let logger = Logger(subsystem: "com.shunito.VocabGlass",
                                       category: "voice-session")

    // Production-grade event. No user content allowed here.
    static func event(_ tag: String, _ message: String) {
        logger.info("[\(tag, privacy: .public)] \(message, privacy: .public)")
        #if DEBUG
        SessionLog.shared.addAsync(tag, message)
        #endif
    }

    // Debug-only detail: transcripts, signal levels. Nothing in release.
    static func debug(_ tag: String, _ message: String) {
        #if DEBUG
        SessionLog.shared.addAsync(tag, message)
        #endif
    }

    // Clear the on-screen viewer at session start (debug builds only).
    static func resetDebugLog() {
        #if DEBUG
        Task { @MainActor in SessionLog.shared.reset() }
        #endif
    }
}
