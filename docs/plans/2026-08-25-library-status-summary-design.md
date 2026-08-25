# Library Status Summary Design

**Status:** Approved  
**Date:** 2026-08-25

## Goal

Keep each Audio row in the iPhone library scannable while preserving truthful backup and processing information.

## Library row

A row contains only:

- Audio title
- Date
- Duration
- One synthesized status

Tapping anywhere on the row opens Audio detail. The status is informational and does not add a separate action.

## Status priority

When multiple conditions apply, show exactly one status, in this order:

1. Upload or processing failure
2. Uploading or upload paused
3. Processing
4. Cloud only
5. Backed up in cloud
6. Only on this iPhone

Capture and recovery states retain their existing higher-priority local-capture presentation where applicable.

## Detail

Audio detail remains the source for operational state. It presents local audio, cloud audio, and processing independently, together with backup, cancellation, playback, and deletion actions.

## Validation

- Unit tests cover status priority.
- UI tests verify a compact library row and navigation to Audio detail.
- Verify no row presents multiple status values.
