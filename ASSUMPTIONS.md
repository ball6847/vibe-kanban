# ASSUMPTIONS — cloud-style local projects rail

Inherits the baseline assumptions in GOAL.md (see its "Assumptions" section). Additions:

1. `goToProjects`/`{ kind: 'projects' }` are placed next to `goToExport` in the union and
   interface (grouping "leaf" pages together) — ordering only, no behavioural impact.
2. `ProjectDestinationKind` deliberately excludes `'projects'`: that type drives kanban
   issue/workspace resolution, and the index page has no project id.
3. Pre-existing red gates (26 unformatted files, 104 unused keys, 8 GB build heap) are handled
   by `check.sh` scoping/baselining rather than by changing repo-wide state, to keep the diff
   surgical.
4. `AppBar` interpolates `project.color` into `hsl(${color})` and `hsl(${color} / 0.2)`, so the
   rail model must emit full `H S% L%` triples. A bare hue ("210") silently drops the active
   background (found live in M6); the unit test asserts the triple shape.
5. A long-running Vite dev server can hold a stale module graph after edits to exported types
   (`appNavigation.ts`); a dev-server restart is required before live checks, and its HMR errors
   are not evidence of a broken build (`vite build` is part of the gate).
