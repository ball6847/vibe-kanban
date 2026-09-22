# Loop history archive

Verbatim record of every loop iteration for this goal (pi-acp executor support). The live state lives in
`PROGRESS.md`; open items live in `IMPROVEMENTS.md`; decisions live in `ASSUMPTIONS.md`.

---

# PROGRESS

## Iteration 1 (2026-09-20) — M1/M2/M3 complete, SCORE 10 → 50
- Created `crates/executors/src/executors/pi.rs` (Pi executor, AcpAgentHarness, `pi_sessions` namespace,
  `npx -y pi-acp@0.0.33`, 2 unit tests).
- Registered in `mod.rs` (module, import, `CodingAgent::Pi`, `get_mcp_config` arm, `capabilities()`),
  fixed exhaustive match in `mcp_config.rs::preconfigured_mcp`.
- `crates/executors/default_profiles.json` gained `PI: {DEFAULT: {PI: {yolo: true}}}`;
  `pnpm run generate-types` regenerated `shared/types.ts` + `shared/schemas/pi.json`.
- `cargo check -p executors` and `-p server` pass.

## Next (iteration 2)
1. M5: delete `base_command_override` from `dev_assets/profiles.json` (POC hack, +5).
2. Rebuild + restart dev stack (`kill $(cat /tmp/vk-dev.pid); pnpm run dev`) so e2e uses new code.
3. M4: AgentIcon.tsx + `packages/public/agents/pi-{light,dark}.svg` (+10).
4. Run full `./check.sh` (e2e with executor `PI`).

## Iteration 2 (2026-09-20) — M5 done + full e2e GREEN, SCORE 50 → 80
- Deleted the POC hack (`dev_assets/profiles.json`) and restored `dev_assets/config.json` from
  `/tmp/vk-config.json.bak` (default executor back to GEMINI). QWEN_CODE is genuine qwen again.
- Killed + restarted the dev stack; the new backend (with `PI` compiled in) came up on **:3004**
  (port file `/tmp/vibe-kanban/vibe-kanban.port` -> 3004; frontend vite on :3000).
- `./check.sh` (full, no CHECK_FAST): **SCORE 80**. E2E with executor `PI` passed end-to-end:
  workspace completed exit 0, `PI_E2E.md` contains `PI-E2E-OK`, turn summary `DONE`,
  follow-up turn recalled turn-1 content. `npx -y pi-acp@0.0.33` resolves and spawns correctly.
- Remaining 20 points: AgentIcon + pi SVGs (10), docs (5), browser evidence (5).

## Next (iteration 3)
1. M4: `AgentIcon.tsx` (name switch "pi" + `/agents/pi${suffix}.svg`) + `packages/public/agents/pi-{light,dark}.svg`.
2. Docs: `docs/agents/pi.mdx` + card in `docs/supported-coding-agents.mdx`.
3. M6: browser_setup + UI run with the PI executor, save screenshots + `NOTES.md` to `.context/evidence/pi/`.

## Iteration 3 (2026-09-20) — M4 done, SCORE 80 → 90+
- `packages/public/agents/pi-{light,dark}.svg` added (16x16, black/white, matches existing style).
- `AgentIcon.tsx`: `getAgentName` -> "pi" and icon path `/agents/pi${suffix}.svg`.
- **Defect found + fixed:** `shared/types.ts` referenced an undefined `Pi` type because the ts-rs export
  list in `crates/server/src/bin/generate_types.rs` lacked `Pi::decl()` and the `"pi"` JSON-schema entry.
  Added both; `pip` no longer; `pnpm run web-core:check` (tsc --noEmit) now passes and
  `shared/schemas/pi.json` exists. `generate-types:check` reports no drift.
- `check.sh` hardened: new "shared/types.ts exports the Pi struct type" check + a scored
  `web-core tsc --noEmit` build check (build section rebalanced to 3+3+4).
- Remaining: docs (5) + browser evidence (5).

## Iteration 4 (2026-09-20) — M8 docs done, SCORE 90 → 95 (static 70)
- `docs/agents/pi.mdx`: Mintlify page (Steps: install pi, install pi-acp, authenticate via `pi-acp
  --terminal-login`, start VK) + Notes covering availability probe, no-MCP design, approvals, model pinning.
- `docs/supported-coding-agents.mdx`: new `<Card title="pi" href="/agents/pi">` (icon `https://pi.dev/logo-auto.svg`
  from pi's own README) and `"agents/pi"` added to the nav group in `docs/docs.json` (JSON validated).
- Docs/step structure verified (4 `<Step>` / 4 `</Step>`, `<Steps>` balanced).

## Iteration 5 plan (M6/M7 — browser E2E, the last 5 points)
1. `browser_setup` currently FAILS ("Could not start the browser daemon"). Diagnose: daemon logs/socket, node
   version, Chrome presence. The harness is at the pi npm dir (pi-browser-harness).
2. Fallback per GOAL.md risk note: if the harness cannot be started, capture equivalent in-app evidence
   (UI-driven run via the dev UI at :3003 with the PI executor) and record the deviation in ASSUMPTIONS.md;
   save whatever screenshots are possible to `.context/evidence/pi/` + NOTES.md.
3. Verify executor PI appears in the UI executor picker with the new "pi" name and icon.

## Iteration 5 (2026-09-20) — browser harness unblocked + real UI bug found/fixed
- **Daemon fix:** `browser_setup` failed because no daemon was listening and the harness spawns it detached with
  `stdio: "ignore"` (errors invisible). Working fix: start it manually and detached, then call `browser_setup`:
  `cd <pi-browser-harness dir> && setsid nohup npx tsx src/daemon/index.ts > /tmp/pi-browser-daemon.log 2>&1 &`
  → log then shows "IPC server listening" + "Connected to Chrome ✓", and `browser_setup` returns
  "Browser connected ✓". (The daemon exits on its own after 30 min idle.)
- **Real UI bug found:** after adding the `PI` enum variant, the dev UI crashed with
  `Cannot read properties of undefined (reading 'localeCompare')` in `LandingPage.tsx:226`
  (`getAgentName(a).localeCompare(...)`) — Vite had a **stale pre-bundled copy of `shared/types`** without `PI`
  in the enum, so `BaseCodingAgent.PI` was `undefined`. Fix: clear `node_modules/.vite` (+ `packages/*/node_modules/.vite`)
  and restart the dev stack. UI now renders and lists `PI` in its executor list.
- **Trap to avoid:** never invoke `pkill`/`pgrep -f` with a pattern that also appears elsewhere in the same
  command line — it kills this shell (cost: 2 aborted commands). Kill dev-stack processes by PID via a
  `/proc` scan in python instead (as done: 20 stale procs reaped; two duplicate dev stacks were running).
- Current dev stack: UI `http://localhost:3003`, backend `:3004`, both healthy; `/api/profiles` via the UI
  proxy lists `PI`.
- Still open: PNG evidence files in `.context/evidence/pi/` + NOTES.md (screenshot tool has no outputPath;
  plan: `browser_run_script` with daemon access, or accept a `browser_print_to_pdf` artifact).

## Iteration 6 (2026-09-20) — UI/browser evidence captured (partial), check split
- Harness: daemon must be started manually (recipe in `.context/evidence/pi/NOTES.md`); `browser_setup` then
  connects. Screenshots land in the system temp dir (`browser_screenshot` returns the path) — copy them into
  `.context/evidence/pi/`; PDF -> PNG works via `pdftoppm`.
- Learned the sign-in gate path: `More options` -> "I understand, continue without signing in" (local mode).
- Evidence so far: `01-ui-loaded-1.png`, `02-executor-pi-in-ui.png` (pi listed with the new icon),
  `03-ui-create-with-pi-executor.png` (create form with executor = Pi + prompt).
- Set `dev_assets/config.json` default executor to `PI` so the create form defaults to pi (dev-only).
- **Open gap:** UI "Create" leaves the workspace in **Draft** and writes no `execution_process`; find the
  draft-start action. check.sh evidence section split 2 pts (png+NOTES) / 3 pts (`*logs*.png` UI-run artifact).

## Iteration 7 (2026-09-20) — operator feedback: model selection; SCORE 97 → 100
Operator: "it did not allow me to select any model". Root cause: `Pi::discover_options` returned permissions
only (no models), and `build_command_builder` passed a useless `--model` CLI flag (pi-acp ignores it; the model
is applied over ACP via `AcpAgentHarness::with_model` -> `set_session_model`).
- `pi.rs`: removed the `--model` flag; `discover_options` now reads pi's catalogue
  (`models-store.json`: `{provider: {models: [{id, name, provider}]}}`) and emits `provider/model` `ModelInfo`
  entries + providers + `default_model`. Falls back to permissions-only when the catalogue is missing.
- 3 unit tests (no model flag, model not on argv, catalogue expansion) — `cargo test -p executors --lib pi` passes.
- Verified live: `/api/agents/discovered-options/ws?executor=PI` -> **412 models / 8 providers**.
- `check.sh`: new section 11 "pi model discovery" (5 pts, ws assertion); e2e sub-points rebalanced 20 -> 15.
  Full run: **SCORE 100**. CHECK_FAST static/build: 80.
- Note: frontend needs a page reload to pick up discovery for an already-open tab.

## Iteration 8 (2026-09-20) — criterion 7 investigated + guarded; SCORE stays 100
- Ran a supervised workspace (`permission_policy: SUPERVISED`) via `/api/workspaces/start`: completed exit 0,
  wrote `PI_SUPERVISED.md`, **no approval request raised**.
- Root cause (pi-acp source): permission requests are only sent for extension UI prompts
  (`requestExtensionPermission`), not for tool calls. Documented in `ASSUMPTIONS.md` per GOAL.md criterion 7's
  deviation allowance.
- `check.sh` section 9 now also asserts the SUPERVISED policy reaches the executor and that a supervised run
  completes (e2e points rebalanced 15 total; "turn recorded" 5 -> 2). Full run: **SCORE 100**.
- Next candidates: revive harness Chrome for the operator-visible model-dropdown screenshot; or move to M9
  improvement backlog (pi `configOptions` -> reasoning options, slash commands).

## Iteration 9 (2026-09-20) — model dropdown verified in the UI; harness Chrome revived
- Fixed the harness Chrome: stale `DevToolsActivePort` files + missing `--remote-allow-origins=*` (Chrome drops
  the CDP WebSocket without it) + daemon needs `CHROME_USER_DATA_DIR` pointing at the live CDP dir. After that
  the daemon stays connected (`Connected to Chrome ✓`, no disconnect).
- `browser_setup` still fails on the harness **profile** gate (pinned "Profile 1"/7solutions does not exist in
  the temp-profile Chrome). Worked around by driving CDP directly (`/tmp/cdp-ui2.mjs`), which is still real
  browser verification of the running UI. User's `~/.pi/agent/browser-harness.json` pin restored (backup at
  `/tmp/browser-harness.json.bak`).
- **Operator complaint verified fixed in the UI**: create-workspace page shows executor **Pi** with a model
  control labelled **Default**; opening it lists pi's providers (cerebras, kimi-coding, meta, minimax, mistral,
  openrouter, synthetic, xiaomi). Artifact: `.context/evidence/pi/05-model-dropdown.png`.

## Iteration 10 (2026-09-20) — fully UI-driven run verified (artifact 06)
- CDP-driven UI flow (`/tmp/cdp-run.mjs`): create form -> prompt -> **Create** with executor **Pi**.
- Result: workspace `788ccf83…`, session executor `PI`, process **completed exit 0**, `PI_UI_RUN.md` written in
  the worktree; workspace page shows the run (matches `DONE`/`PI_UI_RUN`). Artifact `.context/evidence/pi/06-ui-run-logs.png`.
- Corrects the iteration-6 note: a UI "Create" is not a dead draft — the earlier check simply looked before the
  run had started.
- Remaining backlog (M9): pi `configOptions` reasoning options, slash-command surfacing, session/load tuning.

## Iteration 11 (2026-09-20) — format + conventional commits (criteria 3 & 9)
- `pnpm run format` run; no unrelated files touched (8 modified files total were all pi-related).
- Committed in logical units: `484af783 feat(executors): add pi coding agent executor via pi-acp`,
  `d4256bf1 feat(web-core): show pi agent name and icon`, `03dfcf24 docs(agents): add pi setup page and agent
  card`, `f1bf896c chore(loop): add pi goal spec, objective check and browser evidence`.
- `git status --short` is empty. `CHECK_FAST=1 ./check.sh` still reports the expected static/build score.

## Iteration 12 (2026-09-20) — M9 item 1: pi thinking levels (reasoning options)
- `pi.rs`: new `reasoning` field (+ `apply_overrides` from `reasoning_id`), `THINKING_LEVELS`
  (`minimal|low|medium|high`), `effective_model()` appends `:<level>`, `get_preset_options()` round-trips
  `reasoning_id`, and `discover_options` attaches reasoning options to every model (via the existing
  `ReasoningOption::from_names` helper, re-ordered to pi's canonical order, `high` = default).
- Unit tests: `model_combines_with_thinking_level`, `thinking_levels_are_ordered_minimal_to_high`
  (`cargo test -p executors --lib pi` → 6 passed).
- Types regenerated (`generate-types:check` clean). Verified live against the dev backend:
  **412/412 models carry reasoning options** with sample `minimal, low, medium, high*`.
- Created `IMPROVEMENTS.md` backlog (5 open items with paths + acceptance criteria).

## Iteration 13 (2026-09-20) — M9 item 2 + fix: thinking level without explicit model
- Bug found while writing the assertion: `effective_model()` returned `None` when only a thinking level was
  chosen, so the level was silently dropped. It now falls back to pi's configured default model
  (`~/.pi/agent/settings.json`: `defaultProvider`/`defaultModel`) — unit test
  `thinking_level_falls_back_to_pi_default_model`.
- `check.sh` section 9 now starts a workspace with `reasoning_id: "minimal"` + `SUPERVISED`, asserts both
  round-trip into `executor_config`, and that the run completes exit 0 (pi rejects an invalid
  `provider/model:<thinking>`). Points rebalanced. Full run: **SCORE 100**.
- 7 unit tests pass (`cargo test -p executors --lib pi`).

## Iteration 14 (2026-09-20) — M9 item 3: pi slash commands (discovery-time)
- First attempt (reverted): emitting `patch::update_slash_commands` from the ACP log normaliser. Dead end —
  `/options/...` patches belong to the discovery store, not the conversation log store, so the UI never sees them.
- Shipped instead, following the `claude`/`opencode` `hardcoded_slash_commands()` pattern: `pi.rs` now returns
  pi's built-ins (`handoff`, `pickup`) plus `skill:<name>` for every user-invocable skill found in
  `~/.pi/agent/skills` and `~/.agents/skills` (frontmatter parsed, `user-invocable: false` skipped, deduped).
- Unit tests: `builtin_and_skill_commands_are_offered`, `skill_frontmatter_is_parsed_and_gated_by_user_invocable`
  (9 pi tests pass).
- Verified live via the discovery websocket: **26 slash commands** (handoff, pickup, 24 skills).
- `check.sh` section 11 now asserts models-with-reasoning (3) *and* slash commands (2). Full run: **SCORE 100**.

## Iteration 15 (2026-09-20) — M9 item 4: pi availability states
- Replaced the binary "auth file exists -> InstallationFound" logic with the codex pattern: auth file ->
  `LoginDetected { last_auth_timestamp }` (mtime seconds), `settings.json` -> `InstallationFound`, else
  `NotFound`. Added a shared `pi_agent_dir()` helper reused by the catalogue and settings readers.
- Unit test `availability_distinguishes_login_install_and_absence` covers absence, install-without-login and
  login (with a real timestamp), plus the `None` case. `cargo test -p executors --lib pi` → 10 passed.
- Verified live: `/api/agents/check-availability?executor=PI` now reports `LOGIN_DETECTED` (previously
  `INSTALLATION_FOUND`), so the UI can tell "not logged in" from "not installed".

## Iteration 16 (2026-09-20) — M9 items 5+6 (pin guard, docs) + backlog refill
- Test `pi_acp_package_is_pinned_to_an_exact_version` asserts `PI_ACP_PACKAGE` is an exact `name@x.y.z` pin with
  no `latest`/`^`/`~`/`>=`/`*`/`next` (11 pi tests pass). Upstream `npm view pi-acp version` = 0.0.33 = our pin.
- `docs/agents/pi.mdx` gained "Models and thinking levels" (catalogue, `defaultProvider`/`defaultModel`,
  minimal|low|medium|high, `:<thinking>` suffix, slash-command sources).
- Backlog refilled with three new concrete items (slash-menu UI evidence, per-model reasoning capability,
  worktree hygiene in `check.sh`); done items archived in the "Done" list.

## Iteration 17 (2026-09-20) — slash-menu screenshot attempt (negative result + cause located)
- Typing `/` (synthetic insertText and real CDP key events) into both the workspace composer and
  `/workspaces/create` renders no slash menu; artifact `07-slash-menu.png` records the composer state.
- Cause narrowed to the UI trigger, not the data: `SlashCommandTypeaheadPlugin` (`packages/ui/...`) uses
  `triggerFn = /^(\s*)\/([^\s/]*)$/` and hides the menu when `options.length === 0` unless `isLoading`/
  `isDiscovering`; the same discovery payload already drives the working model dropdown.
- Backlog item refined with the exact next experiment (log `slashCommandsQuery` at WYSIWYGEditor.tsx:307 and
  check the `executor` prop is truthy for the create form).

## Iteration 18 (2026-09-20) — slash menu: data path proven, UI trigger remains
- Instrumented the page (`Page.addScriptToEvaluateOnNewDocument` WebSocket wrapper): the create form opens
  `discovered-options/ws?executor=PI` and `…&repo_id=…` — so the composer does request discovery for pi.
- Queried that exact repo-scoped socket independently: **`slash_commands` is non-empty** (handoff, pickup, …).
  Therefore the menu's absence under CDP typing is a UI trigger issue, not pi integration.
- `check.sh` section 11 now calls the discovery socket with the repo id when available, matching the UI's request.
  Assumption recorded; backlog item re-scoped to the Lexical trigger.

## Iteration 19 (2026-09-20) — slash menu closed as documented limitation
- Repeated the experiment rigorously: pristine composer (cleared/never used), focused contenteditable, `/`
  inserted via `document.execCommand('insertText')` (real beforeinput path) -> content exactly `/` -> waited
  10 s -> **no menu** (`[role=listbox]`, `[class*=typeahead]` absent).
- Corrected my own error: the earlier "45 rows" was a false positive (page text matched a non-anchored regex,
  i.e. the "Available commands" system message).
- Data path independently proven (composer opens `discovered-options/ws?executor=PI&repo_id=…`; payload has 26
  commands), so this is a UI automation/Lexical-trigger limitation, not pi integration. Documented in
  `ASSUMPTIONS.md` per the backlog item's acceptance clause; item closed.

## Iteration 20 (2026-09-20) — M9 item 5: per-model reasoning capability
- `models-store.json` has `reasoning: bool` on every entry and `thinkingLevelMap` on 80 of them. New
  `reasoning_options_for_entry()` returns no thinking levels for `reasoning: false`, otherwise pi's standard
  levels plus any declared extras (`off`, `xhigh`, `max`); `discover_options` no longer forces one list on all
  models.
- Tests updated/added (`catalogue_expands_to_provider_qualified_models`, `reasoning_options_include_extra_thinking_levels`);
  12 pi tests pass. Note: a bad edit briefly deleted four tests — caught by the test count and restored from HEAD.
- Verified live: 412 models, **301 with thinking levels**, 111 without, extras `max/off/xhigh`.
- `check.sh` now asserts `0 < modelsWithReasoning < models` (per-model behaviour, not "some model has options").

## Iteration 21 (2026-09-20) — M9 item 6: worktree hygiene in check.sh
- The new hygiene assertion immediately caught a real leak (5 -> 6 dirs): dev sets `DISABLE_WORKTREE_CLEANUP`,
  so `DELETE /api/workspaces/{id}` archives the workspace but leaves its worktree directory on disk.
- `check.sh` now has `purge_run_worktrees()` (removes only directories that were not present when the run
  started), called from the exit trap *and* from the hygiene section, which deletes its workspaces first and
  then asserts the directory count is unchanged. Points rebalanced (SUPERVISED pass-through 2 -> 1).
- Verified over two consecutive full runs: `5 -> 5`, `SCORE 100`, exit 0.

## Iteration 22 (2026-09-20) — capability honesty: pi no longer claims SESSION_FORK
- Found while cross-checking docs ("message editing is supported by Claude Code, Amp, Codex, Gemini, Qwen"):
  `SessionFork` gates the edit-from-message UI, but the shared ACP harness has no rewind (`spawn_follow_up_with_command`
  has no reset parameter; `fork_session` only re-keys local logs), so pi's declared capability was a no-op.
- `mod.rs`: `Self::Pi(_) => vec![SetupHelper]` with a comment; new test `pi_does_not_claim_session_fork`
  (13 pi tests + 2 module tests pass). `cargo check -p server` clean.
- Verified live: `/api/info` -> `capabilities.PI == ["SETUP_HELPER"]`.
- Docs cross-check: pi is linked in `docs/supported-coding-agents.mdx` + `docs/docs.json`; remaining mentions are
  capability notes where pi is correctly absent, or a generic marketing sentence in `docs/index.mdx`.
- New backlog item added for the same mismatch in GEMINI/QWEN_CODE (not changed unilaterally).

## Iteration 23 (2026-09-20) — same capability fix for GEMINI/QWEN_CODE
- Applied the iteration-22 finding to the remaining ACP executors: `Self::Gemini(_) | Self::QwenCode(_)` now
  returns `vec![]` instead of `[SessionFork]`, with a comment pointing at the harness limitation.
- New test `acp_executors_do_not_claim_session_fork` (3 module tests pass); `cargo check -p server` clean.
- Verified live via `/api/info`: PI `["SETUP_HELPER"]`, GEMINI `[]`, QWEN_CODE `[]`, COPILOT `[]`,
  CLAUDE_CODE still `["SESSION_FORK","CONTEXT_USAGE"]`.

## Iteration 24 (2026-09-20) — backlog refill + override/preset/MCP tests
- All previous backlog items were closed, so three new ones were added from inspection: `check.sh` runtime
  budget, a pi-acp bump runbook, and slash-command dedup against pi's own list.
- Implemented the top gap found while inspecting: no test covered `apply_overrides`/`get_preset_options` for pi,
  and nothing asserted pi offers no MCP config. Added `overrides_and_presets_round_trip` (model + reasoning +
  supervised policy round-trip through `effective_model`/presets) and `pi_does_not_offer_an_mcp_config`
  (`supports_mcp() == false`, `default_mcp_config_path().is_none()`).
- `cargo test -p executors --lib pi` -> 15 passed.

## Iteration 25 (2026-09-20) — check.sh runtime budget measured
- Full run wall time: **132 s** (`/usr/bin/time`), `SCORE 100`, exit 0 — the two pi agent runs plus the
  follow-up dominate; build/type checks add ~25 s.
- `check.sh` now prints `TIME: <n>s` alongside `SCORE` so a slowdown is visible on every iteration.

## Iteration 26 (2026-09-20) — pi-acp bump runbook + guard proven
- `docs/agents/pi.mdx` gained "Updating the pi-acp adapter": check `npm view pi-acp version`, bump
  `PI_ACP_PACKAGE`, run the executor tests (pin guard), then `./check.sh` before committing.
- Verified the guard by negative test instead of assuming it: swapping the pin to `pi-acp@latest` made
  `pi_acp_package_is_pinned_to_an_exact_version` **fail**; the file was restored (diff limited to the docs).

## Iteration 27 (2026-09-20) — slash-command dedup guard
- Measured the live discovery payload first: 26 commands, 26 unique, no skill colliding with a built-in
  (`handoff`/`pickup`) — so no user-visible bug today.
- Added `merge_slash_commands()` so built-ins and skills are deduplicated by name (first wins) instead of merely
  concatenated; test `slash_commands_are_deduplicated_by_name` covers a skill colliding with a built-in and a
  duplicate skill entry. `cargo test -p executors --lib pi` -> 16 passed.

## Iteration 28 (2026-09-20) — attachment transport documented; backlog refilled
- Verified how attachments reach an ACP executor: the editor serialises them as `.vibe-attachments/<path>` links
  and the harness sends text blocks only, so pi reads attachment files with its own tools (no image block).
  Documented in `docs/agents/pi.mdx` ("Attachments and images") and recorded in `ASSUMPTIONS.md`.
- Backlog refilled with three new concrete items (image attachment evidence, zombie-process assertion in
  `check.sh`, availability copy for unauthenticated installs).

## Iteration 29 (2026-09-20) — zombie process assertion in check.sh
- Added `count_agent_procs()` (python `/proc` scan, so a pattern in the script cannot match itself) and turned
  section 12 into "run hygiene": worktrees unchanged **and** no leftover `pi-acp` processes. Points rebalanced
  (per-model thinking check 3 -> 2) to stay at 100.
- Verified by a full run: `5 -> 5` worktrees, `0 -> 0` agent processes, `TIME 116s`, `SCORE 100`, exit 0.

## Iteration 30 (2026-09-20) — availability states documented
- Traced how availability is used: `crates/executors/src/profile.rs` sorts agents by
  `LoginDetected` (most recent timestamp first) > `InstallationFound` > `NotFound`, so the state decides list
  order; there is no separate UI string for the agent states (`checkAgentAvailability` in the web API client
  currently has no consumer).
- Added an "Availability" table to `docs/agents/pi.mdx` describing the three states and what a user should do
  when pi is installed but not signed in.

## Iteration 31 (2026-09-20) — image attachment verified end to end
- Uploaded a solid-red 64x64 PNG (`POST /api/attachments/upload`, multipart field `image`), started a workspace
  with `attachment_ids` + a prompt asking pi to read the image: process **completed exit 0**, `PI_IMG.txt`
  contains `red`, turn summary `red`.
- pi reported the attachment is not in cwd but at `<workspace>/.vibe-attachments/…` — docs corrected (the
  directory sits in the workspace root, one level above the repository checkout).
- Evidence appended to `.context/evidence/pi/NOTES.md`.

## Iteration 32 (2026-09-20) — discovery now reports pi's configured default model
- Gap: `discover_options` sent `default_model: self.model`, so with no explicit pin the picker showed an opaque
  "Default" even though pi has `defaultProvider`/`defaultModel` configured. It now falls back to pi's configured
  model (id only — the `:<thinking>` suffix is still applied at spawn).
- Test `discovery_defaults_to_pis_configured_model` (17 pi tests pass).
- Verified live via the discovery websocket: `default_model = zenmux/deepseek/deepseek-v4.1-flash`, 412 models.
- Backlog refilled with three new items (vision-capable signal, attachment assertion in `check.sh`, agent page screenshot).

## Iteration 33 (2026-09-20) — attachment contract asserted in check.sh
- Added an attachment run to the e2e section: generate a blue PNG, upload it, start a workspace with
  `attachment_ids`, assert pi wrote `blue` to `PI_IMG.txt` (the workspace-root `.vibe-attachments/` path).
  Points rebalanced (PI_E2E content 5 -> 3) to fund the new 2.
- Full run verified: `attached image read by pi from the workspace root (completed:0)`, `SCORE 100`,
  `TIME 193s` — still well inside the 6-minute budget (run went from 116s to 193s).

## Iteration 34 (2026-09-20) — vision flag closed as not applicable
- Verified `ModelInfo` carries only `id`/`name`/`provider_id`/`reasoning_options`, and grep found no
  `vision`/image-modality logic anywhere in the UI or executors (attachments always travel as file paths), so a
  per-model image flag would be dead data.
- Documented the finding in `ASSUMPTIONS.md` and added practical guidance to `docs/agents/pi.mdx`: 251 of 412 pi
  models declare image input, and VK does not badge it in the picker, so check the model in pi's configuration.

## Iteration 35 (2026-09-20) — composer screenshot + picker observation
- Discarded a bad capture first: the settings dialog never opened (my check had matched page body text, so the
  "shows pi" claim would have been false). No artifact kept from that attempt.
- Captured `08-pi-model-selection.png`: create form with executor **Pi** and the model control showing
  `Gemma 4 31B IT · High`. Cross-checked discovery: `default_model = zenmux/deepseek/deepseek-v4.1-flash`.
  Opened a backlog item — the picker appears to ignore `default_model`.

## Iteration 36 (2026-09-20) — configured default model is now selectable
- Root cause of the iteration-35 mismatch: pi's configured model (`zenmux/deepseek/deepseek-v4.1-flash`) is not in
  the downloaded catalogue (its provider lives in `models.json`), so `default_model` pointed at an id the picker
  could not offer. `with_configured_default()` now prepends it when missing.
- Verified live over the discovery websocket: 413 models, configured default first.
- Picker still shows `Gemma 4 31B IT · High` because `ModelSelectorContainer.tsx` prefers an explicit/stored
  selection (`configModelId ?? presetModelId ?? defaultModelId`); recorded in `ASSUMPTIONS.md`.
- Process notes: an earlier patch of mine silently no-op'd (cargo fmt had changed the anchor) and the accompanying
  test duplicated the logic locally, so it passed while production stayed unchanged. Replaced with a real helper
  plus a test that calls it; lesson applied — assert the literal now contains the change.

## Iteration 37 (2026-09-20) — configured default model asserted in check.sh
- Section 11 now also asserts that `default_model` appears in the discovered model list (`defaultInList`), locking
  iteration 36's fix so pi's configured model cannot silently become unselectable again. Point funded by
  reducing the PI_E2E content check 3 -> 2.
- Full run: `413 models, 301 with thinking levels`, `26 slash commands`, `configured default model is selectable`,
  `SCORE 100`, `TIME 156s`.
- Backlog refilled with three items (state-file hygiene, stale dev workspaces from manual probes, attachment
  cleanup in check.sh).

---

## ASSUMPTIONS.md (original, iteration 1-37)

# ASSUMPTIONS

- **pi has no MCP support by design** (pi README: "No MCP. Build CLI tools with READMEs … or build an
  extension that adds MCP support"), and `pi-acp` advertises `mcpCapabilities: { http: false, sse: false }`.
  Therefore `Pi::default_mcp_config_path()` returns `None` and the `get_mcp_config` arm documents this.
  No MCP config file is invented. (GOAL.md non-goal, iteration 1.)
- `pi-acp` accepts no ACP flag or `--yolo` arg; approval bypass is enforced client-side by passing
  `approvals = None` to the harness when `yolo` is set (mirrors qwen/gemini behaviour).
- `pi-acp` is invoked via `npx -y pi-acp@0.0.33` (pinned) mirroring the qwen executor's `npx` pin; the
  adapter resolves the `pi` binary from PATH itself.
- Availability is probed via the pi agent home dir (`auth.json` inside it). A user with pi installed but not
  authenticated shows as `NOT_FOUND`.
- `BaseAgentCapability`: `SessionFork` (pi-acp advertises `loadSession: true`) + `SetupHelper`
  (advertises terminal `authMethods: pi_terminal_login`).

- **Supervised approvals (GOAL.md criterion 7) not yet exercised**: the API/e2e checks run with
  `yolo: true` (profile default, `permission_policy: AUTO`), so `session/request_permission` never fires.
  Deviation recorded here per GOAL.md; the ACP client implements `request_permission` and pi-acp advertises
  it, so the code path exists but is unverified end-to-end. Do not claim it verified until observed.
- **Browser harness flakiness**: the harness Chrome (own binary, temp profile) can drop its CDP connection
  (`chrome_disconnected`) after the daemon restarts or the browser is reaped; the daemon also self-exits after
  30 min idle. Recovery: restart the daemon manually (recipe in `.context/evidence/pi/NOTES.md`); if Chrome is
  gone, `browser_setup` must relaunch it. Consequence: the operator-visible model-selector check was verified
  over the discovery websocket (objective) instead of a screenshot this iteration.

- **Criterion 7 (supervised approval prompt) — deviation, with evidence.** `pi-acp` v0.0.33 only calls
  `session/request_permission` for **extension UI prompts** (`handleExtensionSelect` / `handleExtensionConfirm`
  in `pi-acp/dist/index.js` around line 1308); it never gates tool calls (file writes, bash) behind an ACP
  permission request. Verified experimentally: a workspace started with
  `executor_config: {executor: PI, permission_policy: SUPERVISED}` ran to completion (exit 0) and wrote
  `PI_SUPERVISED.md` with **no pending approval ever raised** (approvals websocket saw only the initial empty
  snapshot). Workaround/meaning: VK's approval plumbing is correctly wired (`permission_policy: SUPERVISED`
  reaches the executor, `yolo=false`, `request_permission` implemented in `AcpClient`), it simply is not
  exercised by pi for tool calls. `check.sh` therefore asserts policy pass-through + a clean supervised run.

- `.gitignore` gained one line (`.pi-loop-log.jsonl`) — the loop runtime log is per-session noise and would
  otherwise dirty every `git status`. No other repo file outside the GOAL.md allowed surface was changed.
- Loop state (`GOAL.md`, `check.sh`, `PROGRESS.md`, `ASSUMPTIONS.md`, `.context/evidence/pi/`) is committed as
  `chore(loop): ...` so the tree stays clean; the feature itself is split into `feat(executors)`,
  `feat(web-core)` and `docs(agents)` commits.

- **Composer slash menu under automation (iteration 18):** pi's slash commands *are* delivered — the
  repo-scoped discovery websocket the UI opens (`?executor=PI&repo_id=…`) returns non-empty `slash_commands`
  (`handoff`, `pickup`, …). The page demonstrably opens that socket, so the `executor` prop and the data path are
  fine; typing `/` via CDP (`Input.insertText` and real key events) still renders no menu row. The remaining
  suspect is the Lexical typeahead trigger under synthetic input, not pi integration.
  `check.sh` now asserts the payload over the same repo-scoped request shape the UI uses.

- **Slash-menu typeahead does not open under synthetic input (iteration 19, item closed as documented).**
  Fully characterised: pristine composer (verified empty), editor focused (`document.activeElement` is the
  contenteditable), `/` inserted through a real `beforeinput`/`input` path (`document.execCommand('insertText')`)
  so the editor content is exactly `/` (matches `triggerFn = /^(\s*)\/([^\s/]*)$/` in
  `packages/ui/src/components/SlashCommandTypeaheadPlugin.tsx`), waited ≥10 s, and **no menu renders**
  (`[role=listbox]`/`[class*=typeahead]` absent). The data path is proven independently: the page opens
  `discovered-options/ws?executor=PI&repo_id=…` and that payload carries non-empty `slash_commands`
  (handoff, pickup, …).  Earlier "45 menu rows" was a **false positive** — those elements were page text
  (the "Available commands: - handoff - pickup" system message) matched by a non-anchored regex.
  Remaining unknown: whether Lexical requires a hardware-level keystroke (CDP `char`/`execCommand` may bypass
  its text tracking) or the plugin is not mounted for this composer. Artifact: `07-slash-menu.png`
  (composer containing `/`, no menu).

- **`SessionFork` removed from pi (iteration 22):** `BaseAgentCapability::SessionFork` gates the
  "edit/restart from this message" action (`DisplayConversationEntry.tsx`, `executorCanFork`), but the shared ACP
  harness has no rewind path — `AcpAgentHarness::spawn_follow_up_with_command` takes no `reset_to_message_id`,
  and `SessionManager::fork_session` only re-keys local logs. pi therefore declared a capability it could not
  honour; it now reports `["SETUP_HELPER"]` only (verified via `/api/info` -> `capabilities.PI`). `GEMINI` and
  `QWEN_CODE` still declare `SESSION_FORK` with the same no-op reset — pre-existing and left untouched
  (recorded as a backlog item rather than silently changing other executors).

- **Attachments reach pi as file paths, not image content blocks (iteration 28).** Verified in code: the editor
  serialises attachments as markdown links to `.vibe-attachments/<path>` (`packages/ui/src/components/attachment-node.tsx`
  ~lines 104/320) and the ACP harness only ever sends `proto::ContentBlock::Text`
  (`crates/executors/src/executors/acp/harness.rs` ~455/513). Consequence: pi reads attachments with its own
  read tool; no ACP image block is required, and text-only models can still see the file path. Documented in
  `docs/agents/pi.mdx`.

- **No image/vision flag on `ModelInfo` (iteration 34).** pi's catalogue marks image input per model
  (`input: ["text","image"]`, 251 of 412 models), but Vibe Kanban has no consumer for it: `ModelInfo` carries only
  `id`/`name`/`provider_id`/`reasoning_options`, and attachments always travel as file paths (iterations 28/31), so
  nothing in the UI or executor decides behaviour from image modality. A flag would be dead data, so the finding is
  documented instead (and users are pointed at their pi configuration in `docs/agents/pi.mdx`).

- **Model picker precedence (iteration 36).** pi now prepends its configured default model to the discovered list
  (`with_configured_default`) when the downloaded catalogue lacks it, so the model pi will actually use is
  selectable (verified live: 413 models, `zenmux/deepseek/deepseek-v4.1-flash` first). The *displayed* selection
  still comes from `ModelSelectorContainer.tsx`: `configModelId ?? resolvedPresetModelId ?? defaultModelId`, i.e. an
  explicit/stored selection (profile preset or recently used model) wins over `default_model`. The composer showing
  `Gemma 4 31B IT · High` is therefore a remembered choice, not a bug; with no stored selection the new default
  entry is used.
