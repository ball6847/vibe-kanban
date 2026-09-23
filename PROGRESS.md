# PROGRESS — link tasks to workspaces

**Current state:** M4 + M6 done. Whole e2e flow green (create-from-task, link, show, open). e2e passes: create action -> create flow (prefilled from the task) ->
submit -> workspace created, opened and linked (`GET /api/workspaces?task_id=`).

## Baseline (M0)
- `CHECK_FAST=1 ./check.sh` -> `SCORE: 47 / MAX: 104` (full: `68/125`, 335s). Every failure was
  the unimplemented feature.
- Pre-existing repo drift handled by the gate (26 unformatted `web-core` files, 104 unused i18n
  keys, 8 GB build heap, tracked `.pi-loop-log.jsonl`) stays out of scope.

## Milestones
- [x] M0 - baseline + loop docs reset
- [x] M1 - backend write path + read filter, proven with curl (positive/negative/control)
- [ ] M2 - regenerate types (`CreateAndStartWorkspaceRequest.task_id`)
- [x] M3 - create-from-task action (prefilled, carries task_id) - **verified e2e via agent-browser**
- [x] M4 - task card shows/opens linked workspaces (verified e2e)
- [ ] M5 - agent-browser e2e + evidence
- [x] M6 - pure logic (`taskWorkspaceLinkModel.ts`) + vitest (34 tests / 4 files)
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

## M3 detail (2026-09-23)
- The draft carries the task: `DraftWorkspaceData.task_id` (Rust, `#[serde(default)]`), regenerated
  types, `CreateModeInitialState.taskId`, bootstrap (seed + scratch), reducer state, and the
  debounced draft save.
- `useCreateModeState`/`CreateModeProvider` expose `taskId`; `CreateChatBoxContainer` sends it as
  `task_id` (the `null` placeholder is gone).
- `LocalKanbanBoard` gained the per-task action (`data-testid="task-create-workspace-<id>"`, card
  test id `task-card-<id>`) which persists the draft (prompt from title+description + task id) and
  opens `/workspaces/create`; `kanban.task.createWorkspace`/`openWorkspace` added to all 7 locales.
- Spec amended: the prompt editor does not forward `data-testid`, so the gate locates it by its
  `aria-label="Markdown editor"` and submits via the composer's `Create` button.
- Gate fixes: UUID parsing no longer accepts `/workspaces/create` as a workspace (it captured `c`),
  and the prompt probe reads `textContent` (the editor is a Lexical contenteditable).
