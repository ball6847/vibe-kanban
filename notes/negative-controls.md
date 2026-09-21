# Negative controls for `check.sh`

Proof that the harness actually fails when it should (a check that cannot fail is worthless). Run with the dev stack up;
`CHECK_FAST=1` keeps each step to ~35 s. Section headers carry no point totals so they cannot drift — re-check the award in
the script when the numbers below move.

Baseline (iteration 72, after the setup-coverage work): `CHECK_FAST=1 ./check.sh` -> `SCORE: 82`.

| Break | Expectation | Measured |
| --- | --- | --- |
| `mv .context/evidence/pi/*.png /tmp/ && CHECK_FAST=1 ./check.sh` | all three evidence checks miss (present 2, UI-run 2, freshness 1) | `SCORE: 77` |
| write `dev_assets/profiles.json` with `QWEN_CODE.base_command_override = "pi-acp"` | POC-hack guard misses (4) | `SCORE: 78` |
| restore both | back to baseline | `SCORE: 82` |

Full-run equivalents lose the same points from the 100 total (100 -> 95 / 96). Re-measure after changing `check.sh` so the
guard rails stay honest, and remember to restore the artifacts and delete `dev_assets/profiles.json`.

## Re-measured after the fork work (loop iteration 8, 2026-09-21)

| Control | Result |
| --- | --- |
| Baseline, `CHECK_FAST=1` | **97 / 97** (exit 0) |
| Evidence screenshots removed | **92 / 98** (exit 1) — note `MAX` moves with the branch (the present/absent evidence branches award different totals), so the gate stays correct but `MAX` is not comparable across that flip |
| Provider-relative guard: provider-qualified ids reintroduced in `pi.rs` | **94 / 97** with `[MISS] model ids must not repeat their provider (236 doubled)` — the exact bug from iteration 6 |
| Upstream adapter (`pi-acp@0.0.33`, no shim) | §14 probe: `model_applied: false`, `level_applied: false`, **exit 0** — i.e. the run succeeds while silently ignoring the model, which is why this defect survived so long. §14 fails; a green suite without §14 would have missed it |
| Restored (fork pinned, ids provider-relative) | **97 / 97**; §14 probe back to `model_applied: true, level_applied: true` |

Each control was applied by temporarily editing `pi.rs`, waiting for the cargo-watch rebuild, measuring, and reverting; the tree was
verified clean afterwards (`git status`).
