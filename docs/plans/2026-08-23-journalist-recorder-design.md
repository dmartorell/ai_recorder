# Journalist Recorder Design

**Status:** Approved  
**Date:** 2026-08-23  
**Working title:** AI Recorder

## Purpose

Build an independent iPhone application for journalists and interviewers. It records interviews reliably, uploads completed audio for cloud processing, separates and labels speakers, transcribes Spanish and English, generates summaries, and creates source-linked highlights. A responsive web application provides the primary editorial workspace.

The initial product is for one journalist. A dedicated hardware recorder may be reconsidered after validating demand, but it is outside this MVP.

## Product principles

- Recording must work without internet.
- The original audio must remain recoverable and unchanged.
- The app must communicate clearly where each copy exists.
- No local audio is ever deleted automatically.
- Generated content must remain traceable to literal transcript segments and audio timestamps.
- The product assists editorial work. It must not invent or silently rewrite quotations.
- The MVP prioritizes reliability and a focused workflow over collaboration or publishing features.
- Native capture is a core product capability. Importing from Voice Memos is not a substitute for the recording workflow.

## Scope

### Included

- Native iPhone recording on iOS 17 or later.
- Built-in and external audio input support through iOS.
- Spanish, English, and mixed-language transcription.
- Speaker diarization for two to four speakers.
- Manual speaker naming and correction.
- Manual markers created while recording.
- AI-generated summaries, topics, and suggested highlights.
- Private cloud audio backup and playback.
- Responsive web review and editing.
- Export to TXT, Markdown, DOCX, and PDF.
- Configurable cloud retention with explicit deletion controls.

### Excluded from MVP

- Dedicated recording hardware.
- Android.
- Browser-based recording.
- Live transcription.
- Automatic voice-identity recognition.
- Team collaboration, comments, roles, or newsroom administration.
- Direct publishing to third-party platforms.
- Audio waveform in the web player.
- Cross-interview semantic search, dossiers, or translation.
- Import from Voice Memos.
- Destructive audio editing, trimming, or segment replacement.
- Folders, favorites, Apple Watch support, or iCloud-based library synchronization.
- Full visual or feature parity with Apple's Voice Memos app.

## System architecture

```text
iPhone app
  1. Records and verifies a local file
  2. Stores manual marker timestamps
  3. Uploads the completed audio in resumable parts
        |
        v
Cloudflare R2 private object storage
        |
        v
Cloudflare Worker + Queue
        |
        v
Speechmatics Batch
  - transcription
  - timestamps
  - language handling
  - speaker diarization
        |
        v
Claude API
  - summaries
  - topics
  - suggested highlights
        |
        v
Supabase Postgres
        |
        +----> iPhone app
        +----> responsive web app
```

### Technology choices

- iPhone: Swift, SwiftUI, AVFoundation, SwiftData, background `URLSession`.
- Web: React, TypeScript, Vite, React Router, TanStack Query, and the Cloudflare Vite plugin.
- Identity and structured data: Supabase Auth and Postgres.
- Audio storage: Cloudflare R2.
- API and orchestration: Cloudflare Workers and Queues.
- Speech processing: Speechmatics Batch.
- Editorial analysis: Claude API.
- Monitoring: Sentry.

Use free infrastructure tiers during prototyping. Move Supabase and Cloudflare to production plans only when reliability and usage require it.

## Data integrity model

The system maintains distinct layers:

1. **Original audio:** immutable source recording.
2. **Automatic transcript:** literal provider result with timestamps, confidence, language, and speaker assignments.
3. **User corrections:** corrected text and speaker names without destroying the provider result.
4. **Generated analysis:** summaries, topics, and suggested highlights with source references.

A quote is literal only when it maps to transcript text and a precise audio interval. Paraphrases must be labeled as summaries. Regenerating analysis must not retranscribe or mutate source data.

## iPhone application

### Main screens

- **Library:** audio items, search, status, and new capture. The initial local-recording slice uses a reverse-chronological list with title, date, duration, and state; search and filters arrive later in the MVP.
- **Preparation:** selected microphone, battery, free space, format, language preference, and estimated recording time available for the active audio configuration.
- **Recording:** elapsed time, input level, stop control, and `Highlight` marker.
- **Processing:** separate upload, transcription, and analysis progress.
- **Audio:** local playback with play/pause, scrubbing, ten-second skips, marker navigation, metadata, backup and processing states, deletion controls, and a link to open the processed item on the web. It does not display a waveform.
- **Settings:** app language selection between Spanish and English.

The product concept `Audio` is shown as `Audio` in the Spanish interface and `Recording` in the English interface.

In the MVP, the native app does not display or edit transcripts, speakers, summaries, generated highlights, or exports. Those editorial workflows belong exclusively to the responsive web app. The iPhone app remains focused on reliable recording, local audio management, upload, and status visibility.

### Recording behavior

- Pressing the record control creates the Audio immediately before capture begins. Capture starts without a countdown or confirmation and uses haptic and visual feedback rather than an audible cue.
- Until the user assigns a custom title, the app dynamically displays `Audio - <localized date>, <localized start time>`; for example, `Audio - 24 ago 2026, 10:32 h` in Spanish. The fallback relocalizes when the app language changes, while user-authored titles never change. Duration is displayed separately.
- Recording writes continuously to a local file. The active screen shows a persistent red indicator, recorded-audio duration, input level, and active input name. If no input level is detectable, it warns without stopping automatically.
- The initial local-recording slice supports only AAC-LC in M4A, uses a fixed voice-appropriate quality configuration, and uses the audio route selected automatically by iOS. Quality controls, WAV, and manual input selection are deferred to a later MVP slice.
- Preserve up to two channels when an external input provides them.
- Markers are stored independently and persisted immediately with timestamps on the playable-audio timeline. A marker is created with one tap and confirmed using haptic feedback and a brief visual change. The native app does not attach text notes to markers during the MVP; annotation belongs to the web workflow. The primary elapsed-time counter also follows recorded audio duration and pauses during an interruption. Marker creation is unavailable during an interruption because no source audio exists for that interval. Recovery retains only markers whose timestamps map to recovered playable audio.
- While capture is active in the foreground, the app prevents automatic display sleep and uses a dark recording screen to reduce power consumption. It always respects explicit locking with the side button, never wakes the display after a manual lock, and restores the normal idle-timer behavior immediately after capture or when leaving the capture screen.
- Recording continues while the screen is locked or the user is in another app. Returning to the app immediately reflects the current capture state. The initial local-recording slice does not expose finalize or marker controls on the lock screen.
- The initial local-recording slice does not support manual pause and resume.
- The recording screen uses a `Finalize` action. Selecting it opens a confirmation dialog while recording continues; confirming stops capture, closes the existing file, and verifies it. Saving is not a separate action.
- The app records audio interruptions and communicates them clearly. It resumes automatically when iOS indicates that resumption is safe and preserves the interval without audio as an interruption event.
- If the active microphone becomes unavailable, the app continues with an available iOS-routed input when possible, records the route change, and warns the user without discarding prior audio.
- The physical audio file uses a stable private identifier. Editing user-facing metadata never renames it.
- If capture fails before any audio is written, the app reports the error and removes only the empty Audio record. It never removes a file containing captured audio.
- No upload starts until the file closes successfully and passes local verification. If finalization or verification fails while a file exists, the app preserves it and exposes the Audio as `Needs recovery`.
- Finalizing never blocks on metadata entry. The Audio is saved immediately with its automatic title; the journalist can optionally edit its title and general context afterward. Context belongs to the Audio as a whole, not to an individual marker. Known names are collected in a later cloud-processing slice.
- Capture has no artificial duration limit. Before starting, the app derives and displays a conservative, approximate recording-time estimate from available iPhone storage, a safety reserve, and the active audio configuration. It warns or blocks when storage is insufficient, but it never deletes local audio automatically.
- During capture, the app warns as storage approaches a critical level. At the safety threshold it finalizes automatically to preserve playable audio and explains why capture ended.
- Low battery produces clear warnings but never causes the app to finalize automatically.

### Status model

Display file location and processing separately:

```text
Local audio       Available
Cloud audio       Backed up
Transcription     Complete
Summary           Processing
```

Library labels include:

- Only on this iPhone
- Uploading
- Backed up in cloud
- Processing
- Processed
- Upload failed
- Processing failed

The app considers cloud audio backed up only after the backend verifies the complete R2 object.

Local recording, library access, and playback do not require authentication. Authentication is introduced when cloud backup is implemented.

### Local deletion rules

- Local audio is never deleted automatically.
- Without verified cloud audio, deletion requires a prominent permanent-loss warning and double confirmation. The first step explains that no cloud copy exists; the second names the Audio and requires an explicit `Delete permanently` action.
- During upload, deletion is blocked until the user explicitly cancels the upload.
- With verified cloud audio, deletion uses a normal confirmation and states that web playback remains available.
- A completed transcript does not count as audio backup.
- If cloud state is unknown, deletion remains blocked unless the user chooses a forced deletion with double confirmation.
- Low-storage warnings may recommend action but must never trigger deletion.

## Web application

The web app is an authenticated React single-page application and editorial workspace. Recording in the browser is outside the MVP. It does not require SEO, server-side rendering, React Server Components, or Server Actions. Vite and the Cloudflare Vite plugin provide a direct deployment path to Cloudflare Workers without a framework adapter.

### Library

- List audio items with title, date, duration, language, and state.
- Search by title, transcript text, or named person.
- Filter by date, language, and state.
- Rename, archive, and delete audio items.

### Player

- Play and pause.
- Current position and total duration.
- Skip backward or forward by five or ten seconds.
- Playback speed.
- Manual and AI highlights displayed on the timeline.
- Active transcript segment synchronization.
- Selecting a transcript segment seeks to its timestamp.
- No waveform.

The browser requests playback through an authenticated backend. After ownership verification, it receives a short-lived signed R2 URL. The R2 bucket is never public.

### Transcript editing

- Visually separate speaker turns.
- Rename a speaker across the full Audio.
- Correct speaker attribution for a segment.
- Correct text, punctuation, and names.
- Preserve the automatic original.
- Surface low-confidence words or segments.
- Search and replace.

### Summary and highlights

- Brief summary.
- Detailed summary.
- Main topics.
- Mentioned chronology.
- People, organizations, and places.
- Manual markers from the iPhone.
- AI-suggested highlights.
- Selection of transcript text as a highlight.
- Notes on highlights.
- Verification state after listening to source audio.
- Regeneration without retranscription.

Each generated point links to supporting transcript segments. Literal quotes include speaker and timestamp.

### Export

Export the full transcript, summary, or highlights as TXT, Markdown, DOCX, or PDF. Timestamps and speaker names are optional export settings.

### Cloud deletion

- Deleting cloud audio does not delete the local iPhone copy.
- After cloud audio deletion, transcript and analysis may remain, but web playback becomes unavailable.
- Deleting an entire Audio removes its original audio and structured records after explicit confirmation.
- Cloud retention is configurable per Audio, but no local retention policy may delete the iPhone copy.

## Privacy and security

- If microphone permission is unavailable, do not create an Audio. Explain why permission is required and provide a control that opens the app's system Settings page.
- Use iOS file protection for local recordings.
- Encrypt traffic with HTTPS.
- Keep R2 objects private.
- Authorize every signed playback or download URL.
- Use Supabase row-level security so users can access only their records.
- Do not opt interview data into provider model training.
- Request deletion of Speechmatics batch data after ingesting the result.
- Send transcript text, not audio, to Claude.
- Never store API secrets in either client application.
- Never log audio, transcript content, signed URLs, or user credentials.

Cloud processing prevents true end-to-end encryption because processing providers require plaintext during inference. Product copy must not claim end-to-end encryption.

## Failure handling

- Preserve the recording up to the last successfully written audio block after an app or process failure. On relaunch, expose it as one recovered Audio with continuous playback even if recovery uses multiple internal segments, identify that capture ended unexpectedly, and require the recovered partial audio to be playable.
- Use multipart upload and resume from confirmed parts after connectivity loss.
- Make every backend phase idempotent.
- Use stable external job identifiers to prevent duplicate provider charges.
- Apply bounded retries and dead-letter handling.
- Show failed work as requiring attention rather than hiding it.
- Retry Speechmatics or Claude without uploading audio again.
- Never remove the local source because cloud processing failed.

## Prototype validation

Use a 30-minute recording as the quick development check. Validate the reliability milestone with a real two-hour interview involving two speakers.

Acceptance criteria:

- A two-hour recording completes in airplane mode with the screen locked; the 30-minute variant remains the routine development check.
- A separate recording survives a real audio-session interruption, records the interruption, and communicates it clearly.
- After unexpected app termination during recording, relaunch recovers the partial audio through the last successfully written block.
- Manual markers preserve accurate timestamps.
- The local file remains after completion and processing.
- Upload resumes after losing and restoring connectivity.
- Backup and processing states are independently correct.
- Speechmatics transcribes and separates speakers in Spanish and English.
- Renaming a speaker updates the full Audio.
- Claude output links to real transcript segments.
- Literal quotes match transcript and audio.
- The web player seeks using transcript timestamps.
- Deletion warnings match verified backup state.
- Backend failures never cause local audio loss.

Additional test scenarios:

- Wi-Fi to cellular transition.
- Audio interruption and route change.
- Low storage.
- Two, three, and four speakers.
- Spanish, English, and mixed-language speech.
- Simulated Speechmatics and Claude failures.
- Independent deletion of local and cloud copies.

## Prototype cost target

With existing Apple and Supabase accounts:

- Supabase Free: $0.
- Cloudflare Workers, Queues, and R2 Free: $0 within quotas.
- Speechmatics: initial usage covered by trial credit, then model-dependent per-hour billing.
- Claude API: estimated cents per interview hour.
- Sentry Developer: $0.

The prototype should require no fixed monthly infrastructure cost. Production migration and pricing are separate decisions after validation.
