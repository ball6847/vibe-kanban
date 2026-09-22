# pi executor — status after 86 loop iterations

## Verified end to end (evidence, not intent)

| Behaviour | Evidence |
| --- | --- |
| pi runs as a Vibe Kanban executor | `./check.sh` e2e: workspace exit 0, file written, turn recorded |
| Follow-ups keep context | check: "follow-up turn recalled turn-1 content" |
| Setup script runs before pi, pi sees its output | check: "repo setup script ran before pi (marker present)" |
| Uploaded attachments are readable by pi | check: image probe writes the right colour |
| Concurrent workspaces stay isolated | check: two runs, own files, no leakage |
| Working tree of the repo/executor | `cargo check -p executors -p server`, 22 unit tests, cold build + tests in a clean worktree |
| Slash commands | 24 installed skills; a `/skill:<name>` prompt actually invokes it |
| Browser evidence | `.context/evidence/pi/01..08` + `NOTES.md`, guarded for staleness |
| First run on a clean install | `./check.sh --fresh-state` -> 100 |
| Stopping a running agent | `killed`, no leftover `pi-acp` process |

Full run: **`SCORE 100`**, 41 checks, ~2.5 min. Negative controls (missing evidence / re-introduced POC hack) still fail as
they should (`notes/negative-controls.md`).

## Deliberate limitations

- **Model/thinking selection is hidden.** pi applies it through ACP session config options; the pinned
  `agent-client-protocol` 0.8 has no such API, and 0.11 is a redesigned crate (`ClientSideConnection` and the `Client` trait
  are gone), so enabling it is a protocol-layer rewrite across every ACP executor (scoped in `IMPROVEMENTS.md`). Until then pi
  uses its configured `defaultModel` and no picker is offered rather than one that does nothing.
- **Supervised approvals** are wired but pi-acp only requests permission for extension UI prompts, so tool calls are not gated
  (`ASSUMPTIONS.md`).
- **Project-local skills** are listed only when pi trusts the folder (`trust.json`); worktrees under `/var/tmp` normally are
  not trusted.
- **Composer slash-menu trigger** does not open under synthetic browser input (documented with the evidence).
- **`SETUP_HELPER`** is advertised but has no consumer in the UI/server today; wiring it (or dropping it) is tracked.

## Audit result

Eight defects were found and fixed by checking claims against authoritative sources rather than inference:
stale/duplicated docs tags, missing `ts-rs` export, `SESSION_FORK` advertised without rewind (pi, then gemini/qwen),
untrusted project skills offered, non-core `handoff`/`pickup` hardcoded, missing `off` thinking level, model list unfiltered by
auth, and a model selection that never reached the agent (now honestly hidden).
