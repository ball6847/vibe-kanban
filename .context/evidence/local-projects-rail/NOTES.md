# Evidence — cloud-style local projects rail (M6)

Date: 2026-09-23. Stack: `pnpm run dev` → UI :3003, API :3004 (freshly restarted; the long-lived
dev server had a stale Vite module graph from the `appNavigation.ts` edits).

Seed: two projects created via `POST /api/projects` — "Alpha Board" (`be0a71ae-…`),
"Rail Demo" (`93807132-…`).

## Verified live

| Claim | How | Result |
| --- | --- | --- |
| Rail lists local projects | AX snapshot of the rail | `Alpha Board` (AB), `Rail Demo` (RD) tiles + `Create project`; the cloud "Sign in to view projects" CTA is gone (the remaining `Sign in` at y≈863 is the user popover) |
| Click → board | click the `Alpha Board` tile | URL `/projects/be0a71ae-8293-4e32-a791-47d5f216406a` = Alpha Board's id (checked against `GET /api/projects`) |
| Active highlight | computed style of both tiles on the board route | active `rgba(109, 87, 219, 0.2)` / `rgb(109, 87, 219)`; idle `rgb(33, 33, 33)` / `rgb(196, 196, 196)` (`02-active-project-highlight.jpeg`) |
| Create affordance | click `Create project` in the rail | lands on `/projects`, title `Projects | Vibe Kanban`, composer input placeholder `New project…` (`01-create-project-lands-on-projects.jpeg`) |

## Bug found and fixed by this milestone

The first live check showed the active tile at `rgba(0, 0, 0, 0)` — active detection worked (it was
not the idle `bg-primary`), but the highlight was invisible. `AppBar` builds
`hsl(${project.color} / 0.2)`, and the model emitted a bare hue (`"210"`), so that declaration was
invalid and dropped. Fixed by emitting full `H S% L%` triples in `localProjectsRailModel.ts`; the
unit test now asserts the `H S% L%` shape so the regression cannot come back.

## Not yet verified (M7)

- Creating/deleting a project updates the rail without a manual reload (react-query cache key
  `['local-projects']` is currently not invalidated by the list page's mutations).
