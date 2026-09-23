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
