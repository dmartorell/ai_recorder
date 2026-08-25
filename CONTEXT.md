# Journalist Audio Recorder

The product captures audio reliably on iPhone and provides a web workspace for editorial review.

## Language

**Audio**:
The persistent item visible in the library. It represents captured material that may be an interview or a personal audio note.
_Avoid_: Interview, when referring to every library item

**Capture**:
The time-bounded activity of recording sound to produce an Audio.
_Avoid_: Audio, Original Audio

**Original Audio**:
The immutable local file produced by a Capture and treated as the source of truth for an Audio.
_Avoid_: Audio, transcript, backup

**Automatic Transcript**:
The immutable literal result produced from an Original Audio by the transcription provider. It retains timestamps, detected language, and automatic speaker assignments.
_Avoid_: corrected transcript, summary, quote

**Transcript Segment**:
A timestamped, speaker-attributed unit projected from the Automatic Transcript for review and source linking.
_Avoid_: Audio, marker, highlight

**User Correction**:
A journalist-authored change to transcript text or speaker attribution that remains separate from the Automatic Transcript.
_Avoid_: transcription result, generated analysis

**Transcription Job**:
The idempotent request to produce an Automatic Transcript from a backed-up Original Audio. Its completion means the Automatic Transcript and Transcript Segments are preserved by the product.
_Avoid_: Capture, upload, backup

**Speaker**:
An identity scoped to one Audio. It groups automatic speaker assignments and may be renamed or used to reassign an individual Transcript Segment.
_Avoid_: globally recognized person, voice identity

**Generated Analysis**:
A regenerable, non-literal interpretation of the current editorial transcript. It never changes the Automatic Transcript or User Corrections.
_Avoid_: transcript, quote

**Source Reference**:
A link from editorial or generated content to a precise range of Transcript Segments or words in its source Audio.
_Avoid_: unsupported citation, paraphrase
