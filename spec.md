# VocabGlass Spec

## Vision

A language learner wears Meta Ray-Ban glasses, starts a session from the
iPhone app, and captures objects by voice: look at something and say
"Capture this." AI turns the image into a vocabulary card (word,
pronunciation, meaning, example) and saves it with the photo. The deck is
reviewed later as flashcards. The glasses are an input device; the app
runs on iPhone.

## Scope

In scope:
- Voice sessions: conversation and capture through the glasses, session
  start from the app, end by voice, button, or the 10 minute timer.
  Sessions keep running while the phone is locked.
- Target languages: French, Spanish, Chinese, Japanese (Chinese is the
  current hardcoded default until language selection lands).
- Learning: browse, edit, delete entries; flashcard review (image first,
  reveal the answer).

Out of scope: starting a session from the glasses, folders and spaced
repetition, auth, sync, App Store distribution.

## Architecture

```
Meta Ray-Ban glasses
  camera (DAT SDK)           mic + speakers (Bluetooth HFP, not DAT)
      |                           |
      v                           v
iOS app  --  session orchestrator
  GlassesClient (DAT) · LiveAudioEngine (PCM 16k up / 24k down)
  GeminiLiveClient (WebSocket) · SessionController (state, tool calls)
  CardStore (local JSON + JPEG)
      |  HTTPS                    |  WSS, ephemeral token
      v                           v
Cloudflare Worker             Gemini Live API
  POST /token  POST /generate   voice + tool calls
      |
      v
  Claude (image -> card JSON)
```

Constraints the code depends on (do not "improve" these away):
- DAT has no microphone API; voice runs over the OS Bluetooth HFP route.
- Keep the camera stream at medium/24: lower settings starve the HFP
  link and the mic goes silent.
- The system prompt and tools are baked into the ephemeral token by the
  worker; client-side setup is ignored on the constrained endpoint.
- Every Gemini tool call must be answered (unanswered calls lock the
  model). One capture at a time; extra requests are answered SILENT.
- Playback flushes on the interrupted signal and is capped at 6 seconds
  so conversation lag cannot accumulate.

## Tasks

1. Language selection. Picker for the four languages; worker takes a
   language parameter; rename pinyin to pronunciation with a decode-time
   migration.
2. Demo polish and cleanup. Refresh docs, remove the DesignMocks
   folder, rehearse the demo.

Done: edit and delete entries (with delete confirmation); tabbed UI in
the Quiet style (Capture and Deck tabs, manual capture kept as a
debug-only Dev tab); flashcard review (image first, Show answer reveals
word, pronunciation, meaning, example); unit and UI test targets.
