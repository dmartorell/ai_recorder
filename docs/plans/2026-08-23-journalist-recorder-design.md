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
- Web: Next.js and TypeScript.
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

- **Library:** interviews, search, status, and new recording.
- **Preparation:** selected microphone, battery, free space, format, and language preference.
- **Recording:** elapsed time, input level, stop control, and `Highlight` marker.
- **Processing:** separate upload, transcription, and analysis progress.
- **Interview:** audio playback, transcript, speakers, summary, highlights, and export.

### Recording behavior

- Recording writes continuously to a local file.
- The default format is AAC-LC in M4A. WAV is optional.
- Preserve up to two channels when an external input provides them.
- Markers are stored independently with timestamps.
- Recording continues while the screen is locked.
- Stopping requires a deliberate action to prevent accidental termination.
- The app records audio interruptions and communicates them clearly.
- No upload starts until the file closes successfully and passes local verification.
- After recording, the journalist can add a title, context, and known names before processing.

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

### Local deletion rules

- Local audio is never deleted automatically.
- Without verified cloud audio, deletion requires a prominent permanent-loss warning and double confirmation.
- During upload, deletion is blocked until the user explicitly cancels the upload.
- With verified cloud audio, deletion uses a normal confirmation and states that web playback remains available.
- A completed transcript does not count as audio backup.
- If cloud state is unknown, deletion remains blocked unless the user chooses a forced deletion with double confirmation.
- Low-storage warnings may recommend action but must never trigger deletion.

## Web application

The web app is an editorial workspace. Recording in the browser is outside the MVP.

### Library

- List interviews with title, date, duration, language, and state.
- Search by title, transcript text, or named person.
- Filter by date, language, and state.
- Rename, archive, and delete interviews.

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
- Rename a speaker across the interview.
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
- Deleting an entire interview removes audio and structured records after explicit confirmation.
- Cloud retention is configurable per interview, but no local retention policy may delete the iPhone copy.

## Privacy and security

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

- Preserve the recording up to the last successfully written audio block after an app or process failure.
- Use multipart upload and resume from confirmed parts after connectivity loss.
- Make every backend phase idempotent.
- Use stable external job identifiers to prevent duplicate provider charges.
- Apply bounded retries and dead-letter handling.
- Show failed work as requiring attention rather than hiding it.
- Retry Speechmatics or Claude without uploading audio again.
- Never remove the local source because cloud processing failed.

## Prototype validation

Validate with a real 30-minute interview involving two speakers.

Acceptance criteria:

- Recording completes with the screen locked.
- Manual markers preserve accurate timestamps.
- The local file remains after completion and processing.
- Upload resumes after losing and restoring connectivity.
- Backup and processing states are independently correct.
- Speechmatics transcribes and separates speakers in Spanish and English.
- Renaming a speaker updates the full interview.
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
