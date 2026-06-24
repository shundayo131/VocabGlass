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

In scope:
1. Register and connect to the glasses through the Meta AI app, including the
   camera permission flow.
2. On-demand camera: open a DeviceSession and Stream, capture a still, save the
   JPEG locally.
3. Card generation: send the photo to the worker, get back a vocabulary card
   (word, pinyin, translation, example), and show it.
4. Save cards with their photo into a local deck, browsable in a history screen.

Out of scope:
- Voice command as the capture trigger (next phase).
- Realtime conversational Q&A about what the user sees.
- Spaced repetition, analytics, sync, auth, App Store polish, cross-platform.

## 4. Decisions made

| Topic | Decision | Notes |
|-------|----------|-------|
| Target language | Chinese (Simplified) plus pinyin | Card holds hanzi, pinyin, English gloss, example sentence. Hardcoded for v1, configurable later. |
| Storage | Local-first, backend later | Shipped local-only first: cards and images persist on device (cards.json plus JPEG files in Documents). Backend persistence through the Worker is deferred; when added, the store will be Cloudflare D1. |
| Mock vs real glasses | Mock-first | Build and verify the full loop against MockDeviceKit in the simulator. Touch real glasses last. |
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

## 6. Data model

`LearningCard` (the worker's response): `word` (hanzi), `pinyin`,
`translation` (English), `example` (sentence in Chinese).

`SavedCard` (stored locally): the four card fields plus `id`, `imageFileName`,
and `createdAt`.

Worker `POST /generate` response shape:
```json
{ "word": "...", "pinyin": "...", "translation": "...", "example": "..." }
```
The worker returns exactly these four fields, enforced by Claude structured
outputs.

## 7. Decisions resolved during v1

- Image handling to the worker: base64 image in a JSON body. Simple to send from
  URLSession and to parse in the worker.
- Claude request: model `claude-sonnet-4-6`, multimodal image block plus a text
  prompt, with structured outputs (`output_config.format`) enforcing the four
  card fields.
- Storage: local-first. Cards and images persist on device; no backend yet.

## 8. Still open (next phases)

- Voice-driven capture: trigger capture (and the card flow) by voice instead of
  the on-screen button. Either a voice command on the glasses as the capture
  trigger, or streaming audio so a spoken instruction drives the photo-to-card
  process end to end.
- Backend store: Cloudflare D1 when we add server-side persistence (decided), vs
  Supabase. Not built in v1.
- Where images live long-term: local only today; object storage (R2 or Supabase
  Storage) if backend cards need an image URL.
- Identity for backend rows in a no-auth app: device-generated anonymous id vs a
  single hardcoded demo user. Only matters once there is a backend.
- Live viewfinder: we capture without rendering frames. Add a live preview if the
  demo needs the user to aim.

## 9. References

- DAT API surface and conventions: see AGENTS.md.
- DAT docs: https://wearables.developer.meta.com/docs/develop/
- DAT package: https://github.com/facebook/meta-wearables-dat-ios
