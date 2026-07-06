# AGENTS.md

Instructions for AI agents (and humans) working in this repo.

## What this project is

A demo iOS app for language learners. The user looks at a real-world object
through Meta Ray-Ban (Gen 2) glasses, the app captures a photo from the glasses,
an AI layer generates a word or phrase in the target language (Chinese is the
main use case), and the app saves it as a reusable learning card with the image.

The glasses are an input device, not an app runtime. The app runs on iPhone and
pulls photos from the glasses over the Meta Wearables Device Access Toolkit (DAT).

This is a demo project that explores pairing iOS with DAT for smart glasses.

## How to work here

- Explain before building. For each meaningful piece, say what we are doing,
  which DAT or iOS API it uses, why that one, and how it fits the architecture.
- Do not write the whole app at once. One small milestone at a time.
- Default to giving a skeleton plus instructions and letting the owner write the
  code. Write it for them only if they get stuck or ask.
- Always say which file, where it lives, and what it does before any code is
  written.
- Do not scaffold many files without walking through the plan and getting an OK.
- Stop and check in at the end of each milestone.

## Writing style for anything drafted

Plain English. No em dashes. No filler or AI-slop phrasing. This applies to
code comments, docs, and commit messages.

## Tech stack

- iOS app in Swift and SwiftUI. Edited in VS Code with Claude Code. Tested in
  Xcode. iOS 26+ deployment target. Prefer current APIs over deprecated ones
  kept around for older iOS versions.
- Meta Wearables DAT, version 0.8.0 (Swift Package Manager).
- Backend: Cloudflare Workers as the API endpoint.
- AI: Anthropic Claude API as the multimodal model. The Worker takes the image
  plus any instruction, calls Claude with the image, and returns the generated
  word, translation, and example phrase.

## DAT integration

For DAT API names, signatures, setup, and Info.plist requirements, use the
`mwdat-ios` skill (installed, v0.7.0). It is the authoritative source. Do not
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

## Scope

`spec.md` is the source of truth for scope, architecture, data model,
milestones, and open decisions. Read it before building, and keep work inside
the current milestone. Do not build or pad toward out-of-scope items; where a
later-phase hook is unavoidable, leave a comment marker and nothing more.
