//
//  VocabGlassApp.swift
//  VocabGlass
//
//  App entry point. Builds the long-lived objects (glasses client, card
//  store, session controller) and hands them to the root view.
//

import SwiftUI
import MWDATCore

@main
struct VocabGlassApp: App {
    // Declared without initial values: they are built in init so the
    // session controller can receive the same instances the screens use.
    @StateObject private var client: GlassesClient
    @StateObject private var store: CardStore
    @StateObject private var session: SessionController

    init() {
        // Configure the DAT SDK first: GlassesClient touches
        // Wearables.shared in its init, and the SDK traps if that happens
        // before configure().
        do {
            try Wearables.configure()
            print("Wearables configured")
        } catch {
            print("Failed to configure Wearables: \(error)")
        }

        // Build the dependencies as plain locals, then wrap them.
        // @StateObject properties cannot reference each other directly
        // during init, so this is the standard dependency-injection dance.
        let client = GlassesClient()
        let store = CardStore()
        #if DEBUG
        // UI tests and screenshot runs put the deck into a known state
        // via launch arguments. No-op without them.
        UITestSupport.prepare(store: store)
        #endif
        _client = StateObject(wrappedValue: client)
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: SessionController(glasses: client, store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client, store: store, session: session)
        }
    }
}
