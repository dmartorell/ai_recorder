# Library Row Metadata Design

**Status:** Approved  
**Date:** 2026-08-25

## Goal

Make the Audio library easier to scan by removing the product noun from automatic titles and imposing a consistent metadata order in each row.

## Automatic title

Until the journalist sets a custom title, display only the localized start date and time:

- Spanish: `24 ago 2026, 10:32`
- English: `Aug 24, 2026, 10:32 AM`

A custom title remains unchanged. The automatic title is never persisted and relocalizes when the app language changes.

## Library row

- First line: title.
- Second line, leading: duration followed by a localized short date.
  - Spanish short date: `12/07/26`
  - English short date: `07/12/26`
- Second line, trailing: the one synthesized library status.

The whole row continues to open Audio detail. Detail retains the full date and time.
