# ASSUMPTIONS

Decisions taken without asking the operator, each backed by evidence in the entry below. Older, superseded
evidence lives in `notes/loop-history.md`.

## Index

1. pi has no MCP support by design
2. pi-acp accepts no ACP flag or --yolo arg
3. pi-acp is invoked via npx -y pi-acp@0.0.33
4. Availability is probed via the pi agent home dir
5. BaseAgentCapability: SessionFork
6. Supervised approvals
7. Browser harness flakiness: the harness Chrome
8. Criterion 7
9. .gitignore gained one line
10. Loop state
11. Composer slash menu under automation
12. Slash-menu typeahead does not open under synthetic input
13. SessionFork removed from pi
14. Attachments reach pi as file paths, not image content blocks
15. No image/vision flag on ModelInfo
16. Model picker precedence
17. Docs page is validated structurally, not rendered
18. Fresh-checkout verification is partial
19. Fresh-checkout verification complete

## Entries

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

- **Docs page is validated structurally, not rendered (iteration 44).** There is no local Mintlify toolchain (`docs/`
  has no package.json, no `docs:*` scripts, no `mintlify` dependency or CLI), so a rendered-docs screenshot is not
  achievable offline. `check.sh` therefore validates `docs/agents/pi.mdx` objectively: YAML frontmatter with
  `title`/`description`, balanced `<Steps>`/`<Step>` tags, and parseable `docs/docs.json`.

- **Fresh-checkout verification is partial (iteration 45).** A detached worktree of `2860fd98` compiled
  `cargo check -p executors` from scratch in a separate `CARGO_TARGET_DIR` successfully (6m06s, no reliance on the
  repo's target dir, `dev_assets`, or untracked files; `git status` in the worktree was clean). Re-running the unit
  tests there failed with `Disk quota exceeded (os error 122)` — `/tmp` is a 7.3 GB tmpfs and the second target dir
  (4.6 GB) exhausted it, not a code failure. The test target dir was deleted and the worktree removed; the dev stack
  stayed healthy (backend 200). Re-verifying tests without the shared target needs a larger scratch filesystem.

- **Fresh-checkout verification complete (iteration 47).** With the scratch `CARGO_TARGET_DIR` on the repo disk
  (234 GB free) instead of `/tmp` (7.3 GB tmpfs), a detached worktree of `0d670bea` built cold and ran
  `cargo test -p executors --lib pi` → **18 passed** in 9m09s, after the earlier cold `cargo check -p executors`
  (6m06s). The iteration-45 quota failure was environmental, now closed and cleaned up (4.8 GB scratch dir removed).

- **Follow-ups replay context instead of resuming pi's ACP session (iteration 51).** Verified in
  `crates/executors/src/executors/acp/harness.rs` (~lines 340-370): on a follow-up the harness forks the *local*
  session log, calls `conn.new_session(...)` (always a fresh ACP session — pi-acp's advertised `loadSession: true`
  is never used), passes the prior history through the new-session `meta`, and sends a locally generated
  `resume_prompt`. This is shared ACP behaviour (not pi-specific), it explains why follow-ups still answer from
  earlier context, and it means prompt cost grows with session length. Changing it would alter the shared harness for
  every ACP executor, so it is documented rather than modified; a backlog item tracks the possible optimisation.

- **First-run (fresh `dev_assets`) verification, iteration 52.** Moved `dev_assets` aside, let the stack recreate it
  (config.json, db.sqlite, db.v2.sqlite, dev.db, signing key) and ran the full check against that clean install:
  **SCORE 100**, 39 checks, 143 s, ending with 0 workspaces and 0 attachments — so nothing depends on accumulated
  local state and the harness leaves no residue. The original `dev_assets` was restored afterwards and the dev stack
  restarted (2 workspaces back, backend healthy). The procedure is manual (≈4 min) and tracked as a backlog item.

- **Missing pi catalogue degrades gracefully (iteration 56).** With `~/.pi/agent/models-store.json` moved aside,
  discovery logs `pi model catalogue unavailable at <path> (...); run \`pi update\` ...` and returns the configured
  default model only (models: 1 instead of 413) — so the picker is never empty and the executor stays usable. Restoring
  the file returns 413 models. Added the reader's warning + a docs hint; the warning path is hand-verified because it
  requires manipulating the user's home directory.

- **`SETUP_HELPER` for pi is informational today (iteration 61).** Verified there is no consumer: grepping `SETUP_HELPER`
  across `packages/web-core`, `packages/ui`, `packages/local-web`, `crates/server` and `crates/services` yields nothing
  (only the `SETUP_HELPER_NOT_SUPPORTED` error string exists, and that belongs to the GitHub CLI dialog). Codex and
  Cursor implement the helper end-to-end (`codex_setup.rs` / `cursor_setup.rs` build a `codex login`-style script and run
  it), while `get_setup_helper_action` defaults to `SetupHelperNotSupported` — pi keeps the capability because its login
  step is real, and the verified command is `pi-acp --terminal-login` (re-read from the live ACP `initialize` response:
  `authMethods[0] = { id: pi_terminal_login, type: terminal, args: ["--terminal-login"] }`). No user-visible effect today;
  wiring it (executor method + route + frontend) is tracked as a backlog item instead of writing unused code.

- **How the pinned adapter resolves (iteration 62).** `npx -y pi-acp@0.0.33` completed in ~3 s and created no `~/.npm/_npx`
  entry, i.e. npx used the globally installed adapter rather than downloading it; without a matching global install npx
  fetches the version on first use. Documented in `docs/agents/pi.mdx` (adapter-resolution step + a global install is the
  predictable setup). Typical run latency, measured from `execution_processes.started_at`/`completed_at`: 19 s and 32 s for
  two recent pi runs.

- **Non-`main` default branches work (iteration 63, hand-verified).** The suite always initialises its scratch repo with
  `-b main`, so a repo whose default branch is `master` was tested separately: `target_branch: master` produced a workspace
  on `vk/b775-pi-master`, pi ran to **completed:0**, and `MASTER_OK.txt` contained `MASTER-OK`. Cleanup removed the worktree
  and repo (baseline restored to 2 worktrees). Not automated because it exercises upstream branch handling rather than the
  pi executor.

- **Stopping a running pi agent works cleanly (iteration 64, hand-verified).** `POST /api/execution-processes/{id}/stop`
  during a live pi run returned success, the process moved to **`killed`** (`exit_code: None`) and the spawned `pi-acp`
  child was gone afterwards (0 processes, baseline 0; 1 while running). Worktrees stayed at the baseline of 2 after
  deleting the workspace. Measurement note: an ad-hoc shell count of "pi-acp" processes reports false positives because
  the counting command itself contains the literal, so counts exclude the current process tree (the pattern used in
  `check.sh`'s `count_agent_procs`).

- **`append_prompt` reaches pi (iteration 65, hand-verified).** With `dev_assets/profiles.json` setting
  `PI.DEFAULT.append_prompt = "\n\nAlso reply with the exact token APPENDED-OK on its own line."` and a workspace prompt of
  "Reply with the single word DONE.", the turn summary was exactly `DONE\n\nAPPENDED-OK` — so the profile suffix is applied
  verbatim (no separator is inserted; `AppendPrompt::combine_prompt` concatenates prompt + suffix). Profile file removed and
  the stack restarted afterwards (`append_prompt: null` back on the default profile). Not automated because it needs a profile
  override plus a restart, which would slow every check run.

- **Repo setup scripts run before pi starts, and pi sees their output (iterations 66-67, verified).** With
  `setup_script = "echo SETUP-RAN-3 > SETUP_MARKER3.txt"` the session produced `setupscript -> completed:0` then
  `codingagent -> completed:0`, and the agent's summary was exactly `SETUP-RAN-3` (it read the marker the script wrote).
  API detail for future probes: `POST /api/workspaces/start` returns the **setup** process (action type `ScriptRequest`) when
  the repo has a setup script, not the coding agent - poll the session's `codingagent` row instead. My first two attempts
  watched the wrong process and cut the run short.

- **Project-local pi skills are gated on trust (iteration 74, verified).** pi's README lists skill locations as
  `~/.pi/agent/skills`, `~/.agents/skills`, `.pi/skills` and `.agents/skills` (from cwd up), but project-local resources are
  only loaded when the folder or a parent is trusted in `~/.pi/agent/trust.json`. Experiment: a probe repo with
  `.agents/skills/demo-skill/SKILL.md` announced 31 commands over ACP and **not** `skill:demo-skill`, while the global
  skills were present. Vibe Kanban creates worktrees under `/var/tmp`, which are untrusted, so `skill_dirs()` now includes a
  project's skill directories only when `project_is_trusted()` finds the path (or an ancestor) in that file — otherwise the
  picker would offer commands pi refuses. Unit test asserts only the two global directories are used without trust.

- **No hardcoded pi commands (iteration 75).** `handoff`/`pickup` are **not** pi core: they are absent from pi's README
  command table and from its bundle (`grep` finds no occurrence), and they came from optional packages installed in this
  environment, which is why the ACP session announced them. Hardcoding them would advertise commands a fresh installation
  cannot run, so `pi_slash_commands()` now returns only installed skills (trust-gated), and pi's own/extension commands are
  left to the runtime ACP announcement. Unit test asserts nothing but `skill:*` entries are returned.

- **pi's thinking levels are off/minimal/low/medium/high (+ per-model xhigh/max) — iteration 76.** `pi --help` documents
  `--thinking <level>` as "off, minimal, low, medium, high, xhigh, max", so the base set now includes `off`
  (`THINKING_LEVELS`), and `xhigh`/`max` stay model-specific via the catalogue's `thinkingLevelMap`. Verified live:
  301 reasoning-capable models expose `off, minimal, low, medium, high*` (high default), and a map-carrying model
  (`cerebras/gemma-4-31b`) exposes all seven.

- **Model discovery now uses `pi --list-models` (iteration 77).** The downloaded catalogue listed 413 models including
  providers without credentials; pi's own `--list-models` (documented in its `docs/models.md`) returns 236 for this
  installation, with `thinking`/`images` columns. Discovery now prefers that CLI view, merging per-model `xhigh`/`max`
  levels from the catalogue where it declares them, and falls back to the catalogue file when `pi` cannot run.
  Verified live: 236 models, 173 with thinking levels, base order `off, minimal, low, medium, high*`,
  `kimi-coding/k3` carrying all seven levels, and the configured default model still selectable.

- **Model and thinking selection are currently no-ops for pi (iteration 78, protocol-verified).** Probes against `pi-acp`
  0.0.33: `session/set_model` -> `Method not found` (not implemented), while `session/set_config_option` works —
  `session/new` advertises config options **`model`** (233 entries) and **`thought_level`** (6, current `high`), and setting
  `{configId: "model", value: "kimi-coding/k3"}` succeeds. The `provider/model:<level>` form is rejected
  (`pi set_model failed: Model not found`) because the `:<thinking>` shorthand is a pi CLI nicety, not an ACP value. The
  shared ACP harness applies models via `set_session_model`, so for pi the selection never reaches the agent: the picker and
  the request config are honest, the agent is not. `check.sh` assertion wording now says "accepted by the API"/"recorded on
  the request" rather than "passed through to the executor", and the docs carry a limitation note. Fix tracked as a backlog
  item: apply the model via `set_config_option(model)` and the level via `set_config_option(thought_level)`.

- **Why the pi model/thinking fix is blocked on the protocol crate (iteration 79).** `agent-client-protocol` 0.8.0, which the
  executors crate pins, has no config-option support: `ConfigOption` appears nowhere in its source and
  `SetSessionConfigOptionRequest` does not exist, while 0.11.1 (already in the local registry) implements it. The crate's
  only escape hatch, `ext_method`, carries fixed method names from its schema, so a raw `session/set_config_option` cannot be
  sent on 0.8. An attempted harness change was reverted to keep the tree green; the two viable paths (crate bump plus ACP-layer
  migration, or dropping the picker promises for pi) are recorded in `IMPROVEMENTS.md`.

- **`/skill:<name>` invokes pi skills over ACP (iteration 83, verified).** A temporary skill (`zz-probe-marker`) whose
  SKILL.md instructs pi to reply with the token `SKILL-MARKER-OK` was created under `~/.agents/skills`, then a workspace was
  started with the prompt `/skill:zz-probe-marker`: pi completed and the turn summary was exactly `SKILL-MARKER-OK`. So the
  commands Vibe Kanban lists are not just announcements — sending one as the prompt actually invokes the skill (which is why
  iteration 75 removed the non-core `handoff`/`pickup` entries). The probe skill was deleted afterwards and the worktree
  count returned to its baseline of 2.

- **Protocol-crate migration scope, corrected (iteration 84).** Iteration 82's read of the compiler output ("127 errors, all
  moved type paths") was optimistic: after a bulk `proto::X` -> `proto::schema::X` rewrite brought it to 36 errors, the
  remainder turned out structural. 0.11 dropped `ClientSideConnection` (no reference anywhere in its source) and the `Client`
  trait the harness is built on, replacing them with a `Role`/`Component`/`Builder`/`Handles` design; the crate's latest is
  now 2.x. Migrating therefore means rewriting the ACP connection and dispatch layer, not import bookkeeping, so pi's model
  selection stays hidden (iteration 80) until that work is scheduled deliberately. The scratch worktree and its target dir
  were removed; the repo was never modified.

- **The UI still works with the model list hidden (iteration 85, verified).** After iteration 80 stopped advertising models for pi,
  a full UI-driven run was performed against the current build (CDP: open `/workspaces/create`, type the prompt, click Create):
  workspace `25234873-...` produced two processes — setup script and coding agent — both **completed, exit 0**, with the agent
  turn summary `DONE`. So an empty model selector leaves the create form and the run flow intact; the workspace and its worktree
  were deleted afterwards (baseline 2 worktrees).

- **pi clamps or ignores a requested thinking level, per model (verified).** Asking the adapter for `kimi-coding/k3:minimal`
  makes pi report `low`, and `kimi-coding/k3:off` leaves the level at `high` — pi applies its own support map for the chosen
  model. `:low` on the same model is applied as asked, and `zenmux/deepseek/deepseek-v4.1-flash:minimal` is applied as asked.
  So Vibe Kanban can request a level but cannot promise it; `check.sh` §14 therefore asserts the level on a model/setting pi
  does honour, and the UI/documentation must not promise more.
- **The chosen model really does reach pi (verified, iteration 4).** A workspace started through the API with
  `model_id: kimi-coding/k3` and `reasoning_id: low` produced this in pi's own session log
  (`~/.pi/agent/sessions/<cwd>/<ts>.jsonl`): `model_change zenmux/deepseek/deepseek-v4.1-flash -> kimi-coding/k3` followed by
  `thinking_level_change high -> low`. Before the fork this was impossible: the adapter answered `Method not found`.

- **Model ids are provider-relative; the UI composes `provider_id/id` (iteration 6, fixed).** Vibe Kanban's model selector
  builds the id it sends as `provider_id + '/' + model.id` (`ModelSelectorContainer.handleModelSelect`) and matches
  `default_model` against `provider_id/id` (`resolveDefaultModelId`), exactly as `opencode.rs` does it. pi's discovery was
  emitting **provider-qualified** ids *and* a `provider_id`, so the create form sent `kimi-coding/kimi-coding/k3`, which pi
  rejected and replaced with its configured default — the model choice was silently dropped. Discovery now emits bare ids
  (`k3`) with `provider_id: kimi-coding`, `default_model` stays provider-qualified, and `check.sh` §11 fails if an id ever
  repeats its provider again. Verified end to end: a UI-created run now logs `model_change -> kimi-coding/k3` in pi's session.
