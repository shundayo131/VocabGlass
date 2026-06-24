# Learn Vocabulary with Glass — v1 Spec

Status: v1 vertical slice complete and verified on real glasses. Last updated 2026-06-24.

## 1. Vision

A language learner wears Meta Ray-Ban (Gen 2) glasses, looks at a real-world
object, and captures it through the app. An AI layer turns the image into a
vocabulary card in the target language (Chinese first): a word, its reading, a
translation, and an example sentence. Cards are saved with the image so the
learner builds a personal, photo-anchored vocabulary deck from their own world.

The glasses are an input device. The app runs on iPhone and pulls photos from
the glasses over the Meta Wearables Device Access Toolkit (DAT).

## 2. Why this v1 exists

v1 proves the core vertical slice: glasses photo to saved AI vocabulary card.
It stays ruthlessly small and favors a working end-to-end loop over feature
breadth, as the foundation for larger prototypes next.

## 3. V1 scope

In scope (all delivered):
1. [Done] Boot the app and configure DAT. Show registration and connection state.
2. [Done] Registration plus camera permission flow through the Meta AI app. The
   app requests camera permission before opening the stream.
3. [Done, adjusted] On-demand camera: tapping Start camera creates a
   DeviceSession, adds a Stream, and reflects session state honestly. We do not
   render a live viewfinder; capturing pulls a still off the running stream.
4. [Done] Manual Capture button: capture a still off the stream, preview it, save
   the JPEG locally.
5. [Done] Card generation: the app sends the captured photo to the worker, which
   calls Claude and returns a vocabulary card (word, pinyin, translation,
   example). The app fills the card from that result.
6. [Done] LearningCard model, local persistence, and a history screen that lists
   saved cards with thumbnails.

Out of scope for v1 (do not build or pad toward):
- Voice command as the capture trigger (later phase).
- Realtime conversational Q&A about what the user sees (v2).
- Spaced repetition, analytics, sync, auth, App Store polish, cross-platform.

Leave a comment marker where a v2 hook would attach. Nothing more.

## 4. Decisions made

| Topic | Decision | Notes |
|-------|----------|-------|
| Target language | Chinese (Simplified) plus pinyin | Card holds hanzi, pinyin, English gloss, example sentence. Hardcoded for v1, configurable later. |
| Storage | Local-first, backend later | Shipped local-only first: cards and images persist on device (cards.json plus JPEG files in Documents). Backend persistence through the Worker is deferred; when added, the store will be Cloudflare D1. |
| Mock vs real glasses | Mock-first through M4 | Build and verify the full loop against MockDeviceKit in the simulator. Touch real glasses only at M5. |
| Camera lifecycle | On-demand | The stream is not held open at launch. The user taps Start camera to open the session and stream, captures, then Stop camera (or it returns to idle if the device ends the session). Avoids constant-stream battery, heat, and contention with other glasses experiences. |
| AI request | base64 image in JSON, structured outputs | The app sends the JPEG as base64 in a JSON body. The worker calls claude-opus-4-8 and uses structured outputs so the four card fields always come back as valid JSON. |
| Audio output | Out for v1 | No TTS or pronunciation playback. Natural v1.5 add. |

## 5. Architecture

```
Meta glasses (input device, not an app runtime)
        |  Bluetooth
        v
Meta AI companion app   (registration + permission grants happen here)
        |  DAT SDK talks through this
        v
iOS app (Swift / SwiftUI)
   - DAT layer:   Wearables / DeviceSession / Stream   (the "glasses client")
   - State:       ObservableObject view models         (store + view state)
   - UI:          SwiftUI views                        (declarative components)
   - Local cache: JPEG files + card metadata           (offline display)
   - API client:  URLSession -> Worker                 (like fetch)
        |  HTTPS, image + instruction
        v
Cloudflare Worker
   - POST /generate : image in, calls Claude, returns word card
   - persistence of cards (store TBD: D1 or Supabase)
        |  Anthropic Messages API (multimodal)
        v
Claude -> { word, pinyin, translation, example } -> app -> saved LearningCard
```

### Web-to-iOS mental model map

- SwiftUI `View` is like a React function component. A struct that renders from
  state and re-renders when state changes.
- `@State` and `@Published` on an `ObservableObject` are like `useState` and a
  store. A view model is the screen's hook plus store.
- DAT `stateStream()` and `.listen {}` publishers are like subscribing to an
  event emitter or EventSource. `for await x in stream()` maps to a TS async
  iterator.
- The glasses are a peripheral, not a runtime. Closest web analogy is a
  Bluetooth webcam the page reads from, not a server you deploy to.
- `URLSession` is like `fetch`. The Worker world is unchanged from what the
  owner already knows. The only new part is sending an image to it.

## 6. Data model (draft)

`LearningCard`:
- `id` (UUID)
- `imagePath` or `imageURL` (local cache path; remote URL if uploaded)
- `word` (hanzi)
- `pinyin`
- `translation` (English)
- `example` (sentence in Chinese)
- `createdAt`

Worker `POST /generate` response shape (draft):
```json
{ "word": "...", "pinyin": "...", "translation": "...", "example": "..." }
```

These shapes get firmed up in M4 when we wire the Worker and confirm the Claude
request format against the claude-api skill.

## 7. Milestones

Each milestone: explain the concept, hand over a skeleton plus instructions, let
the owner write it, review together, then check in before moving on.

- M0  [Done] Project skeleton. SwiftUI app, iOS 16+. Add the DAT package.
  Configure Info.plist. Call `Wearables.configure()`. Build clean on the simulator.
- M1  [Done] Mock device plus session lifecycle. Wire MockDeviceKit, drive
  powerOn/unfold/don, create and start a DeviceSession, render session state.
- M2  [Done] Stream plus capture. Add a Stream, feed the mock a sample video so
  it reaches streaming, wire the Capture button and photoDataPublisher, preview
  the still. Live viewfinder frames were not needed for the slice.
- M3  [Done, adjusted] Local save plus history. Define LearningCard / SavedCard,
  save the JPEG and card locally, list saved cards with thumbnails. We skipped
  the hand-typed card and went straight to the AI result once M4 worked.
- M4  [Done, generate slice] Worker plus Claude. Hono worker exposes
  POST /generate; the app sends the photo and shows the generated card. Backend
  persistence (D1) is deferred; cards are saved locally for now.
- M5  [Done] Real glasses. Registration plus URL-callback flow works on device.
  The worker is deployed to Cloudflare; the app reads its URL from a local,
  gitignored WorkerConfig.plist. Verified end to end on real glasses: connect,
  start camera, capture, generate card, save.

Notes on how it actually went: M1 and M2 were built together against the mock.
Registration UI lives on the real-device path (M5), not the mock path, because
the simulator cannot complete the Meta AI registration deep link. Two device
fixes were needed: request camera permission before opening the stream (or the
device ends the session immediately), and make the camera on-demand rather than
held open at launch.

## 8. Decisions resolved during v1

- Image handling to the worker: base64 image in a JSON body. Simple to send from
  URLSession and to parse in the worker.
- Claude request: model `claude-opus-4-8`, multimodal image block plus a text
  prompt, with structured outputs (`output_config.format`) enforcing the four
  card fields.
- Storage: local-first. Cards and images persist on device; no backend yet.

## 9. Still open (next phases)

- Backend store: Cloudflare D1 when we add server-side persistence (decided), vs
  Supabase. Not built in v1.
- Where images live long-term: local only today; object storage (R2 or Supabase
  Storage) if backend cards need an image URL.
- Identity for backend rows in a no-auth app: device-generated anonymous id vs a
  single hardcoded demo user. Only matters once there is a backend.
- Live viewfinder: we capture without rendering frames. Add a live preview if the
  demo needs the user to aim.

## 10. References

- DAT API surface and conventions: see AGENTS.md.
- DAT docs: https://wearables.developer.meta.com/docs/develop/
- DAT package: https://github.com/facebook/meta-wearables-dat-ios
