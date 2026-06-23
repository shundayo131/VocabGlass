//
//  VocabGlassApp.swift
//  VocabGlass
//
//  Created by Shun Ito on 6/23/26.
//

import SwiftUI
import MWDATCore 

@main
struct VocabGlassApp: App {
    init() {
        do {
            try Wearables.configure()
            print("Wearables configured")
        } catch {
            print("Failed to configure Wearables: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
