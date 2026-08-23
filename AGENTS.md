# Agent Instructions

## Project

This repository contains a new, independent journalist interview recorder.

Read these documents before planning or implementing product work:

- `docs/plans/2026-08-23-journalist-recorder-design.md`
- The active implementation plan in `docs/` when one exists

Do not expand the MVP beyond the approved design.

## Product invariants

- Recording is offline-first. Network availability must never be required to record.
- The local audio file is the source of truth while recording.
- Local audio is never deleted automatically. Only an explicit user action may delete it.
- Show local backup, cloud backup, and processing as separate states.
- A transcript does not count as an audio backup.
- If cloud backup cannot be verified, warn prominently before local deletion.
- Keep original audio, literal transcript, user corrections, and generated analysis logically separate.
- AI-generated quotes must point to source timestamps. Never present a paraphrase as a literal quote.
- Support Spanish and English transcription, including mixed-language interviews.
- The MVP is single-user. Do not add collaboration, publishing, history across revisions, or hardware recorder support.
- The web app reviews and edits interviews. It does not record audio in the MVP.
- Do not add an audio waveform to the web player.

## Intended architecture

- iOS 17+ native app using Swift, SwiftUI, AVFoundation, SwiftData, and background `URLSession` uploads.
- React and TypeScript responsive SPA using Vite, React Router, TanStack Query, and the Cloudflare Vite plugin.
- Supabase Auth and Postgres for identity and structured data.
- Cloudflare R2 for private audio objects.
- Cloudflare Workers and Queues for orchestration.
- Speechmatics Batch for transcription, timestamps, language handling, and speaker diarization.
- Claude API for summaries and suggested highlights. Claude receives transcript text, not audio.
- Sentry for app and backend error monitoring.

Treat this architecture as a design target. Follow the implementation plan for sequencing and exact dependencies.

## Project skills

Load the relevant skill before working in its domain:

- Swift, SwiftUI, or iOS: `.agents/skills/swiftui-expert-skill/SKILL.md`
- React performance: `.agents/skills/vercel-react-best-practices/SKILL.md`
- React component APIs: `.agents/skills/vercel-composition-patterns/SKILL.md`
- Web accessibility and UX review: `.agents/skills/web-design-guidelines/SKILL.md`
- React Router SPA routing: `.agents/skills/react-router-declarative-mode/SKILL.md`
- Supabase: `.agents/skills/supabase/SKILL.md`
- Postgres schema, SQL, indexes, or RLS: `.agents/skills/supabase-postgres-best-practices/SKILL.md`
- Cloudflare Workers, R2, or Queues: `.agents/skills/cloudflare/SKILL.md`
- Wrangler configuration or commands: `.agents/skills/wrangler/SKILL.md`

For SwiftUI tasks, follow the skill's instruction to read `references/latest-apis.md` first, then read the references relevant to the task. Resolve relative paths from each skill directory. The Vercel React skill also contains Next.js guidance; ignore Next.js-specific rules because this project uses a Vite SPA.

## Engineering rules

- Prefer small files with one responsibility and explicit interfaces between recording, upload, processing, and presentation.
- Design owned and injected state before writing SwiftUI views. For iOS 17+, prefer `@Observable` models with `@State` ownership and `@Bindable` where bindings are required.
- Use native SwiftUI APIs. Use UIKit bridging only where AVFoundation or platform integration requires it.
- Use stable identity in SwiftUI collections. Use `Button` for actions and include accessibility labels and hints.
- Keep views free of networking, persistence, and audio-session orchestration.
- Preserve server job idempotency. Retries must not create duplicate transcription charges.
- Use migrations for database changes. Enable and test row-level security for all user data.
- Keep R2 private. Audio access requires short-lived signed URLs after authorization.
- Never commit credentials, API keys, signed URLs, recorded interviews, transcripts, or personal data.
- Add tests before or with implementation. Run the narrowest relevant tests, then the full affected suite.
- Do not add dependencies, change cloud schemas, or create commits without explicit user approval.
- Update documentation when commands, architecture, or invariants change.

## Git

- Main branch: `main`.
- Use short-lived feature branches for implementation.
- Keep commits focused and use `type: description` messages.
- Never add agent attribution or co-author lines.

## Pi

Pi automatically loads this `AGENTS.md`. No custom system prompt is needed.

From the repository root:

```bash
pix
```

Use `/login` for provider authentication and `/model` to select the OpenAI model. Run `/reload` after changing agent files. Project prompt templates are under `.pi/prompts/` and load only after the project is trusted.
