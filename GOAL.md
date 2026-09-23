# GOAL — bring the task UX/UI back (local, cloud-free, verified by screenshots)

Status: active · Branch: `drop-remote-support` · Checker: [`check.sh`](./check.sh) (`CHECK_FAST=1 ./check.sh` ≈ 2.5 min, full ≈ 5.5 min)

## Objective

Restore the **task experience** that the deleted cloud feature provided, using only local data, so a
task is a first-class object again: clickable cards, a dedicated detail panel, a workspace you can jump
to, and a task state that advances itself while work happens.

Upstream reference (`git show afc578024` — "drop all remote/cloud support") deleted, among others:
`pages/kanban/KanbanIssuePanelContainer.tsx` (the detail panel), `ProjectRightSidebarContainer.tsx`
(the panel host that jumped to the workspace), `kanban-issue-panel-state.ts` (panel selection state),
`IssueWorkspacesSectionContainer.tsx` (the task's workspace section), `features/kanban/ui/
KanbanContainer.tsx`, `useKanbanFilters.ts`, `BulkActionBarContainer.tsx`, `useIssueShortcuts.ts`,
and the selection params in `project-routes/project-search.ts` (now `z.object({})`).

Parity target = the **local** subset of that UX. Verification target = a browser-driven (agent-browser)
run that produces **screenshots** plus DOM/API assertions for every capability.

## Scope

In scope (all local, no new runtime dependencies):

1. **Clickable task card → selection.** Clicking a card selects the task and reflects it in the URL
   (`?task=<taskId>`), so the view is linkable and survives reload. Card controls (move/create/delete)
   keep working and must not trigger selection.
2. **Dedicated task detail UI** (right-hand panel, as upstream): title, description, status, workspace,
   inline edit of title/description, delete. Closeable (button and `Escape`).
3. **Workspace section, 1:1**: a task owns at most one workspace. The panel shows it and can open it
   (`goToWorkspace`) or create it (prefilled from the task, as today). Starting a second one from the
   same task opens the existing workspace instead of creating a duplicate — enforced in the database.
4. **Automated task status**: execution starting → `in_progress`; execution finishing → `in_review`;
   PR merged → `done`. Forward-only, never silently undoing an operator's `done`/`cancelled`.
5. **Board ergonomics that the old UI had**: filter tasks (text + status), bulk actions (select several
   tasks → move / delete), and keyboard handling (`Escape` closes the panel, `c` focuses the new-task
   input, `/` focuses the filter).

Non-goals (deleted with the cloud feature and impossible locally): comments, sub-issues, issue
relationships, assignees, priorities, remote issue links, the sunset page, remote workspaces. Do not
re-add cloud code, `shared/remote-types.ts`, `crates/remote`, `packages/remote-web`, or Electric deps.

## Completion criteria (measurable)

`./check.sh` is the arbiter: it prints `SCORE: <n>` / `MAX: <n>` and exits 0 **only** when
`SCORE == MAX`. Baseline today is printed by the first run; every milestone raises it.

Hard criteria (each is a gate section):

- **Selection**: the card is clickable, the URL carries `?task=`, a reload keeps the panel open, and
  `Escape` closes it.
- **Detail panel**: `data-testid="task-detail-panel"` visible after a card click, showing the task's
  title, description and status; editing the title through the panel persists (`GET /api/tasks/<id>`).
- **Workspace section**: the panel shows the linked workspace, `task-detail-open-workspace` navigates to
  `/workspaces/<workspaceId>`, and `task-detail-create-workspace` runs the existing prefilled create flow.
- **1:1**: triggering create-from-task twice leaves exactly one workspace for that task
  (`GET /api/workspaces?task_id=` returns one id both times).
- **Automated status**: after the e2e creates and starts a workspace from a task, `GET /api/tasks/<id>`
  reports `in_progress` with nobody clicking a move button; the transition function is unit tested.
- **Filters / bulk / keyboard**: filtering narrows the rendered cards; selecting two cards and moving
  them updates both tasks (`GET /api/tasks`); `Escape` closes the panel.
- **Evidence**: ≥4 screenshots (>12 KB PNG, one per claim above) committed under
  `.context/evidence/task-ux/` together with a `NOTES.md` that maps each screenshot to the claim it proves.
- **Quality**: type checks, lint, prettier, `cargo check`, SQLx caches, i18n regression, local-web build
  and the vitest suite all pass; no new runtime dependency; no cloud code (guards in section 5).

## Mandated test hooks (the gate greps these — do not rename)

| Hook | Where |
| --- | --- |
| `task-card-<taskId>` | card root (already exists) — clicking it selects the task |
| `task-detail-panel` | panel root |
| `task-detail-title`, `task-detail-description`, `task-detail-status` | panel fields |
| `task-detail-edit-title`, `task-detail-title-input`, `task-detail-save`, `task-detail-delete` | panel controls |
| `task-detail-open-workspace`, `task-detail-create-workspace` | panel workspace actions |
| `kanban-filter-input`, `kanban-filter-clear` | board filter |
| `task-select-<taskId>`, `kanban-bulk-move`, `kanban-bulk-delete` | bulk actions |
| `task-create-workspace-<taskId>`, `task-open-workspace-<workspaceId>` | card actions (already exist) |

URL contract: `/projects/<projectId>?task=<taskId>` opens the panel. The create flow's prompt editor is
a Lexical `contenteditable` (`aria-label="Markdown editor"`) that does not forward `data-testid`; the
gate locates it by that label and submits with the composer's `Create` button.

## Milestones (small steps; commit each one)

- [ ] **M1 — selection plumbing.** Extend `projectSearchSchema` with `task`, expose it from
  `useCurrentKanbanRouteState`, make the card a clickable region that sets/clears the param, add
  `Escape` to close. Verify: gate section 2 + `?task=` in the browser.
- [ ] **M2 — detail panel.** New `packages/web-core/src/pages/kanban/TaskDetailPanel.tsx` rendered by the
  board when a task is selected: title/description (inline edit), status, delete, close button; all
  strings in `kanban.task.*` for the 7 locales. Verify: gate section 3 + screenshot.
- [ ] **M3 — workspace section + 1:1.** Panel section showing the linked workspace with open/create;
  migration adding a partial unique index on `workspace.task_id`; create-from-task reuses the existing
  workspace. Verify: gate section 4 + the e2e create-twice check + screenshot.
- [ ] **M4 — automated status.** Restore `Task::update_status` around a pure, unit-tested transition
  function, then hook it: execution start → `in_progress`, execution finish → `in_review`, PR merge →
  `done` (forward-only, never regressing `done`/`cancelled`). Verify: gate section 5 + e2e status poll.
- [ ] **M5 — filters.** Text + status filtering in a pure model (`taskFilters.ts`) with tests, wired to
  `kanban-filter-input` / `kanban-filter-clear`. Verify: gate section 6 + e2e narrowing.
- [ ] **M6 — bulk actions.** Per-card selection checkbox (`task-select-<id>`), a bulk bar with move and
  delete, pure selection model with tests. Verify: gate section 6 + e2e multi-move.
- [ ] **M7 — keyboard.** `Escape` (close panel), `c` (focus new-task input), `/` (focus filter) via a
  small hook; documented in `docs/local-projects-kanban.md`. Verify: gate section 6 + e2e keypress.
- [ ] **M8 — quality pass.** `pnpm run format`, docs updated (task panel, 1:1, status automation,
  shortcuts), evidence `NOTES.md` + screenshots committed, full `./check.sh` green, tree clean apart
  from the loop's own log file.

## Quality standards

- Conventional Commits, **one milestone per commit**; the repo must type-check and format at every commit.
- Tests for all pure logic (vitest, `packages/web-core`) — filtering, selection, transitions, link lookup.
- i18n: every user-facing string exists in all 7 locales (`en, es, fr, ja, ko, zh-Hans, zh-Hant`) with no
  orphans (the ≤104 unused-key baseline is a regression guard, not a target).
- Docs: `docs/local-projects-kanban.md` describes the task panel, the 1:1 rule and the automatic statuses.
- Evidence: screenshots are the verification artifact — capture them from a real browser run and commit
  them; never fabricate a claim the gate cannot reproduce.
- Keep diffs surgical: do not reformat pre-existing drift; record unrelated cleanups in `IMPROVEMENTS.md`.

## Assumptions (decided without asking; recorded in `ASSUMPTIONS.md`)

1. **Parity means the local subset.** Cloud-only affordances (comments, sub-issues, relations, assignees,
   priority, remote links) are non-goals — they cannot work without the deleted backend.
2. **The panel is a right-hand sidebar on the board**, selected through URL search params — exactly how
   upstream did it (`projectSearchValidator` + `ProjectRightSidebarContainer`). The leftover
   `/projects/$projectId/issues/$issueId` routes stay untouched (their removal is separate cleanup).
3. **`workspace.task_id` stays the source of truth**, now backed by a partial unique index for 1:1;
   `Task.parent_workspace_id` remains unused.
4. **Status automation is forward-only**: `todo → in_progress → in_review → done`, `cancelled` terminal,
   and `in_review` is reachable from `todo` when an execution finishes without a recorded start.
5. **A screenshot is valid evidence** if it is a PNG > 12 KB produced by `agent-browser screenshot` during
   the run (blank/failed captures are smaller).
6. **`agent-browser` is the only e2e driver** (`--args "--no-sandbox"`); relative screenshot paths resolve
   against the daemon's cwd, so the gate always passes absolute paths.
7. **Rust checks exclude `vibe-kanban-tauri`** (system glib/GTK absent here).
8. **Pre-existing drift is out of scope**: 26 unformatted `web-core` files and 104 unused i18n keys exist
   on `main`; the gate only forbids regressions.

## Baseline (measured before M1)

Measured on the commit that introduced this spec: **fast `SCORE 58 / MAX 226` in 106 s** (full mode adds
the lint/i18n/build sections, so its `MAX` is higher — always compare `SCORE` against that run's `MAX`).
Sections 1, 7, 11, 12 and the board/card/create basics already score; every M1+ check fails with a
diagnostic naming what is missing.

## Operating notes (for an unattended run)

- Start the dev stack detached, or it dies with the harness process group:
  `setsid nohup pnpm run dev > /tmp/vibe-dev.log 2>&1 < /dev/null & disown`; UI on
  `http://localhost:3003`, API on `http://localhost:3004` (port file `/tmp/vibe-kanban/vibe-kanban.port`).
- `cargo watch` rebuilds after Rust edits — poll `/api/health` for 200 before API/e2e work. The heavy
  gate sections rebuild `target/`, so restart the stack after a full run.
- Run the e2e **before** the Rust gates (they starve `cargo watch` and can kill the API the browser needs).
- Fixtures (repo, project, task, workspace) are created and deleted by the gate itself.
