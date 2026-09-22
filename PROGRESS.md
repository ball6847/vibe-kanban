# PROGRESS — cloud-style local projects rail

**Current state:** M7 done. All behaviour milestones verified live; M8 (quality pass) outstanding. Full gate **133 -> 141/141 green** (lint gates restored). Live behaviour not yet verified (M6/M7). Navigation model has a `projects` destination + `goToProjects()`.
`SCORE` tracked per milestone (baseline recorded below).

## Baseline (M0)
- `./check.sh` → `SCORE: 58 / MAX: 133`, 21 failing checks. All failures are goal-specific
  (nothing implemented yet) except the three documented pre-existing gates, which the gate
  already scopes/baselines (see GOAL.md assumption 8).
- Pre-existing reds handled by the gate: `local-web` build needs CI's 8 GB heap; 26 unformatted
  `web-core` files on `main`; 104 unused i18n keys on `main`.

## Milestones
- [x] M0 — baseline recorded, loop docs reset
- [x] M1 — nav model: `{ kind: 'projects' }` + `goToProjects()` in `appNavigation.ts`
- [x] M2 — local-web nav mapping
- [x] M3 — pure rail model + vitest (28 tests / 3 files)
- [x] M4 — AppBar local mode + i18n key (all 7 locales)
- [x] M5 — SharedAppLayout wiring (react-query `['local-projects']`)
- [x] M6 — live verification (evidence in `.context/evidence/local-projects-rail/`); fixed the invisible active highlight (colour must be a full `H S% L%` triple)
- [x] M7 — refresh correctness (rail invalidates `LOCAL_PROJECTS_QUERY_KEY` on create/rename/delete; verified live)
- [ ] M8 — quality pass (format, docs, full green)

## Notes
- Previous goal (drop-remote) docs are in git history (`afc578024`).
