# Learn Vocabulary with Glass — v1 Spec

Status: draft for review. Last updated 2026-06-23.

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

In scope:
1. Boot the app and configure DAT. Show registration and connection state.
2. Registration plus camera permission flow through the Meta AI app.
3. Capture Mode: create and start a DeviceSession, add a Stream, show a live
   viewfinder, and reflect session state honestly.
4. Manual Capture button: capture a still off the stream, preview it, save the
   JPEG locally.
5. Card generation: the app sends the captured photo to the AI, which analyzes
   the image and returns a vocabulary card (word, pinyin, translation, example).
   The app fills the card from that result.
6. LearningCard model, persistence, and a history screen that lists saved cards
   with thumbnails.

Out of scope for v1 (do not build or pad toward):
- Voice command as the capture trigger (later phase).
- Realtime conversational Q&A about what the user sees (v2).
- Spaced repetition, analytics, sync, auth, App Store polish, cross-platform.

Leave a comment marker where a v2 hook would attach. Nothing more.

## 4. Decisions made

| Topic | Decision | Notes |
|-------|----------|-------|
| Target language | Chinese (Simplified) plus pinyin | Card holds hanzi, pinyin, English gloss, example sentence. Hardcoded for v1, configurable later. |
| Storage | Write to a backend now | Cards persist to a backend through the Worker, not local-only. App keeps a local cache for offline display. Backend store choice is open (see section 8). |
| Mock vs real glasses | Mock-first through M4 | Build and verify the full loop against MockDeviceKit in the simulator. Touch real glasses only at M5. |
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

- M0  Project skeleton. SwiftUI app, iOS 16+. Add the DAT package. Configure
  Info.plist. Call `Wearables.configure()`. Build clean on the simulator.
- M1  Mock device plus session lifecycle. Wire MockDeviceKit, drive
  powerOn/unfold/don, create and start a DeviceSession, render session state.
  Registration and permission UI lands here for the mock path.
- M2  Stream plus live preview plus capture. Add a Stream, show the viewfinder,
  wire the Capture button and photoDataPublisher, preview the still.
- M3  Local save, LearningCard, manual card. Save the JPEG, define the model,
  persist locally, type a card by hand, see it in the history list. Typing the
  card by hand proves the capture-to-card loop before any network call.
- M4  Worker plus Claude. Build the endpoint, send the image, get the generated
  card, persist to the backend, and replace the manual typing from M3 with the
  AI-generated result.
- M5  (optional) Real glasses. Swap to real hardware, run registration and
  permissions for real, test on device.

## 8. Open decisions

- Backend store: Cloudflare D1, or Supabase? Owner knows both. D1 keeps
  everything in the Worker; Supabase gives a hosted Postgres and dashboard.
- Image handling to the Worker: base64 in JSON, or multipart upload? Affects
  payload size and Worker parsing.
- Where images live long-term: keep only local, or also upload to object storage
  (R2 or Supabase Storage) so backend cards carry an image URL?
- Identity for backend rows in a no-auth v1: a device-generated anonymous id, or
  a single hardcoded demo user?
- Claude model id and exact multimodal request shape: confirm against the
  claude-api skill before writing the Worker.

## 9. References

- DAT API surface and conventions: see AGENTS.md.
- DAT docs: https://wearables.developer.meta.com/docs/develop/
- DAT package: https://github.com/facebook/meta-wearables-dat-ios
