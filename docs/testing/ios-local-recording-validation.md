# iOS local recording validation

Status: core recovery and Issue #7 interruption validation passed. Non-interrupting route validation remains pending.

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
| Spotify playback during Capture | Any resulting audio-session interruption ends Capture, persists the terminal interruption event, and preserves verified playable audio | Two consecutive Captures ended on interruption and preserved separate Audio items | Pass |
| Real system interruption | Capture ends without automatic or manual resumption; continuing creates a separate Audio and Original Audio | A Clock timer alarm ended Capture; repeating the scenario in a second Capture also ended it correctly | Pass |
| Non-interrupting route change | Capture continues with the same Original Audio identity and shows the resulting active input name | Pending physical-device run | Pending |

## Issue #7 device procedure

For each pending scenario, record the app commit, device and iOS version, event sequence, verified duration, final Capture event, Original Audio identifier before and after the event, and pass/fail result. Do not mark a scenario passed from simulator or synthetic-event tests.

## Recovery boundary

Capture uses ten-second fragmented M4A intervals. An abrupt termination may lose the incomplete current fragment. A capture terminated before the first completed fragment can have zero recoverable duration and is shown as `Needs recovery` rather than being presented as a verified recording.

No recorded audio, transcript, credentials, signed URLs, or personal interview content is retained in this document.
