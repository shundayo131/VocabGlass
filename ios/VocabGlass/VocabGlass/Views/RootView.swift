//
//  RootView.swift
//  VocabGlass
//
//  Root of the app: Capture and Deck tabs. Carries the app-level wiring
//  that used to live on ContentView: starting the glasses client and
//  handling the registration return URL from Meta AI. The old manual
//  capture screen survives as a debug-only Dev tab.
//

import SwiftUI

struct RootView: View {
    @ObservedObject var client: GlassesClient
    @ObservedObject var store: CardStore
    let session: SessionController

    enum TabID: Hashable {
        case capture, deck, dev
    }

    @State private var selection: TabID = .capture

    var body: some View {
        TabView(selection: $selection) {
            Tab("Capture", systemImage: "camera.viewfinder", value: TabID.capture) {
                captureTab
            }
            Tab("Deck", systemImage: "square.grid.2x2", value: TabID.deck) {
                deckTab
            }
            #if DEBUG
            Tab("Dev", systemImage: "wrench.and.screwdriver", value: TabID.dev) {
                ContentView(client: client, store: store, session: session)
            }
            #endif
        }
        .onAppear {
            client.start()
            #if DEBUG
            if let tab = UITestSupport.initialTab { selection = tab }
            #endif
        }
        .onOpenURL { url in client.handleUrl(url) }
    }

    private var captureTab: some View {
        #if DEBUG
        CaptureView(controller: session, client: client, store: store,
                    demoActive: UITestSupport.demoActiveCapture)
        #else
        CaptureView(controller: session, client: client, store: store)
        #endif
    }

    private var deckTab: some View {
        #if DEBUG
        DeckView(store: store, forcedState: UITestSupport.forcedDeckState)
        #else
        DeckView(store: store)
        #endif
    }
}
