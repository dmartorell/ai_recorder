# AI Recorder

An offline-first iPhone interview recorder for journalists. Completed recordings are transcribed in the cloud with speaker diarization, then enriched with source-linked summaries and highlights. A responsive web app provides the editorial workspace.

## Status

Design approved. The native iPhone project currently contains the physical-device proof for recoverable local Capture. Product implementation proceeds through the tickets linked from the approved specification.

Read:

- [`AGENTS.md`](AGENTS.md) for agent and engineering rules.
- [`docs/plans/2026-08-23-journalist-recorder-design.md`](docs/plans/2026-08-23-journalist-recorder-design.md) for the product design.

## Planned stack

- iOS 17+: Swift, SwiftUI, AVFoundation, SwiftData
- Web: React, TypeScript, Vite, React Router, TanStack Query
- Data: Supabase Auth and Postgres
- Audio: Cloudflare R2
- Orchestration: Cloudflare Workers and Queues
- Transcription: Speechmatics Batch
- Analysis: Claude API
- Monitoring: Sentry

## iPhone proof project

Build and test the current iOS project with:

```bash
xcodebuild test \
  -project apps/ios/AIRecorder.xcodeproj \
  -scheme AIRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=26.2'
```

Physical-device Capture validation requires automatic signing with the configured personal development team.

## Using Pi

Start Pi from this repository so it loads `AGENTS.md`:

```bash
cd /Volumes/T7_SAMSUNG/ai_recorder
pix
```

Inside Pi, use `/login` to authenticate and `/model` to select the OpenAI model. Run `/reload` after changing agent instructions or prompt templates.

Do not add secrets to the repository. Runtime configuration examples will be added with the corresponding implementation tasks.
