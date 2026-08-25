# Private cloud backup validation

This evidence validates Issue #37 against isolated staging services. Use synthetic bytes only. Do not record or retain audio, transcript content, credentials, emails, bearer tokens, backup IDs, object keys, or signed URLs.

## Transcription queue provisioning

Issue #45 adds the staging producer binding `TRANSCRIPTION_JOBS`. Before deploying its Worker configuration, create the named queue in the authenticated Cloudflare staging account:

```sh
cd apps/worker
npx wrangler queues create ai-recorder-transcription-jobs-staging
```

This ticket does not configure a Queue consumer and does not require a Speechmatics account or credential. The queue carries only the opaque Transcription Job UUID. Issue #44 will add the consumer and provider integration.

## Automated staging integration

`apps/worker/test/staging-backup.integration.test.ts` exercises the deployed Worker, Supabase, and private R2 bucket with two pre-provisioned staging users. It verifies:

- missing JWT returns `401`, and another owner receives `404` for the backup;
- Supabase RLS returns the backup only to its owner;
- identical begin requests reuse one backup and conflicting source metadata returns `409`;
- a multipart upload is initiated, its one synthetic 8 MiB part is confirmed by R2, and completion reaches `backed_up` only after size and SHA-256 verification;
- the signed part URL declares the required 900-second lifetime and rejects a different HTTP method or part number.

Before running, export these ephemeral values from a secure shell. They must target an isolated staging project and two different staging users:

```sh
export BACKUP_TEST_WORKER_URL='https://…'
export BACKUP_TEST_SUPABASE_URL='https://….supabase.co'
export BACKUP_TEST_SUPABASE_PUBLISHABLE_KEY='…'
export BACKUP_TEST_OWNER_TOKEN='…'
export BACKUP_TEST_OTHER_OWNER_TOKEN='…'
cd apps/worker && npm run test:integration
```

The suite skips when any value is absent, so a skipped result is not validation. The test does not print URLs, tokens, IDs, or object keys. It creates one backed-up synthetic object. An operator must explicitly delete that isolated test object after recording the pass result. No production or journalist Original Audio may be used.

## Signed URL expiry and scope

The integration suite automatically confirms method and part-number scope. During the same run, retain the signed URL only in memory. After 900 seconds, retry the `PUT` with the same synthetic part. It must be rejected. Record only pass/fail and HTTP status. Never place the URL in this repository or an issue comment.

## Physical iPhone validation

Use the physical iPhone with the staging configuration and a synthetic spoken test. Record the app commit, device, iOS version, and only the expected/actual outcomes below.

| Scenario | Expected result | Actual result | Status |
| --- | --- | --- | --- |
| Offline capture, then reconnect | Capture completes offline. Backup starts only after connectivity returns. | Expected behavior observed | Pass |
| Backup during interruption | The verified local Original Audio remains playable after interruption and relaunch. | Expected behavior observed | Pass |
| Remote integrity | The UI becomes `Backed up in cloud` only after the Worker completes R2 size and SHA-256 verification. | Expected behavior observed | Pass |
| Local deletion protection | Before remote verification, deletion has the permanent-loss warning. After verified backup, deletion states web playback remains available. | Expected behavior observed | Pass |

Do not mark these scenarios passed from simulator, mocks, or Worker tests. Delete any synthetic local Audio and isolated test cloud object only through explicit user actions after documenting the result.

## Recorded evidence

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-25 | Remote `audio_backups_rls.test.sql` executed through `supabase db query --linked --file` | Pass. The final pgTAP assertion reported `ok 14`; the transaction rolls back its fixtures. |
| 2026-08-25 | `supabase test db --linked` | Blocked. This CLI path requires Docker Desktop in the current environment. The remote query above is the executed substitute. |
| 2026-08-25 | `supabase test db --linked supabase/tests/audio_backups_rls.test.sql` for Issue #45 | Blocked. Docker and Podman are unavailable, so the CLI could not run pgTAP against the linked project. The new migration was not applied to staging. |
| 2026-08-25 | Staging Worker integration | Pass, user-confirmed. |
| 2026-08-25 | Physical iPhone flow | Pass, user-confirmed. |
