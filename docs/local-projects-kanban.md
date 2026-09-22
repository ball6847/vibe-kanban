# Local Projects Kanban (sqlite-backed)

The local web app serves a projects kanban board backed only by the local
sqlite database — no login, no organizations, no remote sync.

- List: `packages/web-core/src/pages/kanban/LocalProjectsList.tsx` at
  `/projects` (route `_app.projects.tsx`; detail routes use flat
  `projects_.*` ids so the list is not their layout parent). Supports
  create, rename (double-click), and delete; deleting a project cascades
  to its tasks (verified live against sqlite).
- Board: `packages/web-core/src/pages/kanban/LocalKanbanBoard.tsx`, rendered
  by `LocalProjectKanban.tsx` on all `/projects/:projectId` local-web routes.
  Columns map `tasks.status` (`todo` / `inprogress` / `inreview` / `done`);
  `cancelled` tasks fold into the Done column. Supports create, move
  (‹ ›), rename (double-click title), edit description, and delete;
  shows not-found, error+retry, mutation-error banners, and mobile snap-scroll.
- API (`crates/server/src/routes/local_projects.rs`):
  `GET /api/projects`, `POST /api/projects`, `PATCH /api/projects/{id}`,
  `DELETE /api/projects/{id}`,
  `GET /api/tasks?project_id=`, `POST /api/tasks`, `PATCH /api/tasks/{id}`,
  `DELETE /api/tasks/{id}`.
- Data layer: `crates/db/src/models/project.rs` (`Project`, `CreateProject`)
  and `crates/db/src/models/task.rs` (`Task`, `TaskStatus`, `CreateTask`,
  `UpdateTask`). No new migrations — it reuses the existing
  `projects`/`tasks` tables.
- Frontend calls go through `localProjectsApi` / `localTasksApi` in
  `packages/web-core/src/shared/lib/api.ts`.
