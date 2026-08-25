# Library Location Icons Design

**Status:** Approved  
**Date:** 2026-08-25

## Goal

Make stable audio-location states in the iPhone library faster to scan without losing their meaning for VoiceOver users.

## Scope

In the trailing library-row status position, replace these stable text statuses with SF Symbols:

| Audio location | Visual status | VoiceOver label |
| --- | --- | --- |
| Local original only | `iphone` | Only on this iPhone |
| Verified cloud original only | `icloud` | Cloud only |
| Local and verified cloud originals | `iphone` followed by `icloud` | Backed up in cloud |

The two symbols in the final state remain distinct symbols, not a combined custom asset.

All operational, transient, and failure statuses remain text: capture/recovery states, uploading, upload paused, and upload failed. Audio detail continues to show independent text labels for local audio, cloud audio, and processing.

## Presentation and accessibility

Icons inherit the existing caption size and secondary foreground style of the status position. They have no separate tap target. The library row remains one accessible button; its combined accessibility label includes the existing localized meaning of the location state rather than SF Symbol names.

## Alternatives considered

- Keep all text: clearest at first glance, but repeats information and makes rows less scannable.
- Use one combined icon for local plus cloud: more compact, but obscures that both independent copies exist.
- Use two separate SF Symbols: selected. It directly represents the two copies, requires no new asset, and keeps the status compact.

## Validation

- Unit tests lock the status-to-symbol mapping and ensure non-location statuses have no icon mapping.
- UI tests verify the cloud-only library row exposes its localized textual meaning through the row accessibility label, while the detail still exposes its independent textual states.
- Run the full iOS test suite and inspect the three location states with VoiceOver enabled.
