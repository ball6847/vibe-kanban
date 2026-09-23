# ASSUMPTIONS — link tasks to workspaces

Inherits GOAL.md's assumptions. Additions from M1:

1. `workspace.task_id` is the single source of truth for the link; the reverse column
   `tasks.parent_workspace_id` stays unused to avoid dual-write drift.
2. The start request carries `task_id: Option<Uuid>`; PR-created and MCP-created workspaces pass
   `None` because neither is started from a local task.
3. `GET /api/workspaces` only filters when `task_id` is present, so every existing caller keeps
   its current behaviour.
4. The new `fetch_all_by_task_id` query is part of the SQLx offline cache; any change to it
   requires `pnpm run prepare-db` again.
5. The dev server rebuilds itself through `cargo watch`, so the curl proof required waiting for
   `/api/health` to answer 200 before asserting.

## Revision 2 — assumptions made without asking

1. **Selection is a URL search param on the project board** (`?task=<uuid>`), not a new route tree.
   Rationale: the codebase's own convention (`projectSearchValidator` on every project route) and the
   upstream selector were both search/path-param driven; the leftover `issues/$issueId` paths stay
   untouched (removing those cloud paths is separate cleanup).
2. **The task detail lives in a right-hand panel on the board** (as `ProjectRightSidebarContainer` did)
   rather than a full page, because the operator's description ("jump from task detail to workspace")
   matches that panel, and it keeps the board as the single screen.
3. **`workspace.task_id` stays the source of truth** (not `Task.parent_workspace_id`), now with a partial
   unique index to make it 1:1.
4. **Automated status is forward-only**: `todo -> in_progress -> in_review -> done`, with `cancelled`
   terminal and operator-set `done` never regressing; `in_review` is also reachable from `todo` if an
   execution finishes without a recorded start.
5. **`agent-browser` remains the e2e driver**; the status automation is asserted through the API inside
   that same browser-driven flow.
