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
        // Build the dependencies as plain locals first, then wrap them.
        // @StateObject properties cannot reference each other directly
        // during init, so this is the standard dependency-injection dance.
        let client = GlassesClient()
        let store = CardStore()
        _client = StateObject(wrappedValue: client)
        _store = StateObject(wrappedValue: store)
        _session = StateObject(wrappedValue: SessionController(glasses: client, store: store))

        do {
            try Wearables.configure()
            print("Wearables configured")
        } catch {
            print("Failed to configure Wearables: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(client: client, store: store, session: session)
        }
    }
}
