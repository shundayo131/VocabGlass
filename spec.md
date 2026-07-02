# Learn Vocabulary with Glass — v2 Spec

Status: v1 vertical slice complete and verified on real glasses. v2 (voice
sessions + learning features) planned, not started. Last updated 2026-07-02.

## 1. Vision

A language learner wears Meta Ray-Ban (Gen 2) glasses, starts a session from
the iPhone app, and captures objects by voice: look at something and say
"Capture this." An AI layer turns the image into a vocabulary card in the
target language (French, Spanish, Chinese, or Japanese): a word, a
pronunciation aid, an English meaning, and an example sentence. Cards are
saved with the image so the learner builds a personal, photo-anchored
vocabulary deck from their own world, reviewable later as flashcards.

The glasses are an input device. The app runs on iPhone and pulls photos from
the glasses over the Meta Wearables Device Access Toolkit (DAT). Voice runs
over the glasses' standard Bluetooth audio connection, outside of DAT.

## 2. Where we are

v1 proved the core vertical slice: button-triggered glasses photo to saved AI
vocabulary card, working end to end on real hardware. Chinese only, capture by
on-screen button, cards saved locally and browsable in a history screen.

v2 makes it a useful demo: voice-driven capture sessions, four target
languages, and real review features (edit, delete, flashcards).

## 3. V2 scope

In scope:
1. Voice sessions: start a session from the app; the glasses camera stream and
   a realtime voice loop run together. "Capture this" triggers the photo-to-card
   flow with spoken confirmation. "End session" (or a 10 minute cap) ends it.
2. Target language selection: French, Spanish, Chinese, Japanese. Definitions
   in English. Pronunciation aid per language (pinyin for Chinese, kana or
   romaji for Japanese).
3. Learning features: edit and delete saved entries, review the deck as
   flashcards (image front, card fields back).

Out of scope (unchanged from the product doc):
- Folders, completion status, spaced repetition, or other advanced deck
  management.
- User authentication, multi-user sync, backend persistence.
- Production-level privacy and data management, App Store distribution.
- Starting a session from the glasses (not possible with current DAT).

## 4. Decisions made

| Topic | Decision | Notes |
|-------|----------|-------|
| Orchestration | The iOS app is the session orchestrator | The realtime voice API returns tool calls to the app, not to a backend. The app runs the capture, calls the entry worker, saves locally, and returns the tool result. No server-side session state, no push channel to the phone. |
| Realtime voice API | Gemini Live API, connected directly from the app | WebSocket from iOS. A Worker endpoint mints short-lived ephemeral tokens so the Gemini key never ships in the app. |
| Entry generation LLM | Anthropic Claude, via the existing Worker | Multimodal request plus structured outputs. Unchanged from v1 except for the language parameter and generalized schema. |
| Voice in/out | Glasses mic and speakers over standard Bluetooth (HFP), not DAT | DAT 0.8.0 has no microphone API. Meta's documented pattern for third-party apps is HFP through AVAudioSession. See section 6 for constraints. |
| Session length | 10 minutes, enforced by a client-side timer | Also bounded by Gemini Live session limits and token TTL; confirm during M10. |
| Spike first | Verify glasses audio + DAT stream together before building voice features | Desk research says this works (section 6); the spike confirms quality and stability on our hardware. Runs on a throwaway branch. |
| Card model | Generalize pinyin to pronunciation, add language | Decode-time migration maps old saved cards (pinyin, implicit Chinese) to the new shape. |
| Target language | User-selected: French, Spanish, Chinese, Japanese | Chosen at first run, changeable in settings. Applies to new cards only. |
| Storage | Local-first, unchanged | cards.json plus JPEG files in Documents. The Worker sees an image only for the moment it generates an entry. |
| Camera lifecycle | On-demand per session, unchanged | Stream opens when a session starts and closes when it ends. |

Carried over from v1: base64 image in JSON to the worker, structured outputs
enforcing the card fields, mock-first development where possible (voice and
audio work needs real glasses).

## 5. Architecture

```
Meta AI Glasses
  camera                     mic / speaker
  (DAT SDK)                  (Bluetooth HFP, not DAT)
      |                           |
      v                           v
iOS App  --  session orchestrator
  - DAT layer:    Wearables / DeviceSession / Stream (GlassesClient)
  - Voice layer:  AVAudioSession (Bluetooth route) + GeminiLiveClient
  - Session:      SessionController (tool calls -> capture -> generate -> save)
  - State:        ObservableObject view models
  - Local cache:  JPEG files + card metadata
      |                           |
      | HTTPS                     | WebSocket (ephemeral token)
      v                           v
Cloudflare Workers            Gemini Live API
  POST /token                   listens, speaks short feedback,
  POST /generate                returns tool calls
      |                         (capture_object, end_session)
      v
Claude (image + language -> card JSON)
```

Session flow: start from the app -> open DAT session and stream, configure the
Bluetooth audio route, fetch a token, connect to Gemini Live. "Capture this" ->
Gemini acknowledges by voice and returns a `capture_object` tool call -> the app
captures a photo over DAT, POSTs it with the target language to `/generate`,
saves the returned card and image locally, and sends the result back as the
tool response -> Gemini confirms by voice ("Saved. This is pomme, apple in
French."). "End session" returns an `end_session` tool call; the app tears down
the WebSocket, audio session, and DAT session. A 10 minute timer does the same.

Both Worker endpoints stay stateless; no long execution windows are needed.

### Web-to-iOS mental model map

- SwiftUI `View` is like a React function component. `@State` / `@Published`
  on an `ObservableObject` are like `useState` plus a store.
- DAT `stateStream()` and `.listen {}` are like subscribing to an event
  emitter. `for await x in stream()` maps to a TS async iterator.
- `AVAudioSession` is like `getUserMedia`: you declare that you want record
  and playback with Bluetooth allowed, and the OS picks the route. The app
  never talks to Bluetooth directly.
- The glasses are a peripheral, not a runtime. Camera is a Bluetooth webcam
  read through a vendor SDK; mic and speakers are a standard Bluetooth headset.
- `URLSession` is like `fetch`. The Gemini Live connection is a plain
  WebSocket, like `new WebSocket(url)` with audio chunks going both ways.

## 6. Audio findings (desk research, 2026-07)

What we verified before building, and the constraints that shape the code:

- DAT 0.8.0 has no microphone or audio API (modules: Core, Camera, Display,
  MockDevice). Meta's documented pattern for third-party mic access is the
  standard Bluetooth Hands-Free Profile through platform audio APIs.
- Mic input over HFP is 8 kHz mono. While HFP is active, speaker output also
  drops to 8 kHz mono (A2DP high-quality playback and HFP are mutually
  exclusive). Telephone quality: fine for command recognition, and the
  glasses' beamforming still applies; the tradeoff is response audio comfort,
  not intelligibility.
- Simultaneous DAT camera streaming and HFP audio is supported, not just
  tolerated: Meta's audio docs give an explicit ordering rule for combining
  them, and a third-party app (a language coach) runs camera stream + HFP
  speech-to-text + TTS output in production on Ray-Ban glasses.
- Ordering rule: add the camera stream to the session first, then configure
  the HFP route (set the glasses as preferred input, let the route settle),
  then start the stream. Configuring HFP after the stream starts can make the
  audio route fail silently. GlassesClient currently calls `addStream` and
  `stream.start()` back to back; the voice path must insert HFP setup between
  them.
- Bluetooth bandwidth is real but not blocking: community reports put `.high`
  resolution raw-codec streaming at the practical ceiling on gen-1 hardware.
  We stream `.medium`, which leaves headroom for HFP.
- "Hey Meta" is not affected by any of this because wake word detection runs
  on the glasses' own DSP and Meta's assistant audio travels over a
  proprietary channel. That path is not exposed to third parties.

References: Meta "Microphones and speakers" and "Integration overview" docs,
meta-wearables-dat-ios discussions #116 and #141. Links in section 10.

## 7. Data model

`LearningCard` (the worker's response): `word`, `pronunciation`, `translation`
(English), `example` (sentence in the target language).

`SavedCard` (stored locally): the four card fields plus `id`, `language`,
`imageFileName`, and `createdAt`.

Worker `POST /generate` request: `{ image, mediaType, language }`.
Response shape:
```json
{ "word": "...", "pronunciation": "...", "translation": "...", "example": "..." }
```
Enforced by Claude structured outputs. `pronunciation` is pinyin for Chinese,
kana or romaji for Japanese, and may be empty for French and Spanish.

Migration: existing saved cards decode `pinyin` into `pronunciation` and
default `language` to Chinese. One-way, done at load time.

Worker `POST /token` response: an ephemeral Gemini Live token plus its expiry.

## 8. Milestones

One at a time, skeleton-first, check in at each boundary. Voice sessions come
before the learning features: the voice capture loop is the heart of the demo,
so it lands first (with Chinese still hardcoded), and languages, editing, and
flashcards follow. M6 is design, M7 runs on a throwaway spike branch;
everything after builds on main.

- M6 — UI mockups. Mock up the main screens before building: home (session
  start), active session, deck, card detail/edit, flashcard review. Agree on
  layout and flow, then use them as the reference for M9 and later UI work.
- M7 — Audio spike (branch `spike/voice-audio`). A debug-only screen plus a
  small `AudioSpike` helper: configure the Bluetooth HFP route, confirm the
  route lands on the glasses, record and play back a loop, then run the
  existing camera stream and photo capture at the same time using the section
  6 ordering rule. Exit criteria: route is stable for minutes, capture works
  during audio, 8 kHz quality judged acceptable by ear. Findings go into
  section 6; the branch is then deleted.
- M8 — Gemini Live plumbing. Worker `POST /token` minting ephemeral tokens;
  `GeminiLiveClient` in the app: WebSocket, audio up and down, tool
  declarations (`capture_object`, `end_session`). Testable with the iPhone
  mic, no glasses needed. Confirm session limits and token TTL cover 10
  minutes.
- M9 — Voice session orchestration. `SessionController` ties DAT, audio, and
  Gemini together per the section 5 flow, including the HFP-before-start
  ordering, the 10 minute cap, and teardown on device-initiated session end.
  Session UI per the M6 mockups. Chinese hardcoded until M10.
- M10 — Language selection. First-run and settings picker; worker takes
  `language` and returns the generalized schema; model rename and decode
  migration per section 7. Voice confirmations follow the selected language.
- M11 — Edit and delete entries. Swipe-to-delete and an edit sheet in
  HistoryView; update/delete with image file cleanup in CardStore.
- M12 — Flashcard review. Review mode over the deck: image front; word,
  pronunciation, translation, example on the back; tap to flip, swipe to
  advance.
- M13 — Demo polish. Session screen with live status and last saved card,
  error surfacing, hardening for a live demo.

## 9. Still open

- Gemini Live specifics: exact session duration limits, ephemeral token TTL,
  input audio format expectations at 8 kHz, and interruption behavior. Resolve
  in M10.
- Whether "Hey Meta" or other glasses features contend with an active DAT
  session plus HFP in practice. Watch during M6/M11; docs say only one session
  runs at a time and some device features pause during it.
- Pronunciation content for French and Spanish: empty, or light IPA. Decide
  in M9 with prompt tuning.
- Live viewfinder while aiming: still deferred; revisit if voice capture makes
  aiming harder.
- Backend persistence (D1) and image storage (R2): still deferred, unchanged.

## 10. References

- DAT API surface and conventions: see AGENTS.md.
- DAT docs: https://wearables.developer.meta.com/docs/develop/
- Microphones and speakers: https://wearables.developer.meta.com/docs/microphones-and-speakers/
- Known issues: https://wearables.developer.meta.com/docs/develop/dat/knownissues/
- DAT package: https://github.com/facebook/meta-wearables-dat-ios
- Camera + HFP in production, BT bandwidth ceiling: https://github.com/facebook/meta-wearables-dat-ios/discussions/116
- Raw mic access request, "Hey Meta" DSP notes: https://github.com/facebook/meta-wearables-dat-ios/discussions/141
- Gemini Live API: https://ai.google.dev/gemini-api/docs/live
