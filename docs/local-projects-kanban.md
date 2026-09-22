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

## AppBar rail (cloud-parity navigation)

The projects section of the AppBar rail lists the same local projects and works
**without a cloud session** — no sign-in, no organizations:

- Data: `SharedAppLayout.tsx` loads projects with react-query under
  `LOCAL_PROJECTS_QUERY_KEY` (`localProjectsRailModel.ts`) and maps them with
  `toAppBarProjects` (id, name, and a colour derived deterministically from the
  project id — the local model has no colour column).
- Click: a rail tile calls `appNavigation.goToProject(id)`, opening that
  project's board.
- Active state: `resolveActiveProjectId(destination)` feeds `activeProjectId`,
  so the open project's tile is tinted while its board (or any project
  sub-route) is showing; the projects index highlights nothing.
- Create: the rail's create button calls `goToProjects()` and lands on
  `/projects`, whose composer creates the project. The rail is not a second
  create surface by design.
- Freshness: `LocalProjectsList` invalidates `LOCAL_PROJECTS_QUERY_KEY` after
  create, rename and delete, so the rail updates without a reload.
- Cloud path preserved: `AppBar` keeps its sign-in CTA and only bypasses it when
  `projectsEnabled` is passed (i.e. locally).
- Colours must be full `H S% L%` triples: `AppBar` interpolates them into
  `hsl(${color})` / `hsl(${color} / 0.2)`, and a bare hue renders the active
  highlight transparent.
- Navigation model: `{ kind: 'projects' }` + `goToProjects()` in
  `packages/web-core/src/shared/lib/routes/appNavigation.ts`, implemented in
  `packages/local-web/src/app/navigation/AppNavigation.ts` (forward →
  `/projects`, reverse ← route id `/_app/projects`). The kind is deliberately
  not part of `ProjectDestinationKind`, which drives kanban issue/workspace
  resolution from a project id.
