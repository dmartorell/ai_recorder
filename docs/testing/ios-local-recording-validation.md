# iOS local recording validation

Status: manual validation passed on the paired physical iPhone.

## Environment

- Device: iPhone 12
- iOS: 26.3.1
- App target: iOS 17+
- Network: not required for local capture
- Audio source: iOS-selected microphone

## Scenarios

| Scenario | Expected result | Actual result | Status |
| --- | --- | --- | --- |
| Normal local capture | Finalized AAC-LC M4A remains in the library and plays locally | Audio finalized, remained available and played | Pass |
| Screen locked during capture | Capture continues and remains playable after unlocking | Capture continued and was finalized successfully | Pass |
| Abrupt app termination after a completed fragment | Relaunch exposes one recovered Audio playable through the last completed fragment | Audio appeared as `Recovered` and played through the recovered duration | Pass |
| Abrupt termination before the first completed fragment | No unverifiable audio is presented as recovered | Audio appeared as `Needs recovery` with zero recoverable duration | Pass |
| Delete while playing | Local file and library metadata are removed after explicit confirmation | Audio disappeared and a new capture could start immediately | Pass |
| Relaunch after playback | Playback can start without recording a new Audio first | Existing Audio played after relaunch | Pass |

## Recovery boundary

Capture uses ten-second fragmented M4A intervals. An abrupt termination may lose the incomplete current fragment. A capture terminated before the first completed fragment can have zero recoverable duration and is shown as `Needs recovery` rather than being presented as a verified recording.

No recorded audio, transcript, credentials, signed URLs, or personal interview content is retained in this document.
