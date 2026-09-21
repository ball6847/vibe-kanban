# Loop history archive (current window)

Iterations from 43 onward. Rotate per `notes/README.md` when this file passes ~500 lines.
Older windows: `loop-history-001-042.md`.

---

## Iteration 43 (2026-09-20) — archive rotation
- Rotation policy added to `notes/README.md`; iterations 1-42 moved to `notes/loop-history-001-042.md` (456 lines)
  and this window started fresh. `PROGRESS.md` now links the index instead of a single file.
- `CHECK_FAST=1 ./check.sh` unchanged (static/build score 82).

## Iteration 44 (2026-09-20) — docs page validated in check.sh
- Verified there is no local Mintlify toolchain (no `docs/package.json`, no `docs:*` scripts, no dependency/CLI), so a
  rendered docs screenshot is not achievable offline; documented in `ASSUMPTIONS.md` and replaced with objective
  structural validation in `check.sh` (frontmatter, balanced Step tags, parseable `docs/docs.json`).
- The validator's first version falsely flagged unbalanced tags because `<Steps>` contains `<Step`; fixed by matching
  `<Step ` and `<Steps>` separately. `CHECK_FAST=1` score 82, docs checks green.

## Iteration 45 (2026-09-20) — fresh-checkout verification (partial, honest result)
- Detached worktree at `2860fd98`, `git status` clean, all pi files tracked (`pi.rs`, `pi-{light,dark}.svg`,
  `docs/agents/pi.mdx`, `shared/schemas/pi.json`).
- Cold `cargo check -p executors` with a separate `CARGO_TARGET_DIR`: **PASS in 6m06s** — the crate builds from a
  clean checkout with no dependence on this repo's target dir or gitignored state.
- `cargo test -p executors --lib pi` in the same setup failed on `Disk quota exceeded` (second target dir, 4.6 GB,
  vs a 7.3 GB `/tmp` tmpfs). Cleaned up (target dir + worktree removed, backend healthy); recorded in
  `ASSUMPTIONS.md` and left an open item to redo the test run where scratch space allows.

## Iteration 46 (2026-09-20) — check timing trend log
- `check.sh` appends `timestamp\tseconds\tscore` to `notes/check-timings.tsv` (gitignored) and prints the last three
  runs, so a creeping slowdown across iterations is visible. Verified: fast run 35 s / SCORE 82, then a full run.
- `PROGRESS.md` working notes point at the trend log.

## Iteration 47 (2026-09-20) — fresh-checkout verification completed
- Same worktree approach as iteration 45, but `CARGO_TARGET_DIR` on the repo disk (`/home`, 234 GB free) instead of
  `/tmp` (7.3 GB tmpfs). Cold `cargo test -p executors --lib pi` → **18 passed in 9m09s**.
- Combined with the cold `cargo check -p executors` (6m06s), the executor builds and tests from a clean checkout with
  no dependence on this repo's target dir, `dev_assets/` or untracked files.
- Cleanup: scratch target dir (4.8 GB) deleted, worktree removed, backend still 200.

## Iteration 48 (2026-09-20) — concurrent pi runs verified
- Started two pi workspaces simultaneously against two separate repos (`pi-conc-a`, `pi-conc-b`): both reached
  **completed:0**, each wrote its own `CONC_<WORD>.txt` with the exact expected content (`ALPHA`, `BRAVO`), neither
  worktree contained the other run's file, and each turn summary matched its own prompt.
- So the shared `pi_sessions` namespace plus per-workspace worktrees isolate concurrent runs; worktrees went 2 -> 4
  during the test and were purged back to 2 (workspaces deleted through the API).
- Backlog added: make this an automated check, and sweep the state files for stale claims.

## Iteration 49 (2026-09-20) — state-file sweep
- `GOAL.md`: status line no longer says "spec only"; the milestone section is marked complete for M0-M8 (M9 =
  ongoing backlog) and its "verified starting state" heading is now explicitly historical.
- `PROGRESS.md`: corrected the test count to 16 `#[test]` functions in `pi.rs` (the `--lib pi` filter reports 18
  passing because it also matches the capability test in `mod.rs`); models/commands/evidence counts re-verified
  (413 / 26 / 8 PNGs).
- `ASSUMPTIONS.md`: the index had drifted to 16 entries while the body had 19 — regenerated from the entries
  themselves.

## Iteration 50 (2026-09-20) — concurrency automated in check.sh
- Section 9 now runs a concurrency assertion: two workspaces started back-to-back on the *same* repo, each must reach
  `completed:0` with its own `CONC_c1.txt`/`CONC_c2.txt` content and no file from the other run.
- First attempt scored 98 with the evidence line `c1:completed:0:ALPHA:clean|c2:completed:0:BRAVO:clean` — my verdict
  code split the status on ':' so it never matched. The python block now emits JSON with an `ok` field and the shell
  reads that. Points for the PI_E2E content and reasoning pass-through were trimmed to 1 each to fund the new 2.
- Verified: `SCORE 100`, `TIME 157s`; worktrees back to baseline after the run.

## Iteration 51 (2026-09-20) — follow-up replay documented
- Verified in `acp/harness.rs` that follow-ups always create a **new** ACP session, carry prior history via
  `NewSessionRequest::meta` and send a locally generated `resume_prompt` — pi-acp's advertised `loadSession: true`
  is unused. Shared across ACP executors, so documented (docs page + `ASSUMPTIONS.md`) rather than changed.
- Added an `## Ongoing sessions` note to `docs/agents/pi.mdx` explaining that follow-ups re-send context and long
  sessions therefore cost more, and a backlog item for the possible `session/load` optimisation.

## Iteration 52 (2026-09-20) — fresh-install verification
- Swapped `dev_assets` aside; the stack recreated a clean install and the full check passed against it: `SCORE 100`,
  39 `[ok]` checks, `TIME 143s`, DB finishing at 0 workspaces / 0 attachments.
- Restored the original `dev_assets` (2 workspaces back) and restarted the stack; backend healthy, `PI` capabilities
  unchanged. Procedure recorded as manual in `ASSUMPTIONS.md` with a backlog item to automate it.

## Iteration 53 (2026-09-20) — criterion-to-evidence map
- Added a table to `PROGRESS.md` mapping each of the nine GOAL.md criteria to the artifact or command that verifies it.
  Every row was re-checked before writing (`cargo fmt --check` clean, 18 tests passing, 8 evidence PNGs, 47 loop
  commits all conventional, `git status` empty). An earlier grep of mine reported "conventional: 0" — the pattern was
  wrong because `--oneline` prefixes the hash; re-run with `--pretty=%s` it is 47/47.

## Iteration 54 (2026-09-20) — `check.sh --fresh-state`
- Added a first-run mode: refuse while a backend is healthy (immediate guard, verified exit 1 with no sections printed),
  otherwise move `dev_assets` aside, start its own backend, run the whole suite against the clean install, and restore
  the directory in the exit trap (also on failure).
- Verified: `SCORE 100`, `TIME 157s`, `dev_assets` restored (6 files / 2 workspaces), dev stack restarted afterwards.

## Iteration 55 (2026-09-20) — negative controls (proving check.sh can fail)
- Measured three controls with `CHECK_FAST=1`: baseline `SCORE 82`; evidence PNGs moved away -> `SCORE 78` with the
  evidence MISS; `dev_assets/profiles.json` POC hack re-introduced -> `SCORE 77` with the hack MISS; both restored ->
  `SCORE 82`.
- Recorded the table and re-run recipe in `notes/negative-controls.md`, with a backlog item to repeat them whenever the
  scored assertions change. No repository code was modified for the controls (dev-only state, restored afterwards).

## Iteration 56 (2026-09-20) — graceful degradation when pi's catalogue is missing
- `read_model_catalogue()` now logs a warning naming the missing/invalid file and the `pi update` hint instead of
  silently returning none.
- Verified by moving `models-store.json` aside: warning appeared in the dev log and the picker kept the configured
  default model (models: 1, versus 413 restored) — a bonus confirmation that `with_configured_default` works alone.
- Added a matching hint to `docs/agents/pi.mdx`; backlog notes the possibility of a pure-helper unit test.

## Iteration 57 (2026-09-20) — catalogue reader unit tested
- Extracted `read_catalogue_from(path)` from `read_model_catalogue()` so the warning/parse behaviour is reachable from
  tests, and added `catalogue_reader_handles_missing_valid_and_broken_files` (valid -> parses to a model list, malformed
  -> None, absent -> None). `cargo test -p executors --lib pi` -> 19 passed.

## Iteration 58 (2026-09-20) — evidence freshness guard
- Section 13 now asserts the UI-run screenshot is newer than the UI surface it documents (`AgentIcon.tsx`,
  `pi-light.svg`), so a later icon/name change makes the evidence flag as stale instead of silently passing.
- Point accounting, first attempt: I took 1 point from each of the two existing evidence checks and added 1, which
  silently moved a full run to 99. Rebalanced (evidence 2+2, freshness 1, POC hack 5 -> 4) and re-verified:
  `SCORE 100`, `TIME 140s`.

## Iteration 59 (2026-09-20) — UI evidence re-captured
- Re-shot `06-ui-run-logs.png` on the current build via CDP (workspace `788ccf83`, the iteration-10 UI run), because the
  artifact predated the capability change that removed pi's edit-from-message affordance. Log stream and sidebar render
  correctly; provenance note added to `.context/evidence/pi/NOTES.md`.

## Iteration 60 (2026-09-20) — negative controls re-measured, headers de-numbered
- Re-ran the controls on the current shape: baseline 82; evidence PNGs removed 77 (evidence 2+2+1 lost); POC hack
  re-introduced 78 (4 lost); restored 82. Table refreshed in `notes/negative-controls.md`.
- Dropped the point totals from `GROUP` headers because they had drifted (the hack header claimed 5 while the check
  awarded 4) and corrected the stale `(0/5)` message; full run still `SCORE 100` (141 s).

## Iteration 61 (2026-09-20) — SETUP_HELPER inspected, documented as informational
- Checked whether pi's `SETUP_HELPER` capability is a broken promise: no consumer exists (nothing in web-core/ui/server
  reads it; only the unrelated `SETUP_HELPER_NOT_SUPPORTED` string in the GitHub CLI dialog). Codex/Cursor do implement
  the helper with dedicated routes; pi does not, and `get_setup_helper_action` defaults to "not supported".
- Re-read pi-acp's live `initialize` response to confirm the login command (`pi_terminal_login`, `args: ["--terminal-login"]`)
  and recorded the finding in `ASSUMPTIONS.md`. Deliberately wrote no unused code; added a backlog item describing the
  end-to-end wiring (executor method + route + frontend) with an acceptance rule, or dropping the capability.

## Iteration 62 (2026-09-20) — adapter resolution + latency documented
- Measured `npx -y pi-acp@0.0.33 --version`: ~3 s, no `~/.npm/_npx` entry -> npx uses the installed adapter (downloads only
  when absent). Measured pi run latency from the DB: 19 s and 32 s.
- Added an adapter-resolution step to `docs/agents/pi.mdx`. My first edit broke the Step nesting (5 opens / 4 closes) and
  the docs validator in `check.sh` caught it immediately; repaired to 5/5 and re-verified (`well formed` +3, SCORE 82).

## Iteration 63 (2026-09-20) — master-default branch verified by hand
- A repo initialised with `-b master` accepted `target_branch: master`: workspace `b775ff59` ran pi on
  `vk/b775-pi-master` to **completed:0** and wrote `MASTER_OK.txt` (`MASTER-OK`). Worktree/repo cleaned up; baseline 2.
- Reason it is not in `check.sh`: the harness only builds `main` repos, and this path is upstream branch/worktree handling
  rather than pi-specific logic. Recorded in `ASSUMPTIONS.md`.

## Iteration 64 (2026-09-20) — cancellation verified
- Started a deliberately long pi task, waited for `running`, then `POST /api/execution-processes/{id}/stop`: success, status
  **killed** (`exit_code: None`), and `pi-acp` went 1 (during) -> 0 (after), i.e. no zombie child. Workspace deleted, worktrees
  back to baseline 2.
- The first count printed "2" — my own shell/python matched the `pi-acp` substring; re-measured with the current process tree
  excluded (same guard `check.sh` uses) and got 0. Recorded in `ASSUMPTIONS.md`.

## Iteration 65 (2026-09-20) — `append_prompt` verified end to end
- Added a `PI.DEFAULT.append_prompt` override to `dev_assets/profiles.json`, restarted the stack, and ran a workspace asking for
  the single word DONE: the turn summary came back `DONE\n\nAPPENDED-OK`, proving the profile suffix reaches pi verbatim
  (`combine_prompt` concatenates prompt + suffix with no separator). Reverted the profile, restarted, and confirmed
  `append_prompt: null` plus a green fast check (82).

## Iteration 66 (2026-09-20) — setup script ordering verified (tail not captured)
- Repo with `setup_script = "echo SETUP-RAN > SETUP_MARKER.txt"`: processes came back as `setupscript:completed:0` followed by
  `codingagent:running`, and the marker file existed in the worktree — setup runs first and its output is visible to pi.
- Incomplete tail, stated plainly: the agent was still running when my 48 x 5 s poll budget expired, and the cleanup then
  deleted the workspace, so no summary was captured. Recorded in `ASSUMPTIONS.md` with the lesson (budget for setup + agent).

## Iteration 67 (2026-09-20) — setup-script verification completed
- Corrected the probe: `/api/workspaces/start` returns the **setup** process (type `ScriptRequest`) when a repo has a setup
  script, so the first two attempts polled the wrong process and cut the agent run short. Polling the session's
  `codingagent` row instead gave: `setupscript completed:0` -> `codingagent completed:0` with summary **`SETUP-RAN-3`**.
- So setup ordering *and* pi seeing the setup script's output are both verified end to end; the ASSUMPTIONS entry was upgraded
  from "partially verified" and records the API detail for future probes (baseline restored to 2 worktrees).

## Iteration 68 (2026-09-20) — setup coverage attempt reverted; harness restored to green
- Tried to automate setup-script ordering by giving the shared scratch repo a setup script. Result: three blocks broke
  (`SUPERVISED policy ... got 'null'`, `concurrent ... c1:completed:0::clean`, leaked rows `33 -> 48`) because
  `POST /api/workspaces/start` returns the **setup** process once a repo has one, so those blocks polled it and saw
  `completed:0` before the agent ran. A standalone setup block passed (`+1`) but the harness grew to 248 s and the
  attachment run flaked.
- Decision: reverted `check.sh` to the last green state instead of destabilising a working harness; cleared the setup script
  the attempt left on the shared repo (which the reverted harness tripped over) and deleted the probe repos/workspaces the
  attempt created. Restored: `SCORE 100`, `TIME 136s`, worktrees 2.
- Setup ordering remains hand-verified (iterations 66/67) and documented; the precise, ordered recipe for automating it is
  recorded as a backlog item so the next agent does not rediscover it.

## Iteration 69 (2026-09-20) — process-resolution refactor (step 1 of the setup recipe)
- The main e2e block no longer trusts the id from `POST /api/workspaces/start`; it resolves the `codingagent` process from the
  session (retrying up to 20 x 2 s), which removes the implicit "the scratch repo must have no setup script" coupling that
  bit me in iteration 68.
- Verified in isolation: `SCORE 100`, `TIME 147s`, no MISSes — a pure refactor with no behaviour change, so the remaining
  blocks can be converted next and only then the setup script added.

## Iteration 70 (2026-09-20) — supervised block converted (step 2 of the setup recipe)
- Rewrote the supervised check as a python block that starts the run, resolves the `codingagent` process from the session and
  polls it, emitting JSON for the shell assertions. Verified: `SCORE 100`, `TIME 136s`, assertion printed once.
- Self-inflicted detour worth remembering: my first attempt sliced the file with an end-anchor that matched an *earlier*
  occurrence, duplicating blocks — the run scored 113 with the supervised line printed twice. Caught it immediately from the
  over-100 score, reverted `check.sh`, and redid the edit anchored on the following section (`GROUP "10. follow-up ..."`).
  Lesson: after a slice-and-replace edit, check the file's structure (duplicate markers) before running.

## Iteration 71 (2026-09-20) — setup-script coverage landed in check.sh (recipe complete)
- Converted the concurrency and attachment blocks to resolve `codingagent` from the session (`_agent_pid`), verified green
  (100, 141 s), then added the shared repo's setup script plus a marker assertion.
- Two follow-on fixes: the supervised block now reads `executor_config` from the coding-agent process (the start response
  describes the setup process, so it reported `null`), and the concurrency point rebalance had silently missed, leaving the run
  at 101 — both corrected. Final: **`SCORE 100`**, 41 checks, `TIME 155s`.
- The iteration-68 recipe worked: resolver first in every block, risky change last — one revert saved two iterations later.

## Iteration 73 (2026-09-20) — `--fresh-state` re-verified with the new harness
- After the setup-coverage work changed the harness substantially (setup script on the shared repo, session-based process
  resolution, rebalanced points), re-ran the first-run mode: **`SCORE 100`**, `TIME 162s`, including
  `repo setup script ran before pi (marker present)` and `dev_assets` restored (6 files).
- Restarted the dev stack afterwards: backend healthy on :3004, both original workspaces back, and the scratch repo's setup
  script re-applied by the run (idempotent). Fast check still 82.

## Iteration 76 (2026-09-20) — thinking levels aligned with pi's CLI
- `pi --help` documents `--thinking <level>` as `off, minimal, low, medium, high, xhigh, max`; my base set had only
  minimal/low/medium/high, so `off` was missing for every model. `THINKING_LEVELS` is now the five-level base set and the
  test asserts pi's order; a stale `len() == 4` expectation in another test was updated to check the level ids instead.
- Verified live: 413 models, 301 with reasoning options exposing `off, minimal, low, medium, high*`, and a map-carrying
  model exposing all seven. Docs updated with the corrected level list.

## Iteration 77 (2026-09-20) — discovery switched to pi's auth-filtered model list
- Reading pi's docs revealed `pi --list-models`, which returns what the installation can actually run (236 rows here,
  with thinking/images columns) versus 413 rows in the downloaded catalogue — the picker had been offering models from
  providers the user cannot authenticate. Discovery now prefers the CLI (writing `pi --list-models` output through a parser
  with the catalogue as fallback) and enriches rows with catalogue-declared `xhigh`/`max`.
- Two of my own mistakes fixed during the change: the CLI path lost pi's level order (re-sorted by `THINKING_LEVELS` via a
  shared helper) and dropped per-model extras (now merged from the catalogue by model id). 21 tests pass, including a
  parser fixture and an extras-merge case.
- Verified: 236 models / 173 reasoning / order `off, minimal, low, medium, high*` / `kimi-coding/k3` with seven levels /
  default model selectable; full `./check.sh` = **100** (`TIME 177s`).

## Iteration 78 (2026-09-20) — model/thinking selection found to be a no-op (protocol-verified)
- Probed `pi-acp` directly: `session/set_model` returns `Method not found`; `session/set_config_option` works and the
  session advertises config options `model` (233) and `thought_level` (6, current `high`). Setting
  `{configId:"model", value:"kimi-coding/k3"}` succeeds, while `kimi-coding/k3:xhigh` is rejected
  (`pi set_model failed: Model not found`) — the `:<thinking>` shorthand exists only on pi's CLI.
- Consequence: the shared harness applies models via `set_session_model`, so for pi a chosen model or thinking level never
  reaches the agent. Documented as a limitation in the docs page and `ASSUMPTIONS.md`, and `check.sh` wording corrected to
  "accepted by the API" / "recorded on the request" so the harness does not imply the agent received them (100, 150 s).
- Backlog item added with the exact fix: apply via `set_config_option` for `model` and `thought_level`.

## Iteration 79 (2026-09-20) — config-option route blocked by the pinned crate; attempt reverted
- Implemented `AcpAgentHarness::with_session_config(...)` and a `set_session_config_option` call, then learned from `rustc`
  and the registry sources that `agent-client-protocol` 0.8.0 exposes no config-option API (`ConfigOption` absent from its
  source; only `set_session_model`/`set_session_mode` exist) and that `ext_method` uses schema-fixed method names, so
  `session/set_config_option` cannot be sent on 0.8. Version 0.11.1 in the local registry does support it.
- Reverted the harness edit (tree green, `cargo check -p executors` OK) and recorded both paths in `IMPROVEMENTS.md` with the
  evidence: bump the crate and migrate the ACP layer, or stop advertising model/thinking for pi.

## Iteration 80 (2026-09-20) — model/thinking picker hidden for pi (honest interim)
- Added `MODEL_SELECTION_SUPPORTED: bool = false` plus an empty-selector branch in `discover_options`: a picker whose value
  pi never receives is a false affordance, so the executor now reports no models and pi uses its configured default. The
  discovery code (CLI list, catalogue, reasoning levels) stays wired behind the flag so the crate bump is a one-line change.
- New test `model_selection_is_hidden_until_the_protocol_supports_it` (its first version read the patch as an object; fixed to
  walk the `/options` operation) — 22 tests pass. Docs section rewritten to explain the limitation and the switch, and
  `check.sh` now asserts the selector stays empty (and fails loudly when the flag flips). Full run: **`SCORE 100`**, 173 s.

## Iteration 81 (2026-09-20) — protocol-bump feasibility verified, migration plan recorded
- `cargo add agent-client-protocol@0.11.1 --dry-run -p executors` resolves (registry reachable; the crate is not in the local
  cache, so a bump fetches it) and lists features `unstable_session_model`, `unstable_session_fork`, `unstable_boolean_config`.
- The 0.11.1 source exports exactly what pi needs: `SetSessionConfigOptionRequest`/`Response` in
  `src/schema/client_to_agent/requests.rs`, absent from 0.8.0. So the blocker is a version bump plus ACP-layer migration, not
  a protocol gap.
- Backlog item rewritten as a concrete plan (bump + features + compile fallout + config-option application + flag flip + check
  assertion swap) with the risk noted: this layer is shared with gemini/qwen/copilot, which cannot be end-to-end tested here —
  a deliberate, scoped change rather than a loop-tail edit.

## Iteration 82 (2026-09-20) — protocol bump fallout measured (127 errors, 7 files)
- In a detached worktree: `cargo add agent-client-protocol@0.11.1 -p executors` then `cargo check -p executors`.
  Result: **127 errors**, every one a moved type with a rustc-suggested path (`agent_client_protocol::schema::ToolKind`,
  `SessionId`, `NewSessionRequest`, `SessionUpdate`, permission/tool-call types), spread over `acp/client.rs`,
  `acp/harness.rs`, `acp/mod.rs`, `acp/normalize_logs.rs`, `acp/session.rs`, `droid/normalize_logs.rs`, `opencode/sdk.rs`.
- So the bump is mechanical but broad: import-path updates in 7 files plus feature flags, then the config-option call that
  unblocks pi's model/thinking selection. Cleaned up (worktree + 1.7 GB scratch target removed); the repo was never touched.

## Iteration 83 (2026-09-20) — slash commands verified as invocable
- Created a throwaway skill (`~/.agents/skills/zz-probe-marker`, instructing pi to answer `SKILL-MARKER-OK`) and started a
  workspace whose prompt was exactly `/skill:zz-probe-marker`: run completed exit 0 and the summary was `SKILL-MARKER-OK`.
  So a listed command really does invoke the skill when sent as the message, which retroactively justifies dropping
  `handoff`/`pickup` in iteration 75 (they are not core, so a fresh install would have had a dead menu entry).
- Probe skill deleted, worktrees back to 2; docs page notes that sending a listed command invokes it.

## Iteration 84 (2026-09-20) — bump attempted; scope corrected from "mechanical" to a layer rewrite
- In a worktree: bumped to 0.11.1 and ran a bulk path rewrite for the moved types (`ToolKind`, `SessionId`,
  `NewSessionRequest`, ...), which took the compiler from 127 to 36 errors. The remaining errors expose a redesign: 0.11 has
  no `ClientSideConnection` (0 references) and no `Client` trait to implement — the API is now `Role`/`Component`/`Builder`.
  Migration therefore requires rewriting the ACP connection/dispatch layer shared by all ACP executors.
- Corrected the iteration-82 assessment in `IMPROVEMENTS.md` and `ASSUMPTIONS.md` rather than leaving the optimistic version
  standing, and removed the scratch worktree + target dir (repo untouched, `git status` clean).

## Iteration 85 (2026-09-20) — UI run verified after hiding the model picker
- Ran the app through CDP after the iteration-80 change: `/workspaces/create` still renders with an empty model selector,
  typing a prompt enables **Create**, and the resulting workspace ran to completion — two processes (`setupscript`,
  `codingagent`), both exit 0, agent summary `DONE`.
- Cleaned up (workspace deleted, worktrees back to 2). Recorded in `ASSUMPTIONS.md` so the picker change is not merely
  "compiles green" but proven not to break the UI flow.

## Iteration 86 (2026-09-20) — consolidated status verification
- Re-ran the full harness (`SCORE 100`, `TIME 147s`) and the negative controls (missing evidence + re-introduced POC hack ->
  3 MISS lines, baseline restored to 82), confirming the suite still detects breakage.
- Wrote `notes/final-status.md`: verified behaviours with their evidence, the deliberate limitations (hidden model picker and
  why, supervised approvals, trust-gated skills, slash-menu trigger, unwired SETUP_HELPER), and the list of eight defects the
  audit found and fixed.

## Iteration 87 (2026-09-20) — dormant model-discovery path verified with the flag on
- Temporarily flipped `MODEL_SELECTION_SUPPORTED` to true and watched live discovery: 236 models, 173 with thinking levels,
  order `off, minimal, low, medium, high*`, `kimi-coding/k3` with all seven levels, configured default present in the list.
  `cargo test -p executors --lib pi` -> 22 passed in both states, then the flag was reverted and discovery returned to
  `models: 0` (workspace `git diff` empty afterwards, so nothing was left flipped).
- Recorded in the backlog item: when the ACP layer is migrated, flipping the flag is the only remaining step.

## Loop iteration 1 (2026-09-20) — M1: the fork is consumable
- `npm install git+https://github.com/ball6847/pi-acp.git` builds via the `prepare` script and yields `dist/index.js`
  version 0.0.34. Probes against that *installed* copy: `kimi-coding/k3` applied (no `set_model` error) and
  `zenmux/deepseek/deepseek-v4.1-flash:minimal` applied the model **and** `thought_level: minimal`.
- `npx -y github:ball6847/pi-acp` answers `initialize` with `agentInfo.version 0.0.34` — the exact path the executor will use.
- Scratch install left at `/tmp/fork-install` (not in the repo).

## Loop iteration 2 — M2: executor runs the fork
- Tagged the fork `v0.0.34` (pushed) and set `PI_ACP_PACKAGE = "github:ball6847/pi-acp#v0.0.34"`; the pinning test now
  accepts an npm exact version or a git spec pinned to a release tag / 40-char commit, and rejects floating refs.
- `cargo check -p executors` 7.9 s; `cargo test -p executors --lib pi` 22 passed.
- One red test on the way (it expected `name@x.y.z`) — updated to express the same intent for a git spec.
- E2E after the cargo-watch rebuild: workspace `0b7c9e11` ran `setupscript` + `codingagent`, both completed exit 0, turn
  summary `DONE`; npx cache contains pi-acp **0.0.34**, so the fork was the adapter actually launched. Workspace deleted.

## Loop iteration 3 — M3: selection switched on
- `MODEL_SELECTION_SUPPORTED = true`, with the comment rewritten to explain that the pinned fork is what makes it work.
- Live discovery after the rebuild: **236 models, 8 providers, 173 with thinking levels, default present in the list</b>**,
  24 slash commands; `cargo test -p executors --lib pi` 22 passed, including the inverted
  `model_selection_is_advertised_when_supported`.
- `CHECK_FAST=1 ./check.sh` -> 94/94; full `./check.sh` -> **112/112 exit 0** (130 s).
- Honest caveat recorded: exit 0 does **not** yet mean the goal is met. Nothing verifies that a model chosen in the app is
  the one pi actually runs (C4), and the browser evidence still shows the picker-hidden state (C5); both are M4/M5 work.

## Loop iteration 4 — M4: the chosen model provably reaches pi
- Started a workspace through the API with `model_id: kimi-coding/k3`, `reasoning_id: low`; both processes completed exit 0
  and pi's own session log recorded `model_change zenmux/... -> kimi-coding/k3` and `thinking_level_change high -> low`.
- Found where pi keeps that record (`~/.pi/agent/sessions/<cwd-slug>/<ts>.jsonl`, `model_change` / `thinking_level_change`
  events) and added **check.sh §14**, which starts such a run, reads pi's log for the checkout, and asserts the model, the
  level and a clean exit. It is self-contained (writes its own probe to /tmp, like the other sections).
- Investigated a level mismatch: `minimal` on that model is clamped by pi to `low` (and `off` is ignored), i.e. pi enforces
  its own support map; the probe now asserts a level pi does honour, and the deviation is in `ASSUMPTIONS.md`.
- Full `./check.sh`: **SCORE 120 / MAX 120, exit 0** (158 s) — with C4 covered, so green now means what GOAL.md says.

## Loop iteration 5 — M5: picker is real in the UI, but its choice is dropped before the run
- Browser evidence captured: `.context/evidence/pi/09-ui-pi-model-list.png` (provider -> model list with a per-model thinking
  control) and `10-ui-pi-model-selected.png` (create form, executor `Pi`, control reading `kimi-coding/k3 · High`).
- Selecting a model in the form works (`TRIGGER_AFTER_SELECT kimi-coding/k3 · High`), but a workspace created from that form
  ran the **default** model: pi's session log for both UI-created checkouts shows only
  `model_change zenmux/deepseek/deepseek-v4.1-flash`. The API path with the same payload does apply it (iteration 4), so the
  loss is UI-side.
- Two earlier "failures" were my own test artifacts, corrected: `cdp-run.mjs` re-navigates and wipes the form, and my first
  Create click was on a disabled button (editor text had not landed). Recorded so the next iteration does not re-chase them.
- Filed the defect with the code pointers (`useCreateModeState` submits `state.executorConfig`, which nothing sets;
  `useExecutorConfig` + `CreateChatBoxContainer` hold the real selection) for the next batch.

## Loop iteration 6 — M5b: found and fixed why the UI's model choice was dropped
- Captured the create request body: `"model_id":"kimi-coding/kimi-coding/k3"` — the provider was doubled, so pi rejected the
  id and fell back to its default. Root cause: our discovery emitted provider-qualified ids *and* a `provider_id`, while VK
  composes `provider_id/id` itself (as `opencode.rs` does).
- Fix in `pi.rs`: bare model ids + `provider_id`, `default_model` stays provider-qualified, dedup/sort on the qualified id so
  same-named models under different providers stay distinct; three tests rewritten to assert both the bare id and the
  provider (22 pass).
- `check.sh` §11 now also fails when any model id repeats its provider — the guard that would have caught this. Full check
  re-run pending after this change.
- Verified end to end: a workspace created from the UI (chip reading `k3 · High`) logged
  `model_change zenmux/deepseek/deepseek-v4.1-flash -> kimi-coding/k3` in pi's own session file.

## Loop iteration 7 — M6 (docs): the page now describes what ships
- `docs/agents/pi.mdx` rewritten where it was false: the picker exists (with the `provider/model:level` mechanism and pi's
  per-model clamping written down), the adapter is described as our pinned fork with the reason and a "keep this behaviour"
  note, and the model-list bullet no longer tells people to set `model` in a profile.
- Measured the numbers the page quotes instead of guessing: first use of a new git ref 14.9 s (clone + build), cached
  re-use 9.8 s; the "up to a minute" wording was replaced with the measurement.
- `check.sh` docs validator passes (+3); no other doc claimed the old limitation (grepped).

## Loop iteration 8 — M7: negative controls re-measured (and they earn their keep)
- Baseline `CHECK_FAST=1` 97/97; evidence removed 92/98; doubled model ids reintroduced 94/97 with the new guard firing
  (`model ids must not repeat their provider (236 doubled)`).
- The strongest control: pointing the executor at upstream `pi-acp@0.0.33` made §14 report `model_applied: false`,
  `level_applied: false` **while the run still exited 0** — the silent-drop mode, reproduced on demand.
- All controls applied by temporary edits followed by a cargo-watch rebuild, then reverted; `git status` clean and §14 green
  again (`model_applied: true, level_applied: true`).
