# AGENTS.md

Instructions for AI agents (and humans) working in this repo.

## Project

A demo iOS app for language learners. The user looks at a real-world object
through Meta Ray-Ban (Gen 2) glasses, the app captures a photo from the glasses,
an AI layer generates a word or phrase in the target language (Chinese is the
main use case), and the app saves it as a reusable learning card with the image.

The glasses are an input device, not an app runtime. The app runs on iPhone and
pulls photos from the glasses over the Meta Wearables Device Access Toolkit (DAT).

This is a demo project that explores pairing iOS with DAT for smart glasses.

## How to work here

Read the relevant code before making changes.
Implement one small, complete change at a time.
Follow existing patterns and avoid unrelated refactors.
Run the relevant tests, build, lint, or type-check before finishing.
Do not commit, push, or deploy unless asked.

## Commits

Use conventional commit messages.

feat: add card deletion
fix: handle failed API request
refactor: simplify card storage
test: add card service tests
docs: update setup instructions

## Code 

Keep SwiftUI views focused on UI.
Keep networking, storage, and business logic outside views.
Keep TypeScript strict.
Validate external input and API responses.
Prefer simple code over unnecessary abstractions.

## Style 

Match the existing codebase style.
Use plain English. No em dashes. No filler or AI-slop phrasing.
Use clear names and concise comments.
Use plain English in docs and commit messages.

## Tech stack

- iOS app in Swift and SwiftUI. Edited in VS Code with Claude Code. Tested in
  Xcode. iOS 26+ deployment target. Prefer current APIs over deprecated ones
  kept around for older iOS versions.
- Meta Wearables DAT, version 0.8.0 (Swift Package Manager).
- Backend: Cloudflare Workers as the API endpoint.
- AI: Anthropic Claude API as the multimodal model. The Worker takes the image
  plus any instruction, calls Claude with the image, and returns the generated
  word, translation, and example phrase. 
  Open AI realtime API for a live session and intelligence layer. 

## DAT integration

For DAT API names, signatures, setup, and Info.plist requirements, use the
`mwdat-ios` skill (installed, v0.9.0). It is the authoritative source. Do not
invent or guess DAT method names, and do not copy the API surface into this
file where it can go stale. If unsure of a signature, check the skill or the
resolved Swift package.

Project-specific DAT notes that the skill will not tell you:
- Modules we use: `MWDATCore`, `MWDATCamera`, and `MWDATMockDevice` (mock).
- There is no one-shot photo call. Capture is a Stream capability: start a
  session, add a Stream, start it, then `capturePhoto` and read the result off
  `photoDataPublisher`. Plan capture flows around an active stream.
- Doc inconsistency to watch: one mock-testing snippet imports `MetaWearablesDAT`
  while the rest use `MWDATCore / MWDATCamera / MWDATMockDevice`. Confirm the real
  module name from the resolved package before relying on either.
