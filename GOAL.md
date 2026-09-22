# GOAL — Cloud-style local projects rail

## Refined objective

Give the local projects feature the **same navigation UX the cloud feature had**, inside the
de-remoted (local-only) app:

1. The AppBar rail shows the **list of local projects** (from `GET /api/projects`).
2. Clicking a rail project **navigates to that project's board**.
3. The **active project is highlighted** while its board is open.
4. The rail has a **Create project** affordance that works without cloud sign-in.
5. The navigation model gains a **`projects` destination** so the rail can also reach the
   local `/_app/projects` index page.

This is a **wiring/UX-integration** goal. It reconnects an existing local feature (built by
`feat/projects`, already in `main`) to the existing shell. It does NOT rebuild the projects
feature, and it does NOT re-introduce any cloud code.

## Evidence — why the UX is currently disconnected

| Gap | Evidence |
| --- | --- |
| No destination for the projects index | `packages/web-core/src/shared/lib/routes/appNavigation.ts` — `AppDestination` has `{ kind: 'project'; projectId }` but nothing for `/_app/projects`; no `goToProjects()` exists anywhere. |
| Rail hardcoded to empty | `packages/web-core/src/shared/components/ui-new/containers/SharedAppLayout.tsx` — `projects={[]}`, `const activeProjectId = null;`, no `onProjectClick` / `onCreateProject`. |
| Rail gated on cloud sign-in | `packages/ui/src/components/AppBar.tsx` — `if (!isSignedIn) { projectSectionItems.push({ kind: 'kanban-cta', ... }) }`; the create button is `if (isSignedIn && onCreateProject)`. Locally `isSignedIn` is always false, so the rail renders the "Sign in to view projects" popover. |
| Project shapes differ | `AppBarProject = { id, name, color }` (`packages/ui/src/components/AppBar.tsx`); local `Project = { id, name, default_agent_working_dir, remote_project_id, created_at, updated_at }` (`shared/types.ts\`) — no `color`. |
| Existing local UX is page-only | `packages/web-core/src/pages/kanban/LocalProjectsList.tsx` fetches `localProjectsApi.list()` and calls `appNavigation.goToProject(id)`; it is reachable only by typing `/projects`. |

## Scope

### In scope
1. `packages/web-core/src/shared/lib/routes/appNavigation.ts` — add destination + interface method.
2. `packages/local-web/src/app/navigation/AppNavigation.ts` — implement forward + reverse mapping.
3. `packages/web-core/src/pages/kanban/localProjectsRailModel.ts` (**new**) — pure helpers + tests.
4. `packages/ui/src/components/AppBar.tsx` — local-projects mode (no cloud-sign-in gate).
5. `packages/web-core/src/shared/components/ui-new/containers/SharedAppLayout.tsx` — data + wiring.
6. i18n keys for any new user-visible string, in **all 7 locales**.
7. Docs: `docs/local-projects-kanban.md`.
8. Tooling needed to verify the above (web-core unit-test runner).

### Non-goals (do NOT do)
- No cloud/remote code: no `crates/remote`, no `packages/remote-web`, no Electric, no
  `shared/remote-types.ts`. These stay deleted.
- No backend/Rust changes. This goal is frontend-only.
- No re-adding cloud sign-in, organizations, billing, notifications, or their UI.
- No redesign of `LocalProjectsList` / `LocalKanbanBoard` / the board, and no change to the
  local projects REST API.
- No drag-to-reorder of rail projects (cloud had it via remote `sort_order`). Allowed later as
  an improvement item, never as a blocker.
- Do not "fix" unrelated pre-existing issues; note them in `IMPROVEMENTS.md` instead.
- Relay/device-control, workspaces, hosts, terminals, git — untouched.

## Measurable completion criteria

`bash check.sh` exits 0 **and** prints `SCORE: N/N`. Hard gates (all must hold):

1. Every scored structural check in `check.sh` passes.
2. `pnpm run local-web:check`, `web-core:check`, `ui:check` exit 0.
3. `pnpm run local-web:lint` and `pnpm run ui:lint` exit 0.
4. The **goal-owned files** are prettier-clean (`check.sh` scopes prettier to them — see
   assumption 8; repo-wide format drift on `main` is not this goal's problem).
5. `GITHUB_BASE_REF=main ./scripts/check-i18n.sh` exits 0, and the repo-wide unused-i18n-key
   count does **not exceed the 104 baseline** (`check.sh` compares the count; prune any key you
   orphan).
6. `./scripts/check-legacy-frontend-paths.sh` exits 0 and `local-web` builds with
   `NODE_OPTIONS=--max-old-space-size=8192` (CI's heap; the default heap OOMs at ~12.6k modules).
7. `pnpm --filter @vibe/web-core test` exits 0 (unit tests for the pure rail model).
8. The rail behaves per the objective, verified live in a browser (see M6).

The loop is **endless**: once `SCORE: N/N`, keep raising quality via `IMPROVEMENTS.md`.
Declare `LOOP_DONE:` only when the check is green.

## Mandated names (use exactly these; the check script greps for them)

| Thing | Exact name |
| --- | --- |
| Destination kind | `{ kind: 'projects' }` |
| Navigation method | `goToProjects(transition?: NavigationTransition): void` |
| AppBar prop | `projectsEnabled?: boolean` |
| Index route id | `/_app/projects` (file `packages/local-web/src/routes/_app.projects.tsx`) |
| Pure helper module | `packages/web-core/src/pages/kanban/localProjectsRailModel.ts` |
| Helper exports | `toAppBarProjects`, `resolveActiveProjectId` |
| New i18n key | `appBar.projects.create` (namespace `common`, all 7 locales) |
| Shell filler marker | comment `Row-1 filler` in `SharedAppLayout.tsx` (keep it — it fixes a real grid bug) |

## Milestone roadmap

Each milestone is one commit, Conventional Commits style, and must leave the repo
type-checking. Run `bash check.sh` at the end of each milestone and record `SCORE` in
`PROGRESS.md`.

- **M0 — Baseline.** Confirm branch and that `pnpm install` is done. Run `bash check.sh`,
  record the starting `SCORE` and the failing checks in `PROGRESS.md`. Reset
  `PROGRESS.md` / `IMPROVEMENTS.md` / `ASSUMPTIONS.md` for this goal (the previous goal's text
  is preserved in git history).
- **M1 — Navigation model.** In `appNavigation.ts`: add `| { kind: 'projects' }` to
  `AppDestination` and `goToProjects` to the navigation interface. Do **not** add it to
  `ProjectDestinationKind` (that type drives kanban issue/workspace resolution). Verify
  `pnpm run web-core:check`.
- **M2 — local-web navigation.** In `AppNavigation.ts`: `destinationToLocalTarget` returns
  `{ to: '/_app/projects' }` for `kind: 'projects'`; `resolveLocalDestinationFromPath` returns
  `{ kind: 'projects' }` for `case '/_app/projects':`; implement
  `goToProjects: (transition) => navigateTo({ kind: 'projects' }, transition)`. Verify
  `pnpm run local-web:check`.
- **M3 — Pure rail model + tests.** Add `localProjectsRailModel.ts` with
  `toAppBarProjects(projects: Project[]): AppBarProject[]` (deterministic colour derived from
  the project id — no randomness) and `resolveActiveProjectId(destination: AppDestination | null): string | null`
  (returns the project id for `kind: 'project'` and the project sub-route kinds, else `null`).
  Wire a runner: add `vitest` to `packages/web-core` devDependencies and
  `"test": "vitest run"` to its scripts; write `localProjectsRailModel.test.ts` covering
  mapping, colour determinism, and active-id resolution. Verify `pnpm --filter @vibe/web-core test`.
- **M4 — AppBar local mode.** Add `projectsEnabled?: boolean` to `AppBarProps`. Gate the
  cloud CTA with `if (!isSignedIn && !projectsEnabled)` and the create button with
  `if ((isSignedIn || projectsEnabled) && onCreateProject)`. Add the `appBar.projects.create`
  key (English: "Create project") to **all** locale files, and use it for the local create
  label instead of a bare literal. Verify `ui:check`, `ui:lint`, and the i18n scripts.
- **M5 — Shell wiring.** In `SharedAppLayout.tsx`: fetch local projects
  (`localProjectsApi.list()`, same pattern as `LocalProjectsList`), map with
  `toAppBarProjects`, pass `projects`, `projectsEnabled`, `activeProjectId` (derive from the
  current destination — no hardcoded `null`), `onProjectClick` →
  `appNavigation.goToProject(id)`, and `onCreateProject` → `appNavigation.goToProjects()`.
  Remove the `projects={[]}` placeholder. Verify `local-web:check` + `web-core:check`.
- **M6 — Live verification.** With `pnpm run dev` up (UI on `FRONTEND_PORT`, API from
  `/tmp/vibe-kanban/vibe-kanban.port`), use the browser harness to prove: the rail lists real
  local projects, clicking one opens its board, the active project is highlighted (including on
  a project sub-route), and the create button opens the create flow. Save screenshots +
  `NOTES.md` under `.context/evidence/local-projects-rail/`.
- **M7 — Refresh correctness.** Creating a project from either surface makes it appear in the
  rail without a manual reload (shared query/cache invalidation or an explicit refetch), and
  deleting a project removes it from the rail. Verified live; record evidence.
- **M8 — Quality pass.** `pnpm run format` (+ `pnpm --filter @vibe/ui run format`), update
  `docs/local-projects-kanban.md` with the rail UX, full `bash check.sh` green including the
  live section, `git status` clean.

## Quality standards

- **Tests:** pure logic lives in `localProjectsRailModel.ts` and is covered by vitest.
  Interactive behaviour is proven live (M6/M7) with screenshots, not asserted in code.
- **Docs:** `docs/local-projects-kanban.md` describes the rail: what it lists, click behaviour,
  active state, create flow, and the fact that it is local-only (no sign-in required).
- **Git:** one commit per milestone, Conventional Commits (`feat(projects): …`,
  `refactor(projects): …`, `test(projects): …`, `docs(projects): …`). Never commit with a red
  `check.sh` unless the milestone explicitly restores green later.
- **i18n:** every user-visible string goes through `t()`; new keys land in all 7 locales
  (`en`, `es`, `fr`, `ja`, `ko`, `zh-Hans`, `zh-Hant`); `check-unused-i18n-keys.mjs` must pass,
  so **remove** keys you orphan instead of leaving them.
- **Style:** no `any`, no non-null assertions to silence the compiler, no dead code, no
  commented-out blocks, no new dependencies beyond `vitest` (M3).
- **Reuse:** render rail projects with the existing `project-list` / `project-card` kinds in
  `AppBar`; do not build a parallel component.

## Assumptions

1. Work happens on the `drop-remote-support` branch (local projects + the de-remoted shell).
2. Locally `isSignedIn` is effectively always `false`; the cloud CTA code path stays in
   `AppBar` (shared with other shells) but must be bypassed when `projectsEnabled` is true.
3. `AppBarProject.color` is required by the shared component; local projects have no colour, so
   one is derived deterministically from the project id.
4. `AppBar` lives in `packages/ui` and is shared, so its cloud behaviour must keep working when
   `projectsEnabled` is not set.
5. The dev stack is `pnpm run dev` → Vite UI on `FRONTEND_PORT` (3003 as observed) and the API
   on the port in `/tmp/vibe-kanban/vibe-kanban.port` (`main_port`, 3004 as observed). The
   `check.sh` live section self-skips when nothing is reachable and costs no points.
6. `main` exists locally (needed by `scripts/check-i18n.sh`).
7. No Rust/backend change is required; `cargo check --workspace --exclude vibe-kanban-tauri`
   is green and `vibe-kanban-tauri` cannot build here (system GTK/glib missing) — that
   pre-existing environment failure is out of scope.
8. **Pre-existing red gates on this branch (do not chase them):** 26 `web-core` files are
   unformatted on `main` (unchanged by this branch), the repo carries 104 unused i18n keys on
   `main`, and `local-web`'s build only fits in an 8 GB Node heap. `check.sh` handles all three:
   prettier is scoped to goal-owned files, the i18n check is a ≤104 regression gate, and the
   build runs with CI's heap flag. Do **not** reformat the 26 unrelated files or mass-prune
   keys as part of this goal — record such cleanups in `IMPROVEMENTS.md` instead.

## Commands

- Gate: `bash check.sh` (`CHECK_FAST=1 bash check.sh` skips build/lint-heavy steps)
- Types: `pnpm run local-web:check && pnpm run web-core:check && pnpm run ui:check`
- Tests: `pnpm --filter @vibe/web-core test`
- i18n: `GITHUB_BASE_REF=main ./scripts/check-i18n.sh && node scripts/check-unused-i18n-keys.mjs`
- Format: `pnpm run format` then `pnpm --filter @vibe/ui run format` (writes repo-wide), or
  scope it to goal files: `pnpm --filter @vibe/web-core exec prettier --write <files>`
- Dev: `pnpm run dev` (UI `http://localhost:3003`, API `http://localhost:3004`)
