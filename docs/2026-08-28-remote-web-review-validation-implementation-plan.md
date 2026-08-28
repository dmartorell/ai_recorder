# Remote Web Review Validation Implementation Plan

> **For agentic workers:** Implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the Issue #61 web review flow from the original machine without Docker by running the local Vite SPA against explicitly deployed, synthetic-only staging services.

**Architecture:** The browser runs `apps/web` locally and uses only the Supabase publishable key plus the deployed Worker URL. Supabase Auth, RLS data reads, Worker playback authorization, and private R2 access remain remote; Docker is not involved. Staging is the target because the repository currently declares only a `staging` Worker environment; production deployment is a separate approval and configuration decision.

**Tech Stack:** Vite, React, Supabase Auth/Postgres, Cloudflare Worker/R2, Wrangler, GitHub Actions or operator-approved Wrangler deployment.

---

## Preconditions and boundary

- The current `apps/worker/wrangler.jsonc` has an `env.staging` configuration only. Do not infer a production Worker configuration or deploy to production.
- The Worker endpoint for this issue exists only on branch `dmartorell/issue-61-web-audio-transcript-review` until its commit is merged and deployed.
- Use exactly two staging test users and synthetic Audio. Do not use journalist Audio, production credentials, service-role keys, object keys, signed URLs, or transcript content as evidence.
- No deployment occurs until the user explicitly authorizes it.

## File structure

| Path | Responsibility |
| --- | --- |
| `apps/web/.gitignore` | Keeps the browser-only environment file out of Git. |
| `apps/web/.env.local` | Local-only staging URL and publishable-key configuration; never committed. |
| `apps/worker/wrangler.jsonc` | Existing staging Worker configuration, reviewed but not changed by this validation plan. |
| `docs/testing/cloud-backup-validation.md` | Records status-only staging E2E evidence after validation. |

### Task 1: Preserve local browser configuration safely

**Files:**
- Modify: `apps/web/.gitignore`
- Create locally only: `apps/web/.env.local`

- [ ] Confirm the ignored-file rule is present:

```bash
grep -Fx '.env.local' apps/web/.gitignore
```

Expected: one `.env.local` line.

- [ ] Commit and push the ignore-rule-only change before placing real values in the file:

```bash
git add apps/web/.gitignore
git commit -m 'chore: ignore local web configuration'
git push
```

Expected: a clean tracked worktree; `apps/web/.env.local` remains untracked and ignored.

- [ ] Create the local file on the original machine with only browser-safe values obtained from the staging dashboards:

```env
VITE_SUPABASE_URL=https://<staging-project-ref>.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=<staging-publishable-key>
VITE_WORKER_URL=https://<staging-worker-host>
```

Expected: no service-role key, Worker secret, signed URL, or source content appears in the file or shell history.

### Task 2: Prepare staging authentication and synthetic fixtures

**Files:**
- Modify: Supabase Auth staging Redirect URLs through the dashboard
- Modify: staging data through existing operator-approved synthetic-fixture workflow

- [ ] In Supabase Dashboard for staging, add this exact redirect URL:

```text
http://localhost:5173/auth/callback
```

Expected: a magic link opened from the original machine returns to the local SPA callback route.

- [ ] Verify the staging Supabase Project URL and publishable key match `apps/web/.env.local`; do not copy the service-role key into the browser or into a terminal command.

- [ ] Prepare two staging users: owner and foreign owner. Create one synthetic owner Audio with a verified cloud backup and preserved Automatic Transcript. The foreign owner must not own that Audio.

Expected: the owner has one cataloged Audio with ordered Automatic Speakers and Transcript Segments; the foreign owner has no permission for it.

### Task 3: Deploy the reviewed Worker to staging

**Files:**
- Review: `apps/worker/src/cloud-backup.ts`
- Review: `apps/worker/src/supabase-backup-store.ts`
- Review: `apps/worker/wrangler.jsonc`

- [ ] Obtain explicit approval for staging deployment, then verify the branch commits are in the deployment ref:

```bash
git log --oneline -2
```

Expected: `f0a34a4 feat: review private Audio on web` is present.

- [ ] Run local verification before deployment:

```bash
npm ci --prefix apps/worker
npm test --prefix apps/worker
npm run check --prefix apps/worker
```

Expected: all non-staging Worker tests pass.

- [ ] Deploy only the configured staging Worker after approval:

```bash
cd apps/worker
npx wrangler deploy --env staging
```

Expected: a successful staging deployment; do not print or retain the generated deployment URL if it contains identifiers beyond the configured public Worker host.

- [ ] Confirm the configured staging Worker host is the `VITE_WORKER_URL` in `apps/web/.env.local`.

Expected: the SPA requests `/v1/audios/:audioID/playback` from staging, not localhost.

### Task 4: Run the browser against staging without Docker

**Files:**
- Read locally only: `apps/web/.env.local`

- [ ] From the original machine, install and verify the SPA:

```bash
npm ci --prefix apps/web
npm test --prefix apps/web
npm run build --prefix apps/web
```

Expected: test and build commands pass without Docker.

- [ ] Start Vite on the original machine:

```bash
npm run dev --prefix apps/web
```

Expected: Vite serves `http://localhost:5173` and uses staging values loaded from `.env.local`.

- [ ] Complete a magic-link sign-in as the synthetic owner. Verify that `/audios` contains only the owner’s synthetic catalog row and that selecting it opens `/audios/:audioID`.

Expected: no foreign Audio or transcript data is rendered.

- [ ] In detail, start private playback, select a Transcript Segment, and confirm the player seeks to the Segment timestamp and marks it active as the playhead progresses.

Expected: no waveform, download action, editing control, retry action, signed URL, object key, provider identifier, or transcript content is copied into evidence.

- [ ] Sign in as the synthetic foreign owner and request the owner Audio detail and playback endpoint through the browser.

Expected: detail is unavailable and playback receives `404`; no URL is returned.

### Task 5: Record validation and close-out readiness

**Files:**
- Modify: `docs/testing/cloud-backup-validation.md`

- [ ] Add one status-only row to the Web editorial review staging validation evidence table with the date, pass/fail, and HTTP status categories. Do not record credentials, emails, IDs, source content, object keys, or URLs.

- [ ] Re-run static verification:

```bash
git diff --check
npm test --prefix apps/worker
npm test --prefix apps/web
npm run build --prefix apps/web
```

Expected: all commands pass.

- [ ] Open a PR, merge the reviewed branch, and close #61 only after Task 4 passes and the validation evidence is committed.

## Self-review

- Docker is required nowhere on the original machine because Supabase and R2 access are remote staging services.
- The local SPA receives only the Supabase publishable key and Worker URL; it never receives a service-role key or R2 credentials.
- The plan uses staging rather than production because staging is the configured Worker target and the approved Issue #61 validation specifies synthetic staging E2E.
- Literal Automatic Transcript data stays read-only, and tests do not add edits, downloads, waveforms, or generated content.
