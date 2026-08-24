# iOS local recording validation

Status: core recovery and Issue #7 interruption validation passed. External-input validation for Issue #25 remains pending on physical hardware.

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
| Bluetooth HFP microphone | The routed Bluetooth microphone is selected, captured, and its route name matches the capture device | Pending Bluetooth headset run | Pending |
| Wired or USB/Lightning microphone | The routed external microphone is selected, captured, and its route name matches the capture device | Pending external-microphone run | Pending |

## Physical route validation procedure

For each pending scenario, record the app commit, device and iOS version, `AVAudioSession` input port name, port type and UID, selected `AVCaptureDevice` name and unique ID, event sequence, verified duration, final Capture event, Original Audio identifier before and after the event, and pass/fail result. Confirm the recorded signal comes from the attached external microphone. Do not retain audio or personal data, and do not mark a scenario passed from simulator or synthetic-event tests.

## Recovery boundary

Capture uses ten-second fragmented M4A intervals. An abrupt termination may lose the incomplete current fragment. A capture terminated before the first completed fragment can have zero recoverable duration and is shown as `Needs recovery` rather than being presented as a verified recording.

No recorded audio, transcript, credentials, signed URLs, or personal interview content is retained in this document.
