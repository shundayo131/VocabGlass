# Design Directions

3 方向の UI mock の設計意図と遷移図。
前提: [design-brief.md](design-brief.md)、現状: [ui-audit.md](ui-audit.md)。

コードは `ios/VocabGlass/VocabGlass/DesignMocks/` にある。全て固定 mock
data (`MockData.swift`) のみで、CardStore / DAT / ネットワークには一切
触れない。Production の View は未変更。各画面・各状態 (idle / starting /
active / error / empty / revealed / finished / XXL type) に `#Preview` が
あり、Xcode の canvas でそのまま比較できる。

3 方向は色違いではなく、**構造 / カードの見せ方 / 復習の操作**を変えた。

| | A: Utility | B: Visual Library | C: Journal |
|---|---|---|---|
| ルート構造 | NavigationStack 1 本 | TabView 2 タブ | 日付グループの List |
| ホーム画面 | セッションそのもの | Capture タブ | 学習ログ + セッションバナー |
| カードの主役 | テキスト (List 行) | 写真 (グリッド) | 蓄積 (タイムライン) |
| 復習の操作 | ボタンで reveal / next | タップ reveal、全画面写真 | 横スワイプ + フリップ |
| 編集・削除 | 詳細 push + Edit sheet / スワイプ | 詳細 sheet 内ボタン | Menu / スワイプ |
| 賭けているもの | 速さと確実さ | 写真が記憶のフック | 蓄積が続ける動機になる |

---

## Direction A: Utility

**ファイル**: `DirectionA_Utility.swift`

**思想**: Brief の「最短距離」を最も直球に解釈した案。ホーム画面が
セッション画面そのもので、起動 → 開始が 1 タップ。全部 iOS 標準部品
(List, Form, sheet, ContentUnavailableView) で、発明はゼロ。

```
UtilityHomeView (root)
  ├─ [Start voice session] … その場で状態遷移 (画面移動なし)
  └─ toolbar "Deck"
       └─ UtilityDeckView (push)
            ├─ 行タップ → UtilityCardDetailView (push)
            │                └─ "Edit" → UtilityEditSheet (sheet)
            ├─ 行スワイプ → Delete
            └─ toolbar "Review" → UtilityFlashcardView (push)
```

- セッションの状態 (Ready / Connecting / Listening / error) はホーム
  上部の 1 枚のステータスカードに集約。audit で問題視した内部状態の
  生ダンプは「要約 1 行 + 症状に応じた次の一手」に置き換えた。
- キャプチャが保存されると "Saved just now" 行がステータスの下に出る。
  現 SessionView の「最新カードのライブ表示」の後継。
- 復習は push 遷移。フルスクリーンにしない代わりに実装も学習コストも
  最小。
- 強み: 実装が最速、Dynamic Type とアクセシビリティがほぼ無料で付く。
- 弱み: 見た目の個性は出ない。写真が小さく、このアプリ固有の
  「実物を撮った」感が薄い。

## Direction B: Visual Library

**ファイル**: `DirectionB_Library.swift`

**思想**: Brief の「2 場面を混ぜない」を構造にした案。Capture タブは
外でグラス越しに使う画面 (文字最小、巨大ボタン 1 個)、Deck タブは家で
じっくり触る画面 (写真グリッド)。写真こそが記憶のフックという仮説に
賭ける。

```
LibraryRootView (TabView)
  ├─ Tab "Capture": LibraryCaptureView
  │     └─ [丸ボタン] … その場で状態遷移 (画面移動なし)
  │        active 中は保存トーストが積まれる (背景写真は決定で廃止)
  └─ Tab "Deck": LibraryDeckView (NavigationStack)
        ├─ タイルタップ → LibraryCardSheet (sheet, medium/large)
        │                   └─ Edit / Delete ボタン
        └─ [Review N cards] (画面下の capsule)
             └─ LibraryFlashcardView (fullScreenCover)
```

- Capture タブの文字は状態チップ 1 個とボタン下のキャプション 1 行
  だけ。セッション中は背景が現在の視界 (mock では plant 写真) になり、
  「グラスが見ているもの」を画面が反映する。
- フラッシュカードは全画面写真から始まり、タップで material パネルが
  答えを出す。「画像を先に見る」という復習仕様を最も強く表現した形。
- 削除・編集は詳細 sheet の中のみ。グリッドにスワイプが無いため、
  一覧からの直接削除は A / C より一段深い。
- 強み: このアプリにしかない画面になる。デモ映えは 3 案で最強。
- 弱み: 実装コストが最大。写真の質が悪いとグリッド全体が沈む。
  Capture タブの白文字 on 写真はコントラスト管理が必要。

## Direction C: Journal

**思想**: 「いつ・どこで出会った単語か」という文脈ごと記録する案。
ホームは日付グループの学習ログで、セッションは上部のバナーに住む。
統計行 (単語数 / 今日 / 連続日数) で蓄積を見せ、続ける動機を作る。

**ファイル**: `DirectionC_Journal.swift`

```
JournalHomeView (root, List)
  ├─ セッションバナー … その場で状態遷移 (画面移動なし)
  ├─ 統計行 (words / today / streak)
  ├─ "Today" / "Yesterday" / … セクション
  │     ├─ 行タップ → JournalCardDetailView (push)
  │     │               └─ toolbar Menu → Edit / Delete
  │     └─ 行スワイプ → Delete
  └─ toolbar "Review" → JournalFlashcardView (fullScreenCover)
        └─ 横ページング、タップでカードがフリップ、最終ページが完了
```

- 復習は横スワイプでページ送り、タップで 3D フリップ。表は写真だけ
  ("What is this?")、裏が 4 フィールド。スワイプで進む操作は
  「何枚もめくる」復習のリズムに合う。
- キャプチャの成果が「今日」セクションの一番上に増えていく。
  セッション中もホームに留まるので、増える様子がそのまま見える。
- 統計 (streak) は現バックエンドに無いデータ。この案を選ぶ場合、
  カウントは createdAt から導出できるが、streak は新規実装になる。
- 強み: 復習アプリとしての「戻ってくる理由」が構造に入っている。
  リスト基盤なので Dynamic Type にも強い。
- 弱み: 起動直後の画面にセッション以外の情報が多く、Brief の
  「情報量を抑える」とは緊張関係にある。streak が範囲外実装を誘発
  しがち (spec の間隔反復 out of scope に注意)。

---

## 共通の設計判断

3 案とも共有している判断。方向選定とは独立に、production 移植時に
そのまま持っていく:

1. **セッションの開始・終了で画面遷移しない**。状態はその場で変わる。
   audit セクション 8 の「endSession 単一出口」と相性が良い。
2. **状態は enum (SessionPhase) 駆動**。文言は View 側が持つ。
   production の `status` / `statusLine` 生文字列 (audit セクション 9)
   をこの形に置き換える前提。
3. **エラーは「要約 + 次の一手」**。生のエラー文字列を出さない。
4. **空状態は ContentUnavailableView**。iOS 標準の空画面表現。
5. **削除は必ず一覧か詳細から 2 経路以内**。backend の
   `CardStore.delete` / `update` に UI から繋ぐだけの状態にしてある。
6. **フォントは全て semantic**。固定サイズ無し。XXL type の Preview で
   3 案とも破綻しないことを確認済み (B の写真上テキストのみ要注意)。

## 確認方法

Xcode で任意の DesignMocks ファイルを開き、canvas (⌥⌘↩) で Preview を
選ぶ。実機・シミュレータ起動は不要。Preview 名は `A · Home · idle` の
形式で、方向 · 画面 · 状態を表す。

## 決定 (2026-07-21)

**Direction B: Visual Library を採用。** ただし A から 2 要素を移植:

1. **Capture タブのステータス表示は A のステータスカード**
   (eyeglasses アイコン + "Ready" + 説明 1 行)。B の小さな状態チップは
   廃止。写真背景の上でも読めるよう material 背景に変更した。
2. **フラッシュカードは A の縦積みレイアウト**
   (プログレスバー + 枠付き写真 + "Show answer" ボタン)。B の
   全画面写真 + タップ reveal は廃止。提示は fullScreenCover のままで、
   Close ボタンを付けた。

3. **active 中の全画面写真背景を廃止**。背景は全状態で静かな
   グラデーションに統一。あの写真は「最後にキャプチャした静止画」で
   あって現在の視界ではなく、ライブ表示に見せるのは嘘になるため。
   写真は保存トーストの中にだけ出す。
4. **Capture タブに音声ガイダンスカードを追加** (idle のみ)。
   「"Capture this" で保存」「"End session" で終了」「10 分で自動終了」
   「ロック・アプリ離脱してもセッション継続」の 4 行。セッション中は
   スマホを見ない前提なので、読める瞬間 = 開始前だけに出す。

`DirectionB_Library.swift` はこの合成済みの状態に更新済み。
A / C のファイルは比較用に残してあり、production 移植が始まったら削除
する。

残っている open question (B 採用により確定が必要):
- 一覧 (グリッド) からの削除経路。現状は詳細 sheet 内の Delete のみ。
  グリッド長押しの context menu に Delete を足すのが標準的な解。
- Deck タブの並び順とフラッシュカードの並び順 (新しい順 / シャッフル)。

## Style 探索 (2026-07-21)

構造は B で確定したので、次はビジュアルスタイルを 3 案。方向 A / C の
ファイルは削除済み (`DirectionB_Library.swift` が構造の基準として残る)。
各スタイルは代表 3 画面 (Capture / Deck / Flashcard) のみ。目標は
「modern iOS。clear, clean, sleek。不要な色と物を置かない」。

| | S1: Quiet | S2: Ink | S3: Soft |
|---|---|---|---|
| ファイル | `Style1_Quiet.swift` | `Style2_Ink.swift` | `Style3_Soft.swift` |
| 思想 | iOS 標準素材の洗練 | モノクロのギャラリー | 白カードと 1 色 |
| 色 | システムアクセント 1 色 | 黒白のみ。色は写真だけ | インディゴ 1 色 |
| 面 | material (すりガラス) | 塗りなし + hairline 枠 | 白カード + 淡い影 |
| 角丸 | 18 continuous | 10 (シャープ) | 24 continuous |
| 文字 | SF そのまま | 大文字トラッキング、pinyin 等幅 | rounded デザイン |
| グリッド | 写真 + material キャプションバー | 写真の下にキャプション (図録風) | 写真 + 文字を白カードに同居 |
| 主ボタン | borderedProminent | 黒塗り capsule + 大文字 | インディゴ + 色付き影 |

各案の狙い:

- **S1 Quiet**: 素材も色も iOS 標準のまま丁寧に組む。スタイルが内容の
  後ろに消える。実装コスト最小、失敗しようがない案。
- **S2 Ink**: 画面から色を全部抜き、写真だけが色を持つ。UI は図録の
  余白とキャプション。`Color.primary` ベースなのでダークモードは自動で
  成立する。締まって見えるが、遊びはない。
- **S3 Soft**: グループ背景 + 白カード + 影で柔らかい階層を作る。
  rounded 字形と 1 色のインディゴで親しみを足す。学習アプリらしさは
  最も出るが、影と色 1 つぶん S1/S2 より要素が多い。

Preview 名は `S1 Quiet · Capture · idle` の形式。canvas で横に並べて
比較する。

## 次の判断

1. スタイルを 1 つ選ぶ (要素の混合も可。例: S1 の面 + S2 の
   タイポグラフィ)。
2. 選んだスタイルのトークン (色、角丸、字体、面) を確定し、
   `DirectionB_Library.swift` に反映して mock を完成形にする。
3. その後 production への移植計画。audit セクション 8 の維持リスト
   (onOpenURL、endSession 単一出口、保存後の card クリア等) を
   チェックリスト化し、TabView 化にともなう root 画面の組み替えから
   着手する。
