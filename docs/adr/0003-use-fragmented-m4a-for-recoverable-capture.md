# Use fragmented M4A for recoverable Capture

Capture writes AAC-LC Original Audio with `AVAssetWriter` using ten-second initial and subsequent movie fragments. We chose fragmentation over a file that becomes playable only after finalization or a set of separately exposed recordings because normal completion produces one standard M4A while unexpected process termination preserves playback through the last completed fragment.

## Physical-device evidence

Validated on 2026-08-23 with an iPhone 12 running iOS 26.3.1 (a):

| Scenario | Expected | Actual | Result |
| --- | --- | --- | --- |
| Normal finalization | Positive-duration playable AAC-LC M4A with one or two channels as supplied by the input | Approximately 49 seconds, mono, audible through local playback | Pass |
| Foreground `SIGKILL` after more than 25 seconds | At least 20 seconds recoverable through the last completed ten-second fragment | 39.96 seconds, mono, audible through local playback | Pass |
| Locked-screen `SIGKILL` after more than 25 seconds | Capture continues while locked with at least 20 seconds recoverable through the last completed fragment | 49.96 seconds, mono, AAC decoded without errors and audible through local playback after relaunch | Pass |

Recovery may lose the current incomplete fragment. The app must not claim recovery beyond the verified playable duration.
