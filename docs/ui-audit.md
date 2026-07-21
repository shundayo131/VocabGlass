# UI Audit

Redesign 前の現状調査。2026-07-21 時点のコードに基づく。コード変更なし。

## 1. 画面と Navigation

画面は 3 つ。NavigationStack は ContentView が 1 本持つだけで、深さは最大 2。

```
VocabGlassApp
  └─ ContentView (root, NavigationStack)
       ├─ NavigationLink → SessionView   (本文中の "Voice session" ボタン)
       └─ NavigationLink → HistoryView   (toolbar の "Deck" ボタン)
```

| 画面 | ファイル | 役割 |
|---|---|---|
| ContentView | Views/ContentView.swift | 手動キャプチャのデバッグ画面。写真プレビュー、カメラ操作、カード生成、保存 |
| SessionView | Views/SessionView.swift | 音声セッション。状態、残り時間、最新カード、開始/終了 |
| HistoryView | Views/HistoryView.swift | 保存済みデッキの一覧(サムネイル付き) |

補足:
- ContentView は実質「開発用の手動操作パネル」。デモの主役は SessionView。
- FlashcardSession (ViewModel) は実装済みだが、対応する画面はまだ無い。
- モーダル (sheet / fullScreenCover) は未使用。alert も未使用で、エラーは全てインラインの赤文字。

## 2. 各画面が扱う UI state

### ContentView
GlassesClient から読む: `capturedImage`, `card`, `isGenerating`, `registrationState`, `cameraOn`, `isReady`, `status`, `lastError`。
CardStore から読む: なし(save を呼ぶだけ)。
画面ローカルの @State は無し。全状態が ViewModel 側にある。

ボタンの出し分けが状態機械になっている:
- 未登録 → "Connect glasses"
- 登録済み & カメラ off → "Start camera"
- カメラ on → "Stop camera"
- `capturedImage != nil` → "Generate card" が出現
- `card != nil` → CardView + "Save to deck" が出現

### SessionView
SessionController から読む: `state` (idle/starting/active/ending), `statusLine`, `lastError`, `remainingSeconds`。
CardStore から読む: `cards.first`(最新カードのライブ表示)。
画面ローカル state 無し。`timeLeft` は表示用の computed のみ。

### HistoryView
CardStore から読む: `cards` 全件。`image(for:)` を行ごとに同期呼び出し。
画面ローカル state 無し。編集・削除・詳細表示の UI はまだ無い。

## 3. View / ViewModel / Repository の境界

```
Views (SwiftUI)
  ContentView / SessionView / HistoryView / CardView
      │ @ObservedObject
ViewModels (@MainActor ObservableObject)
  GlassesClient      … DAT session/stream + 写真 + カード生成呼び出し
  SessionController  … セッション全体の指揮者。他の全部品を知る唯一のクラス
  RealtimeClient     … OpenAI Realtime (WebRTC)
  AudioRouteManager  … Bluetooth HFP ルート
  FlashcardSession   … フラッシュカード復習の状態(UI 未接続)
Repository 相当
  CardStore          … デッキの永続化 (cards.json + JPEG)。ObservableObject でもある
Networking
  CardAPI            … Worker /generate 呼び出し (static func)
  WorkerConfig       … エンドポイント設定
```

依存注入は VocabGlassApp.init で手組み。全部 @StateObject で持ち、ContentView に手渡し。EnvironmentObject は未使用。

境界の評価:
- CardStore は「Repository + ObservableObject」の兼任。小規模アプリでは妥当で、redesign で分離する必要は無い。
- GlassesClient が肥大気味。DAT 制御、写真キャプチャ、カード生成 (`generateCard`) の 3 役を持つ。カード生成はデバイスと無関係なので、UI 再設計で ContentView を作り直すなら移動候補。

## 4. 再利用可能な UI Component

現状 1 つだけ:
- `CardView` (ContentView.swift 内 138-155 行): LearningCard の表示。ContentView でしか使われていない。

再利用されずに重複しているパターン:
- カード表示が 3 実装ある: CardView (LearningCard 用)、SessionView 35-50 行 (SavedCard + 画像)、HistoryView の行 (SavedCard + サムネイル)。word/pinyin/translation の並べ方がそれぞれ微妙に違う。
- サムネイル/プレースホルダ: HistoryView の `thumbnail(for:)` と ContentView の "No photo yet" プレースホルダは同型。
- フル幅ボタン: `Label + .frame(maxWidth: .infinity) + .buttonStyle + .controlSize(.large)` の組が 7 回コピーされている。
- エラー表示: `.font(.footnote).foregroundStyle(.red)` が ContentView と SessionView に重複。

Redesign では「カードの見た目」を 1 コンポーネントに統一するのが最優先。LearningCard と SavedCard の 2 型があるので、表示用の共通シェイプ(または protocol)を挟む設計が要る。

## 5. Color / Typography / Spacing

デザイントークンは存在しない。全てインラインのシステム値。

Color:
- `Color.gray.opacity(0.15)` (ContentView プレースホルダ)、`0.1` (CardView 背景)、`0.2` (HistoryView プレースホルダ) と 3 種の灰色が散在
- `.secondary`, `.red` (エラー)
- AccentColor.colorset は空 (システム既定のまま)
- ダークモードは触っていない(システム任せで一応動く)

Typography: 全てシステムの semantic font。`.largeTitle.bold()`, `.title3`, `.headline`, `.subheadline`, `.body`, `.footnote`, タイマーのみ `.system(.title, design: .monospaced)`。カスタムフォント無し。中国語表示も特別扱い無し。

Spacing / Shape:
- VStack spacing: 16 (画面), 6 (CardView), 4 (SessionView カード), 2 (HistoryView 行)
- HStack spacing: 12, 10, 8
- cornerRadius: 16 (大), 12 (中), 8 (サムネイル)
- `.padding()` は全て既定値

つまり redesign は白紙から決められる。移行コストになる既存トークンは無い。

## 6. Preview と Mock data

- `#Preview` / `PreviewProvider` は 0 件。プレビューは一切無い。
- Mock は DAT レイヤーにだけ存在: GlassesClient の `setUpMockDevice()` (simulator 限定、MWDATMockDevice) が MockResources/plant.mp4 と plant.png をカメラに流す。
- SavedCard / LearningCard のサンプルデータ、CardStore の in-memory 版は無い。HistoryView や新フラッシュカード画面をプレビューで作り込むなら、`CardStore` にディレクトリ注入 (テスト計画で提案済みの `init(directory:)`) + サンプルカードのフィクスチャが先に要る。

## 7. Loading / Empty / Error 状態

| 画面 | Loading | Empty | Error |
|---|---|---|---|
| ContentView | `isGenerating` でボタン文言が "Generating…" + disabled。写真待ちは `status` 文字列のみ | "No photo yet" プレースホルダ | `lastError` を赤の footnote |
| SessionView | starting/ending は `state.rawValue` と `statusLine` の生文字列 | カード未保存なら何も出ない(空状態の表現無し) | `lastError` を赤の footnote |
| HistoryView | 無し(同期読み込み) | "No saved cards yet" | 無し(読み込み失敗は空扱いに落ちる) |

特記:
- ProgressView / スピナーは 1 つも無い。ローディングは全部テキスト。
- `status` / `statusLine` は内部状態の生ダンプに近い ("session state: …", "stream: …")。デバッグには便利、プロダクト UI としては要翻訳。
- エラーは出っぱなしで、dismiss も自動クリアも無い (`lastError` は次の操作まで残る)。
- HistoryView の画像読み込みは行描画のたびに同期でディスクを読む。デッキが大きくなるとスクロールが引っかかる。redesign で async 化かキャッシュを検討。

## 8. Redesign で維持すべき機能

UI の裏の配線で、見た目を変えても壊してはいけないもの:

1. `ContentView.onAppear { client.start() }` と `.onOpenURL { client.handleUrl(url) }`。Meta AI アプリからの登録戻りはこの onOpenURL 経由。root 画面を差し替えるなら両方を新 root に移すこと。
2. ボタンの状態ゲート: "Capture photo" は `isReady`、"Generate card" は `!isGenerating`、"End session" は `state == .active` のみ有効。
3. 保存フローの後始末: "Save to deck" 後の `client.card = nil` (二重保存防止)。
4. セッション終了は必ず `controller.endSession()` 経由 (単一出口)。UI から直接 realtime や glasses を触らない。
5. SessionView の「最新カードのライブ表示」はデモの見せ場 (音声キャプチャの成果が即座に出る)。redesign 後も残す価値が高い。
6. spec.md の制約類 (camera medium/24 など) は UI から触れないので影響なし。ただし SessionView が `store.cards.first` を直読みしている点は、画面を作り替えるときに忘れやすい。
7. 新バックエンド (未接続): `CardStore.update` / `delete` / `delete(at:)` と `FlashcardSession`。UI 側はここに繋ぐだけでよい。

## 9. UI と business logic の結合箇所

強い順:

1. **ContentView の保存ロジック** (100-104 行): `store.save(card, image:)` と `client.card = nil` を View のボタンクロージャで直接実行。「保存したらドラフトを消す」というルールが View に埋まっている。GlassesClient か薄い ViewModel に `saveCard()` として移すのが素直。
2. **GlassesClient.generateCard**: ネットワーク処理 (CardAPI) がデバイスクライアントに同居。View から見ると 1 つの神オブジェクト。redesign で ContentView を分割するなら一緒に整理。
3. **`status` / `statusLine` が UI 文言そのもの**: ViewModel が英語の表示文字列を組み立てている ("tap Start camera" 等)。状態 enum + View 側で文言化、に直さないとローカライズも文言調整も ViewModel 修正になる。
4. **SessionView → `store.cards.first`**: View が Repository を直読み。動くが、「セッション画面が何を表示するか」の知識が View にある。
5. **HistoryView → `store.image(for:)`**: View がディスク I/O を同期で叩く。
6. ContentView のボタン出し分け (registrationState / cameraOn / isReady の分岐) は View に書かれているが、これは SwiftUI として普通の範囲。ただし分岐が増えるなら `enum CameraPhase` を ViewModel に切ると読みやすい。

## 10. まとめ (Redesign への示唆)

- 画面 3 + 未着手のフラッシュカード画面 1、という小さい面積。白紙 redesign が現実的。
- デザイントークン(色、字体、余白)はゼロから決められる。既存資産は無い。
- 最初に作るべき共通部品: カード表示 1 種、フル幅ボタンスタイル、エラー/ステータス表示。
- 事前の小さな下ごしらえが 2 つ: (a) プレビュー用のサンプルデータと CardStore のディレクトリ注入、(b) status 文字列の enum 化。どちらも見た目以前の配線。
- 触ってはいけない配線はセクション 8 の通り。特に onOpenURL と endSession 単一出口。
