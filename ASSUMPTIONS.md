# ASSUMPTIONS — cloud-style local projects rail

Inherits the baseline assumptions in GOAL.md (see its "Assumptions" section). Additions:

1. `goToProjects`/`{ kind: 'projects' }` are placed next to `goToExport` in the union and
   interface (grouping "leaf" pages together) — ordering only, no behavioural impact.
2. `ProjectDestinationKind` deliberately excludes `'projects'`: that type drives kanban
   issue/workspace resolution, and the index page has no project id.
3. Pre-existing red gates (26 unformatted files, 104 unused keys, 8 GB build heap) are handled
   by `check.sh` scoping/baselining rather than by changing repo-wide state, to keep the diff
   surgical.
