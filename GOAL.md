# GOAL — Link tasks to workspaces (cloud parity)

## Refined objective

Restore the task ↔ workspace linkage the obsolete cloud feature had, locally:

1. **Create a workspace from a task** — the task card offers it, the create flow opens
   prefilled with the task's title/description, and the resulting workspace records `task_id`.
2. **The task card shows its linked workspace(s)** and opens them on click.
3. **The link is durable and queryable** — `GET /api/workspaces?task_id=` returns it, and it
   survives a reload (no client-only state).
4. **Verification is e2e through the `agent-browser` CLI** (not just unit/type checks).

This is a *restore parity* goal: the columns, the read endpoint and the TS types already exist;
the write path and the UI were lost with the cloud feature.

## Evidence — why a task is a dead end today

| Gap | Evidence |
| --- | --- |
| Nothing can ever set the link | `crates/db/src/models/workspace.rs:311-323` — `Workspace::create` inserts a hardcoded `Option::<Uuid>::None` for the `task_id` column |
| The create API cannot carry a task | `shared/types.ts:409` — `CreateAndStartWorkspaceRequest = { name, repos, linked_issue, executor_config, prompt, attachment_ids }`; the only linkage field is `linked_issue: { remote_project_id, issue_id }`, which points at the deleted cloud |
| The reverse link is unwritable | `crates/db/src/models/task.rs:43` — `UpdateTask = { title, description, status }`, no `parent_workspace_id`, although the column exists |
| No UI affordance | `packages/web-core/src/pages/kanban/LocalKanbanBoard.tsx` — create / move / rename / delete only; no workspace reference anywhere |
| The read path existed but ignored the filter | `workspacesApi.getAll(taskId)` calls `GET /api/workspaces?task_id=` (`api.ts`) and `Workspace.task_id` is in `shared/types.ts`, but `get_workspaces` took no query params and returned every workspace (fixed in M1) |
| Stub routes | `/projects/:pid/issues/:iid/workspaces/create/:draftId` render `LocalProjectKanban` (the board) — a dead end |

## Scope

### In scope
1. `crates/db/src/models/workspace.rs` — `Workspace::create` binds a real `task_id`.
2. `crates/server/src/routes/workspaces/create.rs` (+ its request struct) — accept and persist
   `task_id` on `POST /api/workspaces/start`.
3. `shared/types.ts` regenerated (`pnpm run generate-types`) so the request carries `task_id`.
4. `.sqlx` offline caches updated for changed queries (`pnpm run prepare-db`).
5. `LocalKanbanBoard.tsx` — a **Create workspace** action per task that opens the local create
   flow prefilled from the task and carries the task id.
6. `LocalKanbanBoard.tsx` — the task card lists its linked workspace(s) and opens them.
7. Create-flow plumbing so the start request includes `task_id` (`useCreateModeState` /
   `workspaceCreateState` / `workspacesApi.createAndStart`).
8. i18n keys in all 7 locales; docs; tests; e2e evidence.

### Non-goals (do NOT do)
- No cloud code: no `crates/remote`, `packages/remote-web`, Electric, `shared/remote-types.ts`.
- `linked_issue` stays as an unused nullable field — removing it is separate cleanup.
- `Task.parent_workspace_id` stays unused: **`workspace.task_id` is the single source of truth**.
- No per-task repo/executor draft parity on the stub `workspaces/create/$draftId` routes; they may
  redirect to `/workspaces/create` at most. Full draft parity is backlog only.
- No change to the rail, the workspaces list/sidebar, the workspace runtime, or the board's
  existing task features (create/move/rename/description/delete).
- No multi-workspace management UI (no linking an *existing* workspace to a task).
- No new runtime dependencies.

## Measurable completion criteria

`bash check.sh` exits 0 **and** prints `SCORE: N/N`. Hard gates:

1. Every scored structural check passes (see Mandated names).
2. `pnpm run prepare-db:check` exits 0 (SQLx offline caches in sync with the code).
3. `cargo check --workspace --exclude vibe-kanban-tauri` exits 0.
4. `local-web:check`, `web-core:check`, `ui:check` exit 0.
5. `local-web:lint`, `ui:lint` exit 0; goal-owned files prettier-clean.
6. `check-i18n` exits 0, unused i18n keys stay ≤ 104, legacy-path guard exits 0, and `local-web`
   builds with `NODE_OPTIONS=--max-old-space-size=8192`.
7. `pnpm --filter @vibe/web-core test` exits 0.
8. **`agent-browser` e2e passes**: create-from-task → workspace linked → card shows it → open.
9. Screenshots from that run are committed under `.context/evidence/task-workspace-link/`.

The loop is endless: once `SCORE: N/N`, keep improving via `IMPROVEMENTS.md`. Declare
`LOOP_DONE:` only when the check is green.

## Mandated names (the gate greps for these — use them exactly)

| Thing | Exact |
| --- | --- |
| Request field (Rust) | `task_id: Option<Uuid>` in the start/request struct |
| Request field (TS) | `task_id` in `CreateAndStartWorkspaceRequest` |
| Task card root | `data-testid="task-card-<taskId>"` |
| Create-workspace action | `data-testid="task-create-workspace-<taskId>"` |
| Linked-workspace control | `data-testid="task-open-workspace-<workspaceId>"` on each linked workspace |
| Create-flow prompt field | the composer's `WYSIWYGEditor` (`aria-label="Markdown editor"`) — it does not forward `data-testid` |
| Create-flow submit | the composer's `Create` button (matched by accessible name) |
| i18n keys (`common`) | `kanban.task.createWorkspace`, `kanban.task.openWorkspace` |
| Open handler | `appNavigation.goToWorkspace(workspaceId)` |
| Evidence dir | `.context/evidence/task-workspace-link/` |
| Gate browser session | `agent-browser --session vibe-goal-check` |

## Milestone roadmap

One commit per milestone, Conventional Commits, repo left type-checking.

- **M0 — Baseline.** `pnpm install` done; `bash check.sh`; record `SCORE` + failing checks in
  `PROGRESS.md`; reset `PROGRESS.md` / `IMPROVEMENTS.md` / `ASSUMPTIONS.md` for this goal.
- **M1 — Backend write path.** Add `task_id: Option<Uuid>` to the create request; thread it
  through `create_workspace` into `CreateWorkspace`; make `Workspace::create` bind it instead of
  the literal `None`. Run `pnpm run prepare-db` (caches) and `pnpm run prepare-db:check`.
  Prove with curl: starting a workspace with `task_id` makes
  `GET /api/workspaces?task_id=<task>` return it; a start without `task_id` still yields `null`.
- **M2 — Types.** `pnpm run generate-types`; confirm `CreateAndStartWorkspaceRequest` carries
  `task_id`; `local-web:check` + `web-core:check` green.
- **M3 — Create from task.** In `LocalKanbanBoard.tsx` add the per-task **Create workspace**
  action (mandated test ids) that navigates to the local create flow with the task's title and
  description as the prompt, carrying the task id; the create flow submits it as `task_id`.
  The flow must be submittable **without further input** — a repo is preselected by default, so
  the e2e never picks one (it only clicks submit).
- **M4 — Show and open the link.** The task card lists its linked workspaces (resolve them from
  `workspacesApi.getAll(task.id)` / the workspace data the board already has) with the mandated
  test id and `goToWorkspace` on click; a task with no workspace shows nothing extra.
- **M5 — agent-browser e2e.** Run the flow with the CLI (session `vibe-goal-check`), save
  screenshots + `NOTES.md` under the evidence dir, and commit them. `check.sh` section 10 does
  the same flow automatically — make it pass.
- **M6 — Pure logic + tests.** Extract testable helpers next to the board (e.g.
  `taskWorkspaceLinkModel.ts`: build the create prompt from a task; pick the linked workspaces
  for a task id) and cover them with vitest.
- **M7 — Docs.** `docs/local-projects-kanban.md` (plus a short `docs/task-workspace-link.md` if
  it earns its place): the create-from-task flow, the link column, what is deliberately absent.
- **M8 — Quality pass.** Format goal files, full `bash check.sh` green, clean tree, evidence
  committed.

## Quality standards

- **Tests:** pure logic in `taskWorkspaceLinkModel.ts` covered by vitest; the interactive claim is
  proven by the `agent-browser` e2e, not asserted in code.
- **Docs:** the flow, the single-source-of-truth decision (`workspace.task_id`), and the
  deliberately unchanged pieces.
- **Git:** one commit per milestone; `feat(tasks): …`, `feat(server): …`, `test(tasks): …`,
  `docs(tasks): …`.
- **i18n:** every user-visible string through `t()` with keys in all 7 locales
  (`en, es, fr, ja, ko, zh-Hans, zh-Hant`); never leave an orphaned key.
- **Style:** no `any`, no non-null assertions to silence the compiler, no dead code, no new deps.
- **SQLx:** every changed query must be re-prepared so `prepare-db:check` stays green.

## Assumptions

1. Work continues on `drop-remote-support`; the change is additive to the local app.
2. Dev stack: `pnpm run dev` → UI on `FRONTEND_PORT` (3003) and API at
   `/tmp/vibe-kanban/vibe-kanban.port` (`main_port`, 3004).
3. `agent-browser` needs `--args "--no-sandbox"` here and prints an unrelated
   `~/.agent-browser/config.json` warning; the gate filters it. The gate uses its own session so
   it cannot disturb operator tabs.
4. Section 10 (browser e2e) is **scored**, not self-skipped: with the stack or the browser down
   the gate is red by design. Start `pnpm run dev` before running it.
5. `POST /api/workspaces/start` returns as soon as the workspace row exists, so the gate asserts
   the **link**, never agent output or workspace readiness.
6. `vibe-kanban-tauri` cannot build here (system glib missing) and is excluded everywhere.
7. Pre-existing repo drift stays out of scope: 26 unformatted `web-core` files on `main`, 104
   unused i18n keys, the 8 GB build heap, and the tracked `.pi-loop-log.jsonl`.
8. The e2e seeds its own repo/project/task through the API and deletes them afterwards, so it is
   re-runnable and does not depend on operator data.

## Commands

- Gate: `bash check.sh` (`CHECK_FAST=1 bash check.sh` skips the heavy build/lint steps — never the
  e2e section). The dev stack must be running (`pnpm run dev`) or section 10 scores zero.
- Types: `pnpm run generate-types && pnpm run local-web:check && pnpm run web-core:check && pnpm run ui:check`
- DB caches: `pnpm run prepare-db && pnpm run prepare-db:check`
- Tests: `pnpm --filter @vibe/web-core test`
- Dev: `pnpm run dev`
- Browser:
  `agent-browser --session vibe-goal-check open <url> --args "--no-sandbox"` ·
  `… eval "<js>"` · `… get url` · `… click "[data-testid=…]"` · `… screenshot <path>`

---

# Revision 2 — the task is the primary object (operator feedback, 2026-02-24)

## What history shows (evidence, not memory)

- **The deep link already exists as a dead path.** `origin/main` and this branch still ship
  `/projects/$projectId/issues/$issueId` and `.../issues/$issueId_/workspaces/$workspaceId`, but all of
  them render `LocalProjectKanban`, and the selector that used to drive them
  (`packages/web-core/src/project-routes/project-search.ts`) is now `z.object({})` — the selection
  params were stripped with remote support. `useCurrentKanbanRouteState` returns only `projectId`, so
  the params are ignored and every one of those URLs shows the plain board.
- **The dedicated task UI was a right-hand panel on the board, not a separate page.**
  `origin/main:packages/web-core/src/pages/kanban/ProjectRightSidebarContainer.tsx` resolved a
  selection into `{ kind: 'issue', issueId, resolution }` or `{ kind: 'issue-workspace', workspaceId }`
  and jumped with `appNavigation.goToWorkspace(workspaceId)` — exactly the "task detail → workspace"
  hop the operator describes. That file was deleted with remote support.
- **Task state used to be automatic.** `Task::update_status` no longer exists on this branch (only
  `PullRequest::update_status` survives). Upstream drove it from the execution lifecycle:
  `services/container.rs:938` start → `InProgress`; `container.rs:164/1035` completion → `InReview`;
  `services/pr_monitor.rs:131` PR merge → `Done`; `services/approvals.rs` review round-trips →
  `InReview`/`InProgress`. All of those local lifecycle points (`start_workspace`, `start_execution`,
  `stop_execution`) are still present, so the automation is re-attachable, not inventable.
- **The relationship is 1:1.** The operator's model: a task owns at most one workspace. Nothing
  enforces it today: `GET /api/workspaces?task_id=` returns a list, the create flow can be entered
  repeatedly, and `workspace.task_id` has no uniqueness constraint.

## Requirements (new hard gates)

1. **A task card is clickable** and selects the task (the card's own controls keep working and must not
   trigger selection). Selection is reflected in the URL so it is linkable and reloadable.
2. **A task has a dedicated detail UI** showing title, description, status and its workspace, with a
   **jump to the workspace**. Hooks: `data-testid="task-detail-panel"`,
   `data-testid="task-detail-open-workspace"`.
3. **1:1, enforced**: at most one workspace per task. Enforced in the database (partial unique index on
   `workspace.task_id`), so a second create-from-task returns/opens the existing workspace instead of
   making a duplicate. Gate: creating twice from the same task yields one workspace.
4. **Task state is automatic**: starting a workspace's execution moves the task to `InProgress`;
   the execution finishing moves it to `InReview`; a merged PR moves it to `Done`. Transitions are
   forward-only (never silently walk a task back), pure and unit tested, and never override an
   operator's explicit `Cancelled`/`Done`. Gate: after the e2e creates a workspace from a task, the
   task's status is `in_progress` without anyone clicking a move button.

## Milestones

- [ ] M9 — selection plumbing (`projectSearchSchema` params, `useCurrentKanbanRouteState`, clickable card)
- [ ] M10 — task detail panel + workspace jump (test ids above, i18n in all 7 locales)
- [ ] M11 — 1:1 enforcement (migration + create-from-task reuses the linked workspace)
- [ ] M12 — automated task status (guarded `Task::update_status` + lifecycle hooks + unit tests)
- [ ] M13 — gate + e2e for all of the above
