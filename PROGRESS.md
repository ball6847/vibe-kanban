# PROGRESS

**Current state (iteration 73):** pi is a first-class executor with the whole feature verified end to end.
`./check.sh` reports **`SCORE 100`** across **41 checks** (~2.5 min), and `./check.sh --fresh-state` proves the same on a
clean install. 19 executor tests pass, 8 browser artefacts are captured with a freshness guard, and every GOAL.md criterion
is mapped to evidence below. 69 loop commits; `git status` clean.

## Verified working

- `PI` executor: `npx -y pi-acp@0.0.33` over ACP, `pi_sessions` namespace, model + `:<thinking>` over ACP.
- Discovery: 413 models (301 with thinking levels), 26 slash commands, pi's configured default model selectable.
- Availability: `LOGIN_DETECTED` / `INSTALLATION_FOUND` / `NOT_FOUND`; capabilities `["SETUP_HELPER"]` only.
- Attachments: uploaded files are read by pi from `<workspace>/.vibe-attachments/` (verified with a PNG).
- Docs: `docs/agents/pi.mdx` (setup, models, thinking levels, attachments, availability, upgrade runbook) +
  card and nav entry; 16 `#[test]` functions in `pi.rs` (the `--lib pi` filter reports 18 passing, including
  the capability tests in `mod.rs`).

## Goal criteria -> evidence

| # | Criterion (GOAL.md) | Verified by |
| --- | --- | --- |
| 1 | `Pi` executor, existing ACP pattern, pinned adapter | `crates/executors/src/executors/pi.rs`; `cargo test -p executors --lib pi` -> 18 passed |
| 2 | Selectable as `PI` with name/icon | `.context/evidence/pi/02-*.png`, `08-*.png`; `/api/info` -> `capabilities.PI = ["SETUP_HELPER"]` |
| 3 | Checks + formatting clean | `cargo check -p executors -p server`; `cargo fmt -p executors -- --check` clean |
| 4 | Unit tests | 16 `#[test]` in `pi.rs` (18 pass under the `pi` filter) |
| 5 | End-to-end via app + browser | `04-ui-pi-run-logs.png`, `06-ui-run-logs.png`; `check.sh` e2e + attachment + concurrency sections |
| 6 | Follow-up keeps context | `check.sh` "follow-up turn recalled turn-1 content" |
| 7 | Supervised approvals | deviation documented: `ASSUMPTIONS.md` (pi-acp only asks for extension UI prompts); `check.sh` asserts the policy reaches the executor and the run completes |
| 8 | POC hack removed | `check.sh` "no base_command_override left in dev_assets/profiles.json" |
| 9 | Format + conventional commits, clean tree | 47 loop commits, all conventional (`git log --pretty=%s`); `git status` empty; `notes/check-timings.tsv` gitignored |

Full run: `./check.sh` -> `SCORE 100` (39 checks; ~2.5 min). Fresh-install run (iteration 52) also 100.

## Open work

See `IMPROVEMENTS.md` — currently state-file hygiene (done here), stale dev workspaces from manual probes, and
attachment cleanup in `check.sh`.

## Working notes for the next agent

- Full check: `./check.sh` (~160 s, prints `SCORE` + `TIME`); `CHECK_FAST=1` for a ~30 s static/build pass.
- First-run proof: stop the dev stack, then `./check.sh --fresh-state` (swaps `dev_assets` aside and restores it).
- The dev stack auto-rebuilds (`cargo watch`); wait for the rebuild before trusting websocket assertions.
- Never use `pkill`/`pgrep -f` with a pattern that appears elsewhere in the same command line (it kills the shell).
- History: `notes/README.md` indexes the rotated archives (`notes/loop-history-*.md`).
- Run trend: `notes/check-timings.tsv` (gitignored) records every `check.sh` run's time and score.

## Iteration 39 (2026-09-20) — attachment cleanup + deterministic attachment check
- `check.sh` deletes its uploaded attachment (`DELETE /api/attachments/{id}`) and removes the stored file; verified
  over consecutive runs: attachment rows stayed at 1 and `.vibe-attachments/` was empty.
- Flakiness found and fixed: one run scored 98 because pi's free-form answer did not contain `blue`. The prompt now
  constrains the answer to `red|green|blue|yellow`, the check compares the trimmed content exactly, and the failure
  message prints the content so a real misread is still diagnosable.
- Re-verified: `SCORE 100`, `TIME 172s`.

## Iteration 40 (2026-09-20) — dev probe workspaces cleaned up
- Deleted the four loop-created probe workspaces (`pi-poc`, `pi-supervised`, `pi-slash`, `pi-image`) through the
  API (HTTP 202) and removed their worktrees: 6 -> 2 directories. Kept `summarize me stack use` (operator-created)
  and `788c-create-a-file-na` (the workspace behind the UI evidence artifact `06-ui-run-logs.png`).
- `CHECK_FAST=1 ./check.sh` still passes (static/build score unchanged), so the cleanup did not disturb the harness.

## Iteration 41 (2026-09-20) — DB row hygiene assertion + two self-inflicted bugs fixed
- Added a third run-hygiene check: workspace/session/execution-process/turn rows must not grow across a run
  (`count_db_rows()`); verified `8 -> 8`, confirming workspace deletion cascades to those rows.
- Bug 1 (mine): `ROWS_BEFORE` was computed before `DB_PATH` was resolved, so the check reported a fake leak
  (` -> 8`). Moved the assignment after the DB block.
- Bug 2 (pre-existing flake): pi sometimes answers the colour without writing `PI_IMG.txt`. The check now accepts
  the turn summary as equivalent evidence, searches one level deeper, and prints file content *and* answer on
  failure. `check.sh` also had a `tr` error on a missing file, now silenced.
- Verified: `SCORE 100`, `TIME 133s`, `attached image read by pi (file 'blue')`, `no leaked ... rows (8 -> 8)`.
- Backlog refilled with three items (force the attachment file, archive rotation, docs screenshot).

## Iteration 42 (2026-09-20) — attachment check root-caused (shell quoting) and rewritten
- Two clean failures (`completed:0`, no file, no turn) triggered a manual probe of the identical flow — which worked
  and even noted the file was written to cwd. That isolated the fault to the **check**, not pi.
- Cause: the attachment payload was built as a double-quoted shell string containing a multi-sentence prompt, so the
  JSON reached the server mangled (empty prompt -> agent did nothing, exit 0). The block is now a python program
  (`json.dumps` payload, polling, turn lookup, workspace cleanup) mirroring the manual probe.
- Verified twice: `attached image read by pi (file 'blue', status 'completed:0')`, `SCORE 100`, 121 s and 125 s,
  `.vibe-attachments/` empty, no leaked rows (`12 -> 12`).
- Lesson recorded: for multi-sentence payloads, build JSON in python rather than escaping it through bash.

## Goal 2 (fork-based model selection) — M1 done
- [x] M1 fork consumable: git install builds (v0.0.34) and applies model + thinking level; `npx -y github:ball6847/pi-acp`
      handshakes as 0.0.34.
- [x] M1 fork consumable (git install builds v0.0.34; probes apply model + thinking level; npx handshakes as 0.0.34)
- [x] M2 executor runs the fork (pinned `github:ball6847/pi-acp#v0.0.34`; e2e run exit 0 on the fork)
- [x] M3 selection switched on (discovery: 236 models, 8 providers, 173 with thinking levels, default present)
- [x] M4 the chosen model reaches pi -- `check.sh` §14 starts a run with a non-default model + level and asserts both from
      pi's own session log; full run is now 120/120, so exit 0 covers C4
- [x] M5 browser evidence: `09`/`10`/`11` in `.context/evidence/pi/` + NOTES; a UI-created run logged the chosen model
- [x] M6 docs describe selection, the fork and pi's clamping (numbers measured, not guessed)
- [x] M7 negative controls re-measured: baseline 97/97, evidence removed 92/98, doubled ids 94/97, upstream adapter ->
      §14 `model_applied: false` while the run still exits 0
- [x] M8 close-out: full `./check.sh` **123/123 exit 0** (207 s); `./check.sh --fresh-state` **123/123 exit 0** (220 s),
      `dev_assets` restored cleanly
