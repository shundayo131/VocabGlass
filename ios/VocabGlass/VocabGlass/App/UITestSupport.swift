//
//  UITestSupport.swift
//  VocabGlass
//
//  Debug-only launch-argument hooks so UI tests and screenshot runs can
//  put the app into a known state. Seeding and wiping go through
//  CardStore's public API; nothing here touches storage directly.
//  Compiled out of release builds entirely.
//

#if DEBUG
import UIKit

@MainActor
enum UITestSupport {
    private static var args: [String] { ProcessInfo.processInfo.arguments }

    // Wipe or seed the deck before the UI appears.
    static func prepare(store: CardStore) {
        if args.contains("--uitest-reset") {
            wipe(store)
        }
        if args.contains("--uitest-seed") {
            wipe(store)
            seed(store)
        }
    }

    // Which tab to land on. Screenshots of the deck need to start there.
    static var initialTab: RootView.TabID? {
        args.contains("--uitest-tab-deck") ? .deck : nil
    }

    // Force deck states the live store cannot produce.
    static var forcedDeckState: DeckDisplayState? {
        if args.contains("--uitest-deck-loading") { return .loading }
        if args.contains("--uitest-deck-error") {
            return .error("Something went wrong reading saved cards.")
        }
        return nil
    }

    // Open the flashcard review as soon as the deck appears.
    static var autoOpenReview: Bool { args.contains("--uitest-review") }

    // Start the review with the answer already revealed (screenshots).
    static var autoReveal: Bool { args.contains("--uitest-review-revealed") }

    // Render the Capture tab in its active-session look without a live
    // session (screenshots).
    static var demoActiveCapture: Bool { args.contains("--uitest-capture-active") }

    // MARK: - Data

    private static func wipe(_ store: CardStore) {
        for card in store.cards {
            store.delete(card)
        }
    }

    private static func seed(_ store: CardStore) {
        let samples: [(String, String, String, String)] = [
            ("植物", "zhíwù", "plant", "这个植物很漂亮。"),
            ("杯子", "bēizi", "cup", "杯子里有咖啡。"),
            ("窗户", "chuānghu", "window", "请打开窗户。"),
            ("钥匙", "yàoshi", "key", "我的钥匙在桌子上。"),
        ]
        let image = seedImage()
        // Reversed so the first sample ends up newest, on top.
        for sample in samples.reversed() {
            store.save(
                LearningCard(word: sample.0, pinyin: sample.1,
                             translation: sample.2, example: sample.3),
                image: image
            )
        }
    }

    private static func seedImage() -> UIImage {
        if let url = Bundle.main.url(forResource: "plant", withExtension: "png"),
           let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        return UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
        }
    }
}
#endif
