# IMPROVEMENTS (pi executor backlog)

Each item: affected paths + one-line acceptance criterion. Take the top open item, implement, mark it done.

## Done

- [x] **Thinking levels for pi models** — `crates/executors/src/executors/pi.rs`. `discover_options` emits
      `minimal|low|medium|high` (default `high`) per model and `effective_model()` appends `:<level>`; verified
      live: 412/412 models carry reasoning options. (iteration 12)
- [x] **Thinking level without an explicit model** — `crates/executors/src/executors/pi.rs`. `effective_model()`
      falls back to pi's configured default model (`settings.json`) so a level is never silently dropped. (13)
- [x] **Reasoning id end-to-end assertion** — `check.sh`. Starts a workspace with `reasoning_id: "minimal"` and
      asserts the config round-trips and the run completes exit 0. (13)
- [x] **Slash commands from pi** — `crates/executors/src/executors/pi.rs`. Built-ins (`handoff`, `pickup`) plus
      `skill:<name>` from `~/.pi/agent/skills` and `~/.agents/skills`; verified live: 26 commands. A runtime
      route through the ACP normaliser was tried and reverted (option patches never reach the discovery store). (14)
- [x] **Availability: installed but unauthenticated** — `crates/executors/src/executors/pi.rs`. Codex-style
      `LoginDetected { last_auth_timestamp }` / `InstallationFound` / `NotFound`; verified live. (15)
- [x] **pi-acp version drift guard** — `crates/executors/src/executors/pi.rs`. Test asserts `PI_ACP_PACKAGE` is
      an exact `name@x.y.z` pin (no `latest`/range wildcards). Upstream is also pinned to the same `0.0.33`. (16)
- [x] **Docs: model/thinking selection** — `docs/agents/pi.mdx`. Page documents the model catalogue, the
      `minimal|low|medium|high` levels, the `:<thinking>` suffix and where slash commands come from. (16)

## Open

- [ ] **Bump `agent-client-protocol` 0.8 -> 0.11, then apply pi's model/thinking via config options** —
      `crates/executors/Cargo.toml`, `crates/executors/src/executors/acp/harness.rs`,
      `crates/executors/src/executors/pi.rs`.
      Feasibility verified (iteration 81): 0.11.1 exports `SetSessionConfigOptionRequest`/`Response`
      (`agent-client-protocol-0.11.1/src/schema/client_to_agent/requests.rs:5`), which 0.8.0 has nowhere, and the registry
      resolves the version (`cargo add agent-client-protocol@0.11.1 --dry-run -p executors` lists features including
      `unstable_session_model`, `unstable_session_fork`, `unstable_boolean_config`). Plan: bump the dependency + enable the
      `unstable_*` features the ACP layer needs, fix the compile fallout in `harness.rs`/`acp/client.rs`/`mod.rs`, then
      `session/set_config_option(model)` + `(thought_level)` after `session/new`, flip `MODEL_SELECTION_SUPPORTED` to true,
      and let `check.sh`'s "model selection is not advertised" assertion fail as the reminder to restore the model/thinking
      assertions.
      **Scope corrected after attempting it (iterations 82-84).** A bulk path rewrite (`proto::X` -> `proto::schema::X`)
      cleared 127 errors down to 36, but the rest are structural, not cosmetic: 0.11 has **no `ClientSideConnection`** (the
      convenience connection the harness is built on — 0 references in its source) and no `Client` trait; it is a redesign
      around `Role`/`Component`/`Builder`/`Handles`. So the bump means rewriting the ACP connection + dispatch layer for
      every ACP executor, not fixing imports. (The crate's latest is 2.x, so a future migration would likely target that.)
      The dormant path itself is verified (iteration 87): flipping `MODEL_SELECTION_SUPPORTED` to true in place made live
      discovery return **236 models, 173 with thinking levels**, `off, minimal, low, medium, high*`, `kimi-coding/k3` carrying
      all seven levels and the configured default present in the list — so the flag flip is the only missing piece once the
      layer is migrated (`cargo test -p executors --lib pi`: 22 passed with the flag on and off).
      Risks: Cargo.lock churn, a crate fetch, and gemini/qwen/copilot share this layer but cannot be tested end to end here —
      deliberately left for a scoped session rather than a loop-tail edit (the scratch worktree and its 1.7 GB target were
      removed; the repo was never modified).
- [x] **Setup-script coverage inside `check.sh`** — `check.sh`.
      Done in the documented order: main (iteration 69), supervised (70), concurrency + attachment (71) blocks now resolve the
      `codingagent` process from the session, then the shared repo gained a real setup script. The supervised block also reads
      its `executor_config` from the coding-agent process (the start response describes the setup process). Verified:
      **`SCORE 100`**, 41 checks, `TIME 155s`, including `repo setup script ran before pi (marker present)`.
      (iterations 68-71)

- [ ] **Wire pi's setup helper end-to-end (only if the UI starts using it)** — `crates/executors/src/executors/pi.rs`,
      `crates/server/src/routes/workspaces/`, `packages/web-core/src/shared/lib/api.ts`.
      `SETUP_HELPER` has no consumer today, so nothing is broken; the verified login command is
      `pi-acp --terminal-login`. Acceptance: pi gains `get_setup_helper_action` (bash script, mirroring
      `codex_setup.rs`) plus a route and a frontend caller, with a test asserting the script contains the pinned
      adapter and `--terminal-login`; or the capability is dropped if the UI never surfaces it.

- [x] **Evidence freshness is asserted, not the artifact's content** — `.context/evidence/pi/`.
      Re-captured `06-ui-run-logs.png` against the current build (after the capability change removed pi's
      edit-from-message affordance) and recorded why in `NOTES.md`; the freshness guard stays green, so the remaining
      risk (a screenshot that is new but wrong) is explicitly acknowledged in the note. (iteration 59)

- [x] **Catalogue reader is unit tested** — `crates/executors/src/executors/pi.rs`.
      Extracted `read_catalogue_from(path)` (the warning path lives there) and added
      `catalogue_reader_handles_missing_valid_and_broken_files` covering valid, malformed and absent files; the
      end-to-end degradation was still hand-verified with the real catalogue moved aside. 19 tests pass. (iteration 57)

- [x] **Negative controls re-measured; section headers de-numbered** — `notes/negative-controls.md`, `check.sh`.
      After the point rebalance the controls were re-run (baseline 82, evidence removed 77, POC hack 78, restored 82) and
      the table updated. Section headers no longer carry point totals (they had drifted: the hack header still said 5
      while awarding 4) and the matching NO messages were corrected. Full run: `SCORE 100`, 141 s. (iteration 60)

- [x] **First-run verification, automated** — `check.sh --fresh-state`.
      The check refuses to run while a backend is healthy, then moves `dev_assets` aside, starts its own backend,
      runs every assertion against the clean install and restores the directory in its exit trap. Verified:
      `SCORE 100`, `TIME 157s`, `dev_assets` restored (6 files, 2 workspaces). Guard fires before any section output.
      (iterations 52+54)

- [ ] **Consider ACP `session/load` for follow-ups** — `crates/executors/src/executors/acp/harness.rs`.
      The harness always calls `new_session` and replays a locally composed prompt, while pi-acp advertises
      `loadSession: true`. Acceptance: either the harness resumes when the agent advertises `loadSession` (with the
      follow-up check still green for pi, gemini and qwen), or `ASSUMPTIONS.md` records why replay is preferred
      (e.g. uniform behaviour across ACP executors).

- [x] **Concurrency assertion in `check.sh`** — `check.sh`.
      The check now starts two workspaces together on the same repo and requires both to complete with their own
      file and no leakage from the other (`CONC_c1.txt`/`CONC_c2.txt`). Verified: `SCORE 100`, `TIME 157s`.
      First version had a parsing bug of mine — the verdict split `completed:0` on its colon, so it reported `bad`
      while the evidence line was perfect; now the python block returns JSON and the shell reads its `ok` field.
      (iterations 48+50)
      After 48 iterations, re-read each claim and correct anything now stale (e.g. evidence paths, counts, or
      statements superseded by later findings).

- [x] **Verify without the shared Cargo target — done** — clean worktree at `0d670bea`, scratch
      `CARGO_TARGET_DIR` on the repo disk (not `/tmp`, whose 7.3 GB tmpfs caused the earlier quota failure).
      Cold `cargo check -p executors` **6m06s** and cold `cargo test -p executors --lib pi` **18 passed, 9m09s**,
      with no reliance on this repo's `target/`, `dev_assets/` or untracked files. Scratch dir (4.8 GB) removed;
      dev stack healthy. (iterations 45+47)
- [x] **`check.sh` TIME history** — `check.sh`, `notes/check-timings.tsv` (gitignored).
      Every run now appends `timestamp<TAB>seconds<TAB>score` and prints the last three so drift is visible; verified
      with a fast run (35 s / 82) followed by a full run. (iteration 46)

- [x] **Attachment answer is intermittent — root-caused and fixed** — `check.sh`.
      The real cause was the check's shell-built JSON payload (multi-sentence prompt escaped inside a double-quoted
      `-d` argument): pi received a mangled/empty prompt, so nothing ran. The whole attachment flow now runs from a
      python block (`json.dumps` payload, polling, turn lookup, cleanup) like the verified manual probe.
      Two consecutive full runs report `file 'blue'`. (iteration 42)
- [x] **Loop archive rotation** — `notes/README.md`, `notes/loop-history-001-042.md`.
      Rotation rule documented (rotate past ~500 lines into `loop-history-<first>-<last>.md`); iterations 1-42 were
      moved to `loop-history-001-042.md` (456 lines) and a fresh window opened with an index in `notes/README.md`.
      `PROGRESS.md` now points at the index. (iteration 43)
- [x] **Docs page validation (replaces the impossible screenshot)** — `check.sh`, `ASSUMPTIONS.md`.
      No local Mintlify toolchain exists, so rendering the page offline is impossible; the check now validates
      frontmatter, balanced `<Steps>`/`<Step>` tags and `docs.json` instead. The first run of the validator reported a
      false "unbalanced tags" (it counted `<Steps>` as `<Step`) — fixed by matching `<Step ` exactly. (iteration 44)

      Both prose files have grown past 150 lines of iteration history. Acceptance: an `## Archive` (or a
      `notes/` split) keeps the top of each file scannable — current state and open items within the first screen
      — without losing the recorded evidence.
- [x] **Stale dev workspaces from manual probes** — dev database, `/var/tmp/vibe-kanban-dev/worktrees`.
      Deleted `pi-poc`, `pi-supervised`, `pi-slash`, `pi-image` via `DELETE /api/workspaces/{id}` (HTTP 202) and
      removed their worktrees; the operator's `summarize me stack use` and the UI-evidence run `788c-…` were kept
      deliberately. Worktrees went 6 -> 2; `CHECK_FAST` still `SCORE 81`. (iteration 40)
- [x] **`check.sh` attachment cleanup + deterministic assertion** — `check.sh`.
      The run now deletes its upload (`DELETE /api/attachments/{id}`) and removes the stored file; attachment rows
      stayed at 1 across two consecutive runs with `.vibe-attachments/` empty. The assertion was also made
      deterministic (prompt constrains the answer to `red|green|blue|yellow`; the check compares the trimmed file
      content and prints it on failure) after a run failed on the model's free-form wording. (iteration 39)

- [x] **Vision-capable model signal — closed as not applicable** — `ASSUMPTIONS.md`, `docs/agents/pi.mdx`.
      Verified there is no consumer: `ModelInfo` has no modality field and grep found no `vision`/image-capability
      logic in the UI or executors (attachments are paths). Documented the finding plus the practical fact
      (**251 of 412** pi models declare image input) so users know to check their pi config. (iteration 34)
- [x] **Attachment path assertion in `check.sh`** — `check.sh`.
      The e2e section now generates a blue PNG, uploads it (`POST /api/attachments/upload`), starts a workspace
      with `attachment_ids` and asserts pi wrote `blue` to `PI_IMG.txt` — locking the workspace-root
      `.vibe-attachments/` contract. Full run: `SCORE 100`, 193s (budget 6 min). (iteration 33)
- [x] **pi composer evidence screenshot** — `.context/evidence/pi/08-pi-model-selection.png`, `NOTES.md`.
      Captured the create form showing executor **Pi** and the model button on a concrete model + thinking level.
      The settings-dialog capture was discarded (the dialog never opened; the text check had matched page content).
      (iteration 35)
- [x] **Picker ignores `default_model` — resolved** — `crates/executors/src/executors/pi.rs`, `ASSUMPTIONS.md`.
      Two causes: (1) pi's configured model (`zenmux/…`) was absent from the downloaded catalogue, so the picker
      could not select it at all — fixed by `with_configured_default()` prepending it (verified live: 413 models,
      default first); (2) the picker deliberately prefers a stored selection
      (`configModelId ?? presetModelId ?? defaultModelId`), which is why the composer still shows the remembered
      `Gemma 4 31B IT · High`. Rule recorded in `ASSUMPTIONS.md`. (iteration 36)

- [x] **Image attachment end-to-end evidence** — `.context/evidence/pi/NOTES.md`, `docs/agents/pi.mdx`.
      Uploaded a solid-red PNG, started a pi workspace with `attachment_ids`; process completed exit 0,
      `PI_IMG.txt` = `red`, turn summary `red`. Also corrected the docs: attachments live in the workspace root
      (one level above the repo checkout), not in cwd. (iteration 31)
- [x] **Zombie process assertion in `check.sh`** — `check.sh`.
      Section 12 is now "run hygiene" (2 pts): worktree count *and* `pi-acp` process count must not grow across a
      run (`count_agent_procs()` scans `/proc`, avoiding the self-matching `pgrep` trap). Verified: `0 -> 0`.
      Points rebalanced (model check 3 -> 2). (iteration 29)
- [x] **Availability copy for unauthenticated installs** — `docs/agents/pi.mdx`.
      Added an "Availability" table for `LOGIN_DETECTED` / `INSTALLATION_FOUND` / `NOT_FOUND`, derived from
      `profile.rs` sorting (login first, most recent first; install-without-login listed below; nothing else
      offered) and the states `availability_info()` reports. (iteration 30)

- [x] **`check.sh` runtime budget** — `check.sh`.
      Measured full run: **132 s** (well under the 6 min budget) with `SCORE 100`. The script now prints
      `TIME: <n>s` next to the score so regressions are visible on every run. (iteration 25)
- [x] **pi-acp bump runbook** — `docs/agents/pi.mdx`, `crates/executors/src/executors/pi.rs`.
      Docs gained an "Updating the pi-acp adapter" section (`npm view pi-acp version` -> bump `PI_ACP_PACKAGE` ->
      tests -> `./check.sh`). The guard was **proven by negative test**: temporarily setting `pi-acp@latest`
      makes `pi_acp_package_is_pinned_to_an_exact_version` fail; the file was restored afterwards. (iteration 26)
- [x] **Slash-command dedup with pi's own list** — `crates/executors/src/executors/pi.rs`.
      Live payload was already clean (26 commands, 26 unique, no skill colliding with a built-in), but the
      concatenation had no cross-check; `merge_slash_commands()` now keeps the first entry per name and the test
      `slash_commands_are_deduplicated_by_name` covers built-in/skill and duplicate-skill collisions. (iteration 27)

- [x] **ACP executors claim `SESSION_FORK` without rewind** — `crates/executors/src/executors/mod.rs`.
      Dropped for `GEMINI`/`QWEN_CODE` (the ACP harness has no reset path, so it was a no-op that enabled the
      edit-from-message UI). Verified live: `capabilities.GEMINI == []`, `QWEN_CODE == []`, while
      `CLAUDE_CODE` keeps `SESSION_FORK` (it implements the reset). (iteration 23)

- [x] **Slash-menu UI trigger — closed as documented limitation** — `ASSUMPTIONS.md`,
      `packages/ui/src/components/SlashCommandTypeaheadPlugin.tsx`.
      Pristine composer + focus + real `insertText` event + content exactly `/` + 10 s wait still renders no
      menu, while the executor's discovery payload demonstrably carries 26 commands. Trigger requires a
      hardware-level keystroke (or the plugin is unmounted for this composer); recorded with evidence in
      `ASSUMPTIONS.md` and the `07-slash-menu.png` artifact. (iterations 17-19)
- [x] **Per-model reasoning capability** — `crates/executors/src/executors/pi.rs`.
      The catalogue carries `reasoning: bool` and `thinkingLevelMap`; `reasoning_options_for_entry()` now omits
      thinking levels for non-reasoning models and adds declared extras (`off`, `xhigh`, `max`). Verified live:
      301/412 models offer levels. (iteration 20)
- [x] **Worktree hygiene in `check.sh`** — `check.sh`.
      dev disables `DISABLE_WORKTREE_CLEANUP`, so deleted workspaces left their dirs behind; the check now
      deletes its workspaces, purges only the dirs it added (`purge_run_worktrees`, also used by the exit trap)
      and asserts the count is unchanged. Two consecutive runs: 5 -> 5, `SCORE 100`. (iteration 21)
- [ ] **pi docs cross-check** — `docs/supported-coding-agents.mdx`, `README.md`.
      Acceptance: `grep -ri "pi-acp\\|agents/pi" README.md docs/` shows the pi page linked from every agent
      list the other executors appear in.

- [x] **The create form's model choice did not reach pi (found by iteration 5, fixed in iteration 6).** The UI sends
      `provider_id/id`, so our provider-qualified ids arrived doubled; discovery now emits bare ids and §11 guards it. Original notes: With `kimi-coding/k3`
      visibly selected in the create form (chip read `kimi-coding/k3 · High`, Create enabled), the runs that came out of it
      (`b07b347d`, `8182d0a2`) ran the **default** model: pi's own session log for both checkouts records only
      `model_change zenmux/deepseek/deepseek-v4.1-flash`. The API path does apply a chosen model (iteration 4), so the gap is
      on the UI side: `useCreateModeState` submits `executor_config: state.executorConfig ?? null` and nothing outside that
      module calls `setExecutorConfig`, while the model selector writes through `useExecutorConfig` overrides
      (`CreateChatBoxContainer` submits the hook's config). Next: capture the actual start request body to decide between the
      two submit paths, then wire the selection through.
