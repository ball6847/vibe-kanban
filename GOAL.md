# GOAL — `pi` (pi-acp) executor support, with working model/thinking selection via our fork

**Status:** base support shipped (loop iterations 1–86); this spec covers the remaining goal: model/thinking selection
through the running app, using **our pi-acp fork** instead of upstream.
**Check command:** `./check.sh` → prints `SCORE: <n>` and `MAX: <n>`; **exit 0 only when `SCORE == MAX`**.
`CHECK_FAST=1 ./check.sh` skips the e2e/browser work for a ~1-minute static+build pass.
**Status:** all criteria below are met — `SCORE 123 / MAX 123` (207 s) with the dev stack and `123 / MAX 123`
with `--fresh-state` (220 s), 2026-09-21. `SCORE: 79 / MAX: 94` was the starting point before the fork work.
**State files:** `PROGRESS.md` (live state), `IMPROVEMENTS.md` (backlog), `ASSUMPTIONS.md` (decisions/deviations),
`notes/loop-history.md` (iteration log), `.context/evidence/pi/` (browser evidence).

## Objective

Make Vibe Kanban's `PI` executor complete: pi must be selectable, run end-to-end, **and let the user choose the model and
thinking level, with the choice actually applied to the agent**. The mechanism is our own `pi-acp` fork — Vibe Kanban's Rust
client cannot send the modern ACP config-option request, so the fork accepts the legacy `session/set_model` call it does
send and translates it. Everything must be verified through the running app (browser harness), and the code must follow the
existing ACP executor patterns.

## Ground truth (verified; do not re-derive)

- Executor: `crates/executors/src/executors/pi.rs`, pattern = `AcpAgentHarness` + `StandardCodingAgentExecutor`
  (`crates/executors/src/executors/acp/harness.rs`). Base support is done and green (runs, follow-ups, attachments, setup
  scripts, concurrency, cancellation, 24 slash commands, docs page, `--fresh-state` = 100/100 on the old criteria).
- **Why selection was blocked:** VK's pinned `agent-client-protocol` 0.8 sends `session/set_model`; pi-acp bundles
  `@agentclientprotocol/sdk@0.26.0`, which dispatches only `session/{cancel,list,load,prompt,update}` → `Method not found`.
  pi exposes `model` and `thought_level` as **session config options**; 0.8 has no API to send `session/set_config_option`
  and no raw-request escape hatch, and `_meta` is ignored by pi-acp. Bumping the Rust crate is **not** the fix: 0.11 removed
  `ClientSideConnection` and the `Client` trait, i.e. it is a layer rewrite (measured: 127 errors, then structural).
- **Fork:** `github.com/ball6847/pi-acp` (pushed, `main`, version `0.0.34`, commit `f8d999f`). Adds
  `src/acp/set-model-shim.ts`: rewrites `session/set_model` → `session/set_config_option` (`model`, plus `thought_level` when
  `modelId` carries a `:<level>` suffix) and answers the client once both complete. 98/98 tests pass, eslint/prettier clean,
  `prepare` script added so git installs build.
- **Verified against a real pi session** (probe): `session/set_model` no longer errors; `kimi-coding/k3` applied;
  `…deepseek-v4.1-flash:minimal` applied model **and** `thought_level: minimal`; `kimi-coding/k3:off` left the level at
  `high` because **pi itself** ignores unsupported levels for that model (not a shim bug).
- VK composes the model as `provider/model:<level>` (`effective_model()` in `pi.rs`); discovery reads `pi --list-models`
  (236 models, 173 with thinking levels; order `off, minimal, low, medium, high`, plus per-model `xhigh`/`max`).
- Model discovery behind `MODEL_SELECTION_SUPPORTED` works when flipped (verified live): 236 models, default present.
- Discovered options API (used by `check.sh` §11):
  `ws://localhost:$PORT/api/agents/discovered-options/ws?executor=PI&repo_id=<id>` → patches containing `model_selector`.
- Dev stack: `pnpm run dev` → UI `:3003`, backend `:3004` (port from `/tmp/vibe-kanban/vibe-kanban.port`), pid
  `/tmp/vk-dev.pid`. `cargo watch` rebuilds in ~30–60 s; wait for it before asserting behaviour.
- Browser harness: Chrome at `~/.dotfiles/agent-browser/browsers/chrome-*/chrome`, profile
  `/tmp/agent-browser-chrome-f132f78e-5df2-48a1-8dd5-e25b1e3988c6`, CDP needs `--remote-allow-origins=*`.

## Scope

- Point the `PI` executor at **our fork** and keep it a one-line, reviewable dependency change.
- Switch model selection on and prove the choice reaches pi.
- Keep the fork a **thin shim** (no pi semantics changes); keep VK free of protocol-crate churn.
- Update docs, tests, `check.sh`, and the evidence set so every claim is verifiable.

## Non-goals

- No `agent-client-protocol` bump, no ACP layer rewrite (documented in `IMPROVEMENTS.md`; shared with gemini/qwen/copilot,
  which cannot be end-to-end tested here).
- No gemini/qwen/copilot behaviour changes; no MCP support for pi (pi has none by design).
- No npm registry publish unless a git spec proves insufficient (then document why).
- No speculative UI work: only what `MODEL_SELECTION_SUPPORTED` + existing components already support.

## Completion criteria (measurable)

| # | Criterion | How it is checked |
| --- | --- | --- |
| C1 | Executor runs our fork (`github:ball6847/pi-acp`) | `check.sh` §1 |
| C2 | Model selection switched on (`MODEL_SELECTION_SUPPORTED = true`) | `check.sh` §11 |
| C3 | Discovery advertises models (>0) with thinking levels, default present | `check.sh` §11 |
| C4 | A workspace run with a chosen non-default model + level completes exit 0 and pi's session shows that model | new e2e assertion in `check.sh` |
| C5 | The picker is visible and usable in the UI, evidenced by screenshots | `check.sh` browser section + `.context/evidence/pi/` |
| C6 | Existing pi behaviour still green (run, follow-up, attachments, setup script, concurrency, cancellation, slash commands) | `check.sh` §2–§10 |
| C7 | Unit tests (≥ 22 in `pi.rs`) pass; `cargo check -p executors -p server` clean | `check.sh` build section |
| C8 | Docs describe the fork, selection, and `:level` semantics (incl. pi ignoring unsupported levels) | `check.sh` docs section |
| C9 | `pnpm run format` applied; conventional commits; `git status` clean | manual / commit log |
| C10 | Negative controls re-measured after any `check.sh` change | `notes/negative-controls.md` |
| C11 | `./check.sh` reaches `SCORE == MAX`; `./check.sh --fresh-state` also green | `check.sh` |

## Milestones

- **M1 — fork is consumable.** `npm pack` and a git install from `github:ball6847/pi-acp` both produce a working adapter;
  a probe against the *installed* copy applies a model and a level. Verify: probe output shows model + `thought_level`.
- **M2 — executor uses the fork.** Replace the pinned `pi-acp@0.0.33` with the fork spec in `pi.rs`; `cargo check -p executors`
  clean; unit tests pass; one API-driven workspace run completes exit 0. Verify: `check.sh` C1 + a run.
- **M3 — selection switched on.** Flip the flag; discovery reports models/reasoning/default; `check.sh` §1, §11 pass.
- **M4 — the choice actually reaches pi.** Start a run choosing a non-default model and a thinking level; assert the applied
  model from pi's own session record (pi persists the model per session under `~/.pi/agent/sessions`) and that the run
  completes exit 0. Add this as a real `check.sh` e2e assertion (replacing any interim assumption).
- **M5 — browser verification.** Via the harness: open the workspace form, confirm the model picker lists models, select a
  non-default model, start the run, capture evidence (`pick-models`, `pick-selected`, `pick-run`) + update `NOTES.md`.
- **M6 — docs and tests.** `docs/agents/pi.mdx`: fork adapter, how selection works, `:level` suffixes, pi-ignored levels,
  upgrade/rollback of the fork; remove the "picker hidden" limitation. Keep/extend tests.
- **M7 — negative controls.** Re-measure with `check.sh` changes in place (baseline, evidence removed, capability faked).
- **M8 — close out.** `PROGRESS.md`, `IMPROVEMENTS.md`, `ASSUMPTIONS.md` updated; full `./check.sh` and `--fresh-state`
  green; `git status` clean; loop history rotated per `notes/README.md`.

## Quality standards

- **Scoped loops:** `cargo check -p executors` / `-p server` (3–9 s warm). Never `--workspace` (fails: `tauri-app` needs
  GTK/glib dev libs, and it is slow).
- **Tests:** Rust unit tests next to the code (`#[cfg(test)]`); `cargo test -p executors --lib pi` must stay green.
  Fork tests: `npm test` (98) + eslint/prettier, run before pushing the fork.
- **Verification before claims:** each criterion must trace to a command output or an artifact. No "should work".
- **Commits:** conventional messages, one logical unit each; `git status` clean; never commit `dev_assets/`.
- **Evidence:** every UI claim backed by a screenshot in `.context/evidence/pi/` that is newer than the code it shows.
- **Fork hygiene:** one purpose per commit, README documents the shim, version bumped on behaviour change.

## Assumptions and deviations

- The machine has network access for `npx`/git installs; the fork stays public.
- pi-acp's config-option values are the model ids VK already lists (`provider/model`); the shim strips the `:<level>` suffix
  before applying the model.
- pi may ignore a level it does not support for a given model — that is pi's rule, documented, not worked around.
- Supervised approvals stay a documented deviation (pi-acp only requests ACP permission for extension UI prompts).
- `SETUP_HELPER` remains informational until something consumes it.
- Project-local pi skills stay trust-gated (`~/.pi/agent/trust.json`); `/skill:<name>` prompts do invoke skills (verified).
