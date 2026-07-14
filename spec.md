# Learn Vocabulary with Glass — v2 Spec

Status: v1 vertical slice complete and verified on real glasses. v2 in
progress: M7 audio spike and M8 Gemini Live plumbing done and verified on
device (voice both ways, tool calls, tool responses). Next is M9 voice
session orchestration. Last updated 2026-07-07.

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
   flow with spoken confirmation. The session keeps running while the iPhone is
   locked or the app is in the background. It ends by voice command ("End
   session"), by a button in the app, or at the 10 minute cap.
2. Target language selection: French, Spanish, Chinese, Japanese. Definitions
   in English. Pronunciation aid per language (pinyin for Chinese, kana or
   romaji for Japanese).
3. Learning features: edit and delete saved entries, review the deck as
   flashcards (image shown first, answer revealed below it).

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
| Session length | 10 minutes, enforced by a client-side timer | Also bounded by Gemini Live session limits and token TTL; confirm during M8. |
| Background sessions | The session keeps running with the phone locked or the app backgrounded | Enabled by the iOS audio background mode (`UIBackgroundModes: audio` in Info.plist): an app actively recording and playing audio stays alive in the background, which also keeps the WebSocket and DAT work running. Whether the DAT stream itself survives backgrounding is verified in M7. |
| Ending a session | Voice command, in-app button, or the timer | All three paths run the same teardown in SessionController. |
| UI design | Deliberately simple, function over polish | The M6 mockups define structure and flow only, not visual design. The owner writes the SwiftUI as coding practice, with skeletons and guidance from Claude. |
| Flashcard reveal | "Show answer" below the image, not a flip animation | Simpler to build and to use one-handed. A flip can come later if wanted. |
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

### Live API constraints and the resulting behavior (M9)

Facts, measured on device:

- Turn latency (speech end to reply audio) is 3 to 5 seconds. This is
  the platform floor (server VAD plus generation); it cannot be
  engineered away on our side.
- The mic streams continuously. Talking over Gemini reaches the API
  immediately; playback of the stale reply is flushed on the server's
  interrupted signal.
- An unanswered tool call locks the model (it stops responding until a
  response arrives). Every tool call must be answered, even to ignore
  it.
- A pending tool call also makes the model reluctant to issue further
  tool calls.
- capturePhoto takes 2 to 7 seconds, card generation 2 to 3 seconds
  (with photos downscaled to 1024 px before upload).
- The server-side session can die silently while the WebSocket stays
  alive: pings keep ponging and sends keep completing, but nothing is
  received, not even input transcriptions. Confirmed on device with 60
  seconds of one-way traffic. The client detects 30 seconds of server
  silence and rebuilds the Gemini leg (new token, new socket) without
  touching DAT or audio.

Behavior chosen under these constraints:

- One capture at a time. Requests during a capture are answered with
  scheduling SILENT (the model stays free, says nothing). Stacked
  latencies fire late captures when the user is no longer aiming.
- Fixed narration: "Capturing." on the tool call, "Stored." on the
  result. Longer narration clogs the channel at this turn latency.
- Playback queue is flushed on interrupted and hard-capped at 6
  seconds, so conversation lag cannot accumulate.
- Option noted for later: grab the capture image from the live stream
  frame (0 s instead of capturePhoto) and play a local shutter earcon.
- Open follow-up: if a dead voice link ever needs reporting (uplink
  stall), voice cannot carry its own failure; the phone needs a local
  notification or haptic. M13 candidate.

### Voice session findings (M9, on device 2026-07-10)

- Disconnect other Bluetooth audio (AirPods) before a session: two
  headsets contend for HFP and the glasses voice link connects then
  immediately drops.
- Keep the camera stream at medium/24; do not lower it to save
  bandwidth. At low/15 the glasses appear to move the stream onto the
  Bluetooth radio, which starves the HFP voice link: the route still
  shows the glasses, but the mic delivers silence.
- Realtime discipline in both directions, or delay accumulates and never
  recovers: drop mic chunks when the socket cannot drain in real time
  (backpressure), and flush the playback queue the moment Gemini signals
  "interrupted". Both are implemented; the interruption flush is what
  fixed the conversation drifting a minute behind.
- The session screen shows the newest deck card, including ones saved
  before the session; filter to this session's cards in M13.

### Spike results (M7, verified on device 2026-07-06)

Setup: Ray-Ban Meta (Gen 2), glasses firmware v126, glasses-side DAT app
updated to the SDK 0.8 version, iPhone on iOS 26.6, DAT SDK 0.8.0.

- HFP route, loopback recording, and playback through the glasses all work.
- The DAT camera stream and HFP recording run at the same time; photo
  capture works while audio is active.
- Reverse setup order (camera stream first, HFP after) also worked; the
  documented ordering rule did not bite on this firmware. Keep the
  recommended order anyway.
- Background: with UIBackgroundModes audio (plus the existing
  bluetooth-central and external-accessory modes), recording and the camera
  stream both survive the screen locking.
- "Hey Meta" still triggers during a session and takes the microphone; our
  recording stops. Mitigation: turn the wake word off during sessions (Meta
  AI app setting), and M9 should add route-change recovery so the session
  can heal itself.
- 0.8 migration gotcha: DAT 0.8 requires updating the glasses-side DAT app
  (Meta AI app > device > App Info > Install). Until then, every session
  dies right after start. The failure is silent unless the session error
  stream is observed before start(). GlassesClient now observes errors
  before start, waits for .started by polling the live state with a 10 s
  timeout instead of awaiting stateStream() (whose events can be missed),
  and has openGlassesAppUpdate() to jump to the Meta AI update screen.

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
- M7 — Audio spike. Done 2026-07-06; all exit criteria passed, results in
  section 6. The debug-only spike screen (VoiceSpikeView + AudioSpike) stays
  in the app as a diagnostics tool until the M13 cleanup.
- M8 — Gemini Live plumbing. Done 2026-07-07, verified on device with the
  iPhone mic: token mint, WebSocket connect, two-way audio, tool calls, and
  spoken tool results. Findings that shaped the code: ephemeral tokens use
  the BidiGenerateContentConstrained method; system prompt and tools must be
  baked into the token constraints (client setup is ignored for them);
  scheduling sits next to id and name in a function response. Connection
  lifetime is about 10 minutes with a GoAway warning, handled in M9.
- M9 — Voice session orchestration. `SessionController` ties DAT, audio, and
  Gemini together per the section 5 flow, including the HFP-before-start
  ordering, the 10 minute cap, background continuation, and teardown from all
  three end paths (voice command, in-app button, timer) plus device-initiated
  session end. Session UI per the M6 mockups, kept simple. Chinese hardcoded
  until M10.
- M10 — Language selection. First-run and settings picker; worker takes
  `language` and returns the generalized schema; model rename and decode
  migration per section 7. Voice confirmations follow the selected language.
- M11 — Edit and delete entries. Swipe-to-delete and an edit sheet in
  HistoryView; update/delete with image file cleanup in CardStore.
- M12 — Flashcard review. Review mode over the deck: the image is shown first
  with the answer hidden; a "Show answer" tap reveals word, pronunciation,
  translation, and example below it. Swipe or a next button to advance.
- M13 — Demo polish. Session screen with live status and last saved card,
  error surfacing, hardening for a live demo.

## 9. Still open

- Gemini Live specifics: exact session duration limits, ephemeral token TTL,
  input audio format expectations at 8 kHz, and interruption behavior. Resolve
  during the voice milestones.
- Resolved in M8: /token now bakes the system prompt, tools, and modality
  into liveConnectConstraints.config. This was required anyway, because the
  constrained WebSocket method ignores client-side setup for those fields
  (found when Gemini reported having no tools), and it also locks a leaked
  token to VocabGlass-only sessions.
- Resolved in M7: "Hey Meta" does contend; it takes the mic and stops our
  recording. Open follow-up: how well the M9 route-change recovery heals the
  session after an intervention.
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
