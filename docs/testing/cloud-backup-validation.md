# Private cloud backup validation

This evidence validates Issue #37 against isolated staging services. Use synthetic bytes only. Do not record or retain audio, transcript content, credentials, emails, bearer tokens, backup IDs, object keys, or signed URLs.

## Transcription queue provisioning

Issue #45 adds the staging producer binding `TRANSCRIPTION_JOBS`. Before deploying its Worker configuration, create the named queue in the authenticated Cloudflare staging account:

```sh
cd apps/worker
npx wrangler queues create ai-recorder-transcription-jobs-staging
```

The queue carries only the opaque Transcription Job UUID.

Issue #46 adds the consumer. Before deploying that Worker configuration, an operator must explicitly set the staging Worker secret interactively. Do not place its value in a shell command, file, or this repository:

```sh
cd apps/worker
npx wrangler secret put SPEECHMATICS_API_KEY --env staging
```

The consumer signs each private R2 read URL for 900 seconds, reconciles an unresolved provider request by stable tracking reference before another provider submission, and sends Speechmatics only that scoped URL. Do not deploy, create the queue, or set the secret without explicit approval.

## Automatic Transcript callback setup

Issue #47 requires two operator-only staging Worker secrets. Set each value interactively. Do not put either value in a command, shell history, file, test fixture, or issue comment:

```sh
cd apps/worker
npx wrangler secret put TRANSCRIPTION_CALLBACK_TOKEN --env staging
npx wrangler secret put PUBLIC_WORKER_URL --env staging
```

`PUBLIC_WORKER_URL` is the deployed public Worker base URL. The Worker appends `/v1/transcription-callback`. The callback accepts only a metadata-only `POST` with the configured bearer token, a syntactically valid provider job ID, and `status=success`. It never accepts a transcript body. A valid callback queues only the opaque Transcription Job UUID. The consumer retrieves JSON-v2 from Speechmatics, stores it in private R2, then atomically persists the Automatic Transcript projection.

Before using a real interview, exercise only a synthetic provider job and record pass/fail for: rejected missing or incorrect bearer, rejected failed status and body payload, accepted empty success callback, one private artifact, one complete Transcription Job, and an idempotent duplicate callback. Do not retain callback URLs, provider IDs, tokens, object keys, or transcript content as evidence.

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

## Transcription recovery validation

Use synthetic Audio only. Record pass/fail and HTTP status only for each check:

- two transient submission failures followed by stable-reference reconciliation with one provider job;
- terminal submission or ingestion failure after three deliveries;
- owner-authorized retry that queues the existing backed-up Original Audio without another multipart upload;
- one preserved Automatic Transcript projection and artifact after successful ingestion;
- provider deletion success, plus cleanup retries that retain transcription `complete` while cleanup is pending or failed.

Do not retain provider IDs, provider responses, transcript text, object keys, signed URLs, credentials, callback tokens, or API keys in commands, logs, evidence, or issue comments. A failed synthetic job must be retried only through the Audio detail `Retry transcription` control. Do not create another Audio merely to retry processing.

## Web editorial review staging validation

Use two synthetic owners only. After explicit deployment approval, verify magic-link sign-in, owner library visibility, private playback, Transcript Segment seeking, active-segment indication, and foreign-owner denial. Record only pass/fail and HTTP statuses. Do not retain email addresses, tokens, Audio IDs, signed URLs, object keys, or transcript text.

## Editorial corrections staging validation

Use a completed synthetic Audio with an uncorrected Transcript Segment and an existing Editorial Speaker. Run only against isolated staging. The test creates and removes both correction types. It never prints source content or identifiers.

```sh
export EDITORIAL_TEST_SUPABASE_URL='https://….supabase.co'
export EDITORIAL_TEST_SUPABASE_PUBLISHABLE_KEY='…'
export EDITORIAL_TEST_OWNER_TOKEN='…'
export EDITORIAL_TEST_OTHER_OWNER_TOKEN='…'
export EDITORIAL_TEST_AUDIO_ID='…'
export EDITORIAL_TEST_SEGMENT_ID='…'
cd apps/worker && npm run test:integration -- staging-editorial-corrections
```

The suite skips if any value is absent. A passing run proves owner text and Speaker corrections are readable to the owner, hidden from the foreign owner, removable independently, and leave the automatic Segment unchanged. It also verifies that the owner cannot mutate automatic Segment content. Record only pass/fail and HTTP status categories in the evidence table.

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
| 2026-08-25 | `supabase test db --local supabase/tests/audio_backups_rls.test.sql` for Issue #45 on iMac | Pass. `Files=1, Tests=21`, `Result: PASS`. |
| 2026-08-25 | Staging Worker integration | Pass, user-confirmed. |
| 2026-08-25 | Physical iPhone flow | Pass, user-confirmed. |
| 2026-08-27 | Worker lifecycle fakes: `npm run check && npm test` | Pass. TypeScript check passed; 64 tests passed, with one staging-only test skipped. Covers queue submission, callback, ingestion, bounded retry, explicit retry, and cleanup. |
| 2026-08-27 | iOS suite on iPhone 15 simulator | Pass. 111 unit tests and 12 UI tests passed. |
| 2026-08-27 | Isolated staging backup integration | Pass, user-executed. The synthetic multipart backup test completed against staging R2, Worker, Supabase, and RLS. |
| 2026-08-27 | Local pgTAP suite | Blocked. No local Supabase database was running at `127.0.0.1:54322`. |
| 2026-08-27 | Physical iPhone staging transcription pipeline | Pass, user-confirmed. A synthetic Audio reached available local audio, verified cloud backup, and complete transcription. |
| 2026-08-27 | Physical recovery after forced termination | Pass, user-confirmed. A synthetic Capture was recovered and playable after relaunch. |
| 2026-08-27 | Physical audio-session interruption | Pass, user-confirmed. The interrupted synthetic Capture remained in the library and playable. |
| 2026-08-27 | Two-hour physical reliability check | Pass, user-confirmed. The synthetic two-hour physical Capture completed as expected. |
| 2026-08-27 | Local pgTAP suite on iMac | Pass. `Files=1, Tests=66`, `Result: PASS`. |
| 2026-08-28 | Web editorial review synthetic staging E2E | Pass. Owner: 2xx. Unauthenticated playback: 401. Foreign-owner detail and playback: 404. |
