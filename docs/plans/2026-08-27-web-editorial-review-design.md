# Web Editorial Review Slice Design

**Status:** Approved
**Date:** 2026-08-27

## Goal

Make preserved Automatic Transcripts usable in the MVP by adding an authenticated responsive web workspace for an owner's Audio library, private playback, and literal transcript review.

## Scope

- Create `apps/web` with Vite, React, TypeScript, React Router declarative mode, TanStack Query, and the Cloudflare Vite plugin.
- Authenticate with Supabase magic links. The web interface follows the browser's Spanish or English preference, independently from an Audio's transcription language.
- Add a cloud `audios` table as the root representation of Audio metadata: owner, local Audio identifier, title snapshot, capture start, duration, and transcription language.
- Link `audio_backups` to `audios`. The Worker idempotently upserts both when iPhone begins backup, using the metadata supplied by the iPhone.
- Preserve the title as a backup-time snapshot. Later iPhone metadata synchronization and web rename are separate work.
- Add owner-scoped RLS for cloud Audio metadata.
- Add an authenticated Worker playback endpoint. It verifies ownership of the Audio and returns a short-lived R2 URL only for a verified backup. It never returns provider credentials or persistent audio access.
- Provide `/login`, magic-link callback, `/audios`, and `/audios/:audioID` routes.
- Library rows show title, date, duration, language, and separate backup and transcription states. Search and filters are deferred.
- Audio detail provides custom play/pause, progress, duration, ten-second skips, and playback speed. It has no waveform or download control. It renews a failed expired playback URL once.
- Detail reads owner-authorized Automatic Speakers and Transcript Segments directly from Supabase. Selecting a segment seeks to its timestamp; playback identifies the active segment.
- Detail shows processing/failure state when an Automatic Transcript is not preserved. Web retry is deferred.

## Data and authorization

`audios` is distinct from `audio_backups`: it is the cloud catalog representation of the product's root Audio, while `audio_backups` retains upload state and the private Original Audio object. Existing Transcription Jobs and Automatic Transcripts remain associated through the backup.

The iPhone sends only the required metadata while beginning a backup. The local Original Audio remains the source of truth during Capture. Direct Supabase reads use the user's session and RLS. The Worker alone authorizes playback and signs private R2 access.

## Failure behavior

The SPA presents empty, loading, unavailable, and expired-session states without leaking object keys, signed URLs, provider identifiers, credentials, or transcript data in logs. A missing, foreign, or non-backed-up Audio does not receive a playback URL. A playback URL is retried once only when expiry is the likely cause; otherwise the player reports failure without discarding the detail state.

## Validation

- pgTAP coverage for cloud Audio ownership, RLS, and the Audio-to-backup relationship.
- Worker tests for unauthenticated access, cross-owner concealment, verified-backup-only playback, and short-lived signed URLs.
- React tests for protected routing, library and detail states, private-player URL renewal, and segment/player synchronization.
- A synthetic staging E2E validates magic-link access, owner-scoped metadata, private playback, and transcript review. No credentials, URLs, identifiers, source Audio, or transcript content are retained as evidence.

## Out of scope

Transcript or speaker editing, User Corrections, web rename, metadata synchronization after backup, search, filters, export, Generated Analysis, downloads, waveforms, Realtime, notifications, and joining Audio fragments.
