# PROGRESS — link tasks to workspaces

**Current state:** M1 done (backend write path **and** the read filter). Baseline recorded.

## Baseline (M0)
- `CHECK_FAST=1 ./check.sh` -> `SCORE: 47 / MAX: 104` (full: `68/125`, 335s). Every failure was
  the unimplemented feature.
- Pre-existing repo drift handled by the gate (26 unformatted `web-core` files, 104 unused i18n
  keys, 8 GB build heap, tracked `.pi-loop-log.jsonl`) stays out of scope.

## Milestones
- [x] M0 - baseline + loop docs reset
- [x] M1 - backend write path + read filter, proven with curl (positive/negative/control)
- [ ] M2 - regenerate types (`CreateAndStartWorkspaceRequest.task_id`)
- [ ] M3 - create-from-task action on the task card (prefilled, carries task_id)
- [ ] M4 - task card shows/opens linked workspaces
- [ ] M5 - agent-browser e2e + evidence
- [ ] M6 - pure logic (`taskWorkspaceLinkModel.ts`) + vitest
- [ ] M7 - docs
- [ ] M8 - quality pass, full gate green

## M1 detail (2026-09-23)
- `CreateWorkspace.task_id` added; `Workspace::create` now binds `data.task_id` instead of the
  hardcoded `Option::<Uuid>::None` (`crates/db/src/models/workspace.rs`).
- `CreateAndStartWorkspaceRequest.task_id` added (`crates/db/src/models/requests.rs`);
  `create_workspace_record(deployment, name, task_id)` threads it through
  (`crates/server/src/routes/workspaces/create.rs`); PR-created and MCP-created workspaces pass
  `None`.
- **Second gap found by the proof:** `GET /api/workspaces?task_id=` ignored the query param and
  returned every workspace. Added `ListWorkspacesQuery` + `Workspace::fetch_all_by_task_id`.
- New query cache committed via `pnpm run prepare-db`; `prepare-db:check` green.
- Proof (curl, dev server rebuilt): linked workspace returned alone by the filter; a workspace
  started without `task_id` is absent from it; the unfiltered list still returns all 5.
