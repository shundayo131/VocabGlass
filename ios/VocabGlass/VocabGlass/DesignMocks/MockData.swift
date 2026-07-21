//
//  MockData.swift
//  VocabGlass DesignMocks
//
//  Fixed sample data shared by the three design-direction mocks.
//  Never touches CardStore, networking, or the DAT stack.
//

import SwiftUI

enum MockData {

    struct Card: Identifiable {
        let id = UUID()
        let word: String
        let pronunciation: String
        let meaning: String
        let example: String
        let daysAgo: Int
    }

    static let cards: [Card] = [
        .init(word: "植物", pronunciation: "zhíwù", meaning: "plant",
              example: "这个植物很漂亮。", daysAgo: 0),
        .init(word: "杯子", pronunciation: "bēizi", meaning: "cup",
              example: "杯子里有咖啡。", daysAgo: 0),
        .init(word: "窗户", pronunciation: "chuānghu", meaning: "window",
              example: "请打开窗户。", daysAgo: 1),
        .init(word: "钥匙", pronunciation: "yàoshi", meaning: "key",
              example: "我的钥匙在桌子上。", daysAgo: 1),
        .init(word: "自行车", pronunciation: "zìxíngchē", meaning: "bicycle",
              example: "他每天骑自行车上班。", daysAgo: 2),
        .init(word: "书架", pronunciation: "shūjià", meaning: "bookshelf",
              example: "书架上有很多书。", daysAgo: 3),
    ]

    // Session states the mocks render. Mirrors SessionController.SessionState
    // plus an error case, without depending on it.
    enum SessionPhase {
        case idle, starting, active, error
    }

    // The bundled mock photo (same file the simulator mock camera uses).
    static var photo: UIImage? {
        guard let url = Bundle.main.url(forResource: "plant", withExtension: "png")
        else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
}

// The sample photo, with a gradient fallback so previews never show a hole.
struct MockPhoto: View {
    var body: some View {
        if let image = MockData.photo {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            LinearGradient(colors: [.green.opacity(0.5), .teal],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
