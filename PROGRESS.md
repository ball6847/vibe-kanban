# PROGRESS

Goal: see `GOAL.md`. Check: `bash check.sh` (add `SKIP_BUILD=1` for a fast run).

## Current state

- Baseline `0/22` → … → batch 31 `17/22` → batch 32 `19/22` → batch 33 `21/22` → **batch 34: `22/22`, exit 0**.
- **GOAL COMPLETE:** all 22 structural checks pass; build gate green (legacy-path-guard, local-web,
  web-core, ui, `cargo check --workspace --offline`); `cargo test --workspace` = **235 passed, 0 failed**.
- `web-core`, `local-web`, `ui`: 0 type errors. Rust workspace: 0 errors, 0 warnings.

## Batch 34 — drop the Electric DB dependencies (S20)

- Removed `@tanstack/electric-db-collection` + `@tanstack/react-db` from
  `packages/web-core/package.json` and `packages/local-web/package.json` (no source imports remained);
  refreshed `pnpm-lock.yaml` with `pnpm install --lockfile-only`.

**SCORE 21 → 22. `bash check.sh` exits 0.**

## Batch 33 — drop `shared_api_base` + `RemoteClientError` from the config route (S14, S21)

- `crates/server/src/routes/config.rs` — removed the `shared_api_base` field and its
  `remote_info().get_api_base()` wiring; inlined the `"remote_auth_unavailable"` degraded-slug literal
  and dropped the `RemoteClientError` import.
- Regenerated `shared/types.ts` (`pnpm run generate-types`) — it also dropped the stale
  `LinkPrToIssueRequest` / `ImportIssueAttachments` types left by earlier deletions.

## Batch 32 — delete the Cloud docs and remote-access page (milestone 11)

- `git rm -r crates/remote` — **357 files** (the cloud Axum server, migrations, Dockerfile, docker-compose).
- Root `Cargo.toml`: `exclude = ["crates/remote", "crates/relay-tunnel"]` → `exclude = ["crates/relay-tunnel"]`.
- `check.sh` S07: pattern tightened from `crates/remote` to `"crates/remote"` — the loose pattern matched the
  unrelated `crates/remote-info` workspace member.

`cargo check --workspace --offline` stays clean; build gate green. **SCORE 11 → 14 (S01, S07, S13).**

## Batch 29 — remove `VK_SHARED_API_BASE` config plumbing

- `crates/server/build.rs` + `crates/local-deployment/build.rs` — stop forwarding `VK_SHARED_API_BASE`
  (`VK_SHARED_RELAY_API_BASE` is relay and stays).
- `local-deployment/src/lib.rs` — dropped the `api_base` env read and `remote_info.set_api_base(...)`.
- `web-core/relayBackendApi.ts` — dropped the `VITE_VK_SHARED_API_BASE` fallback and the now-dead
  `syncRelayApiBaseWithRemote`; `vite-env.d.ts` — dropped the declaration. See `ASSUMPTIONS.md` #10.

## Batch 28 — remote sync out of the workspace git routes (flips S06)

- `git.rs` — `resolve_vibe_kanban_identifier` no longer looks up the remote issue (param renamed
  `_deployment`, always returns the local workspace id); removed 3
  `if let Ok(client) = deployment.remote_client()` blocks: the post-merge
  `sync_local_workspace_merge_to_remote`, and two `sync_workspace_to_remote` blocks (after push and
  after force-push). Dropped the orphaned `diff_stream` / `remote_sync` imports.

**SCORE 10 → 11.**

## Batch 27 — delete the import-issue-attachments route and its dead cluster

- `attachments.rs` — removed the `import_issue_attachments` handler, its route registration,
  `import_issue_attachments_from_remote`, the `ImportIssueAttachments{Request,Response}` +
  `ImportedIssueAttachment` structs, and the orphaned `FileService` / `RemoteClient` imports.
- `generate_types.rs` — dropped the two matching `::decl()` entries.
- `create.rs` — removed the attachment-markdown helper cluster that the deleted remote import was the
  only production caller of, **together with the 6 unit tests that only covered it** (GOAL.md tests
  rule), plus the orphaned `HashMap` import. `cargo check` warnings went 7 → 0.

## Batch 26 — remove PR-to-cloud sync from the workspace PR routes

- `pr.rs` — removed both `if let Ok(client) = deployment.remote_client()` blocks calling
  `remote_sync::sync_pr_to_remote` (after create-PR and after refresh-PR), plus the orphaned
  `remote_sync`, `PullRequestStatus` and `UpsertPullRequestRequest` imports.

## Batch 25 — remote sync out of the workspace core/create routes

- `crates/server/src/routes/workspaces/core.rs` — removed the archive/rename → `remote_sync::sync_workspace_to_remote`
  block, the `if query.delete_remote { client.delete_workspace(..) }` block, the now-dead `delete_remote`
  query field, and the orphaned `diff_stream`/`remote_sync` imports.
- `crates/server/src/routes/workspaces/create.rs` — removed the "import issue attachments from the remote"
  block and the `import_issue_attachments_from_remote` import; `linked_issue` is now destructured as
  `linked_issue: _linked_issue`.

`cargo check --workspace --offline` **passes**; all frontend checks stay at 0. Remote refs in
`routes/workspaces` down 20 → 15: `attachments.rs` 2, `git.rs` 8, `pr.rs` 5.

**Lesson (same trap as batch 3):** I first deleted `escape_markdown_label` /
`build_workspace_attachment_markdown` as "dead", but they are used by **unit tests** later in the file —
`cargo check` (lib) doesn't see `#[cfg(test)]` usage, so it reports them unused even though the tests
need them. Restored them. Never delete a helper just because the lib build calls it unused; grep the
whole file including tests first.

**Known warnings to reconcile (tracked in IMPROVEMENTS.md):** those two helpers plus
`ParsedAttachmentMarkdown` / `find_unescaped_char` / `parse_attachment_markdown_at` and
`ImportedIssueAttachment.attachment_id` are now referenced only from tests, so `cargo check` warns
"never used". Either delete the helpers **and** their tests, or move the cluster behind `#[cfg(test)]`.

## Batch 23 — container de-remoting + SPEC CORRECTION

**Finding:** `crates/relay-hosts/src/lib.rs` uses `RemoteClient::access_token()` and `RemoteInfo`, and
relay is a non-goal. So `remote_client.rs` / `crates/remote-info` **cannot be deleted** — S05/S06/S21 as
originally written were unsatisfiable. Redefined them to assert the *remote feature* is gone (details in
`ASSUMPTIONS.md` #9). This is a scope correction, not a lowered bar.

Real remote-feature code found and removed:
- `crates/local-deployment/src/container.rs` — deleted the "Sync workspace to remote after CodingAgent
  execution" block (it spawned `remote_sync::sync_workspace_to_remote`), the now-unused `remote_sync`
  import, and the `remote_client: Option<RemoteClient>` **field** from `LocalContainerService`
  (struct, constructor param, assignment, and the `remote_client.clone().ok()` argument in
  `crates/local-deployment/src/lib.rs`).
- `check.sh` — S05/S06/S21 redefined (see above).

`cargo check --workspace --offline` clean; **SCORE 9 → 10**.

**Remaining remote-feature surface (milestone 7, now the biggest item):** `deployment.remote_client()`
call sites in `crates/server/src/routes/workspaces/{links,core,create,git}.rs` (5 sites), the
`remote_sync` service, and `crates/server/src/routes/config.rs`'s `remote_auth_degraded` /
`RemoteClientError` handling (milestone 8).

## Batch 22 — milestone 6: delete the local remote HTTP bridge

- Deleted `crates/server/src/routes/remote/` (10 files) and its registration in
  `crates/server/src/routes/mod.rs` (`pub mod remote;` + `.nest("/remote", remote::router())`).
- `crates/server/src/bin/generate_types.rs` — dropped `LinkPrToIssueRequest::decl()`.
- `packages/web-core/src/shared/lib/api.ts` — removed `issuePrsApi.linkToIssue` (it POSTed to the deleted
  `/api/remote/pull-requests/link`) and the `LinkPrToIssueRequest` import.
- `shared/hooks/useCreateWorkspace.ts` + `shared/components/CreateChatBoxContainer.tsx` — removed the
  now-dead `linkToIssue` parameter and its workspace-linking call.

`cargo check --workspace --offline` passes; all three frontend checks stay at 0. **SCORE 8 → 9.**

**Note:** `shared/types.ts` still declares `LinkPrToIssueRequest` (generated from the now-deleted Rust
struct). It is harmless but will be regenerated away by `pnpm run generate-types` — add that to the
milestone-13 cleanup.

## Batch 21 — finish the frontend; milestones 4 + 5 complete

- `features/create-mode/model/useCreateModeState.ts` — replaced the last `shared/remote-types` import
  with a local structural `RemoteWorkspace` type; removed the `useShape` import, the Electric-backed
  “resolve linked issue” query and its effect.
- `shared/types/commandBar.ts` — removed the dead `{ type: 'issue'; issue: Issue }` union member (it was
  never constructed) and the `Issue` import.
- `shared/components/WYSIWYGEditor.tsx` — the local `fetchAttachmentSasUrl` stub is now actually passed
  to `createImageNode` / `createAttachmentNode` (it is a required option).
- **Milestone 5:** `local-web/src/routes/__root.tsx` dropped the `UserProvider` wrapper;
  `app/providers/ConfigProvider.tsx` dropped `setRemoteApiBase` / `shared_api_base` and the now-unused
  `userSystemInfo`.

`web-core` 7 → 0; `local-web` 9 → 0; `ui` 0. **All frontend packages type-check clean.**

## Batch 20 — type imports + orphaned locals

`shared/remote-types` consumers down from 5 files to **2**; `@/shared/lib/remoteApi` references to **0**.

- Added a local `shared/types/issuePriority.ts` (`'urgent' | 'high' | 'medium' | 'low'`, copied from the
  deleted generated file) and repointed `types/selectionItems.ts`, `stores/useKanbanIssueComposerStore.ts`,
  `stores/useUiPreferencesStore.ts` at it.
- `shared/hooks/useActionVisibilityContext.ts` — dropped the unused `routeProjectId` and `destination`
  locals and the `useCurrentAppDestination` import.
- `shared/dialogs/command-bar/commandBar/useResolvedPage.ts` — removed the `issueActions` icon entry
  and the orphaned `KanbanIcon` import.
- `shared/components/WYSIWYGEditor.tsx` — the cloud `fetchAttachmentSasUrl` from the removed remote API
  is now a local module-level stub (`async (): Promise<string> => ''`), since `fetchAttachmentUrl` is a
  required option of the `@vibe/ui` image/attachment nodes. **Runtime gap:** cloud attachment images will
  no longer resolve — tracked in `IMPROVEMENTS.md`.

`web-core:check` 11 → 7; `local-web:check` 13 → 9.

## Batch 19 — the organization domain

- Deleted 4 org hooks: `useOrganizationMembers`, `useOrganizationInvitations`, `useOrganizationMutations`
  (all three were **orphans**) and `useUserOrganizations`.
- `pages/export/ExportPage.tsx` — orgs → empty list; the `/v1/export` remote call switched to the local
  transport (`makeLocalApiRequest('/api/export', …)`).
- `shared/components/ui-new/containers/SharedAppLayout.tsx` — orgs → `[]`, auto-select-org effect and
  the mobile drawer's org-name lookup removed, `useMemo` import dropped.
- `shared/lib/api.ts` — removed the whole `organizationsApi` object, the `handleRemoteResponse` helper
  (only it used it), the `makeRemoteRequest` (`@/shared/lib/remoteApi`) import and **12** now-orphaned
  response-type imports.

`web-core:check` 13 → 11; `local-web:check` 15 → 13.

## Batch 18 — `shared/remote-types` consumers, round 1

`shared/remote-types` importers down from 8 files to **5**.

- Deleted `shared/lib/resolveRelationships.ts` — **orphan** (no importers).
- `shared/lib/relayBackendApi.ts` — removed the unused `createRemoteSession()` and the
  `CreateRemoteSessionResponse` remote-types import, plus the now-orphaned `parseErrorResponse` helper.
  The relay enrolment/signing-session functions stay (relay is out of scope).
- `shared/lib/api.ts` — removed `remoteProjectsApi` (no consumers) and its `ListRemoteProjectsResponse`
  type, plus the `RemoteProject` remote-types import.

`web-core:check` 16 → 13; `local-web:check` 16 → 15.

**Deliberately deferred:** `organizationsApi` in `shared/lib/api.ts` still uses `makeRemoteRequest`, and
it is consumed by 4 **org hooks** — `useOrganizationMembers`, `useOrganizationInvitations`,
`useOrganizationMutations`, `useUserOrganizations`. Those 4 + `organizationsApi` + the `makeRemoteRequest`
import form one unit and must be removed together (next batch), along with any consumers of the org
hooks.

## Batch 17 — `ActionExecutorContext.remoteWorkspaces`

Removed the last remote-workspace data flow from the action layer:
- `shared/actions/index.ts`: deleted the `resolveLinkedIssue` helper and its 2 call sites
  (`linkedIssue` → `undefined`); `linkedIssueSimpleId` → `undefined`;
  `isLinkedToIssue: Boolean(remoteWs?.issue_id)` → `false`; `issueIdentifier` → `undefined`.
- `shared/types/actions.ts`: dropped the `remoteWorkspaces: RemoteWorkspace[]` field and the
  `shared/remote-types` import.
- `shared/providers/ActionsProvider.tsx`: dropped the `remoteWorkspaces: []` placeholder.
- Deleted `shared/lib/workspaceDefaults.ts` — **entirely unused** (no importers) and remote-coupled
  via `shared/remote-types`.

`web-core:check` 18 → 16; `local-web:check` 17 → 16.

## Batch 16 — `useUserContext` / `useProjectContext` + the sidebar project filter (one unit)

Deleted `shared/hooks/useUserContext.ts` and `shared/hooks/useProjectContext.ts`. Repaired all three
referrers:

- `pages/workspaces/WorkspacesSidebarContainer.tsx` — removed `useUserContext`,
  `useAllOrganizationProjects`, `useUserOrganizations` and `type Project` from `shared/remote-types`;
  removed `remoteWorkspaces`, `remoteProjectByLocalId`, `orgNameById`, `projectGroups` and the remote
  branch of `projectOptions`; deleted the project-filter branches from both `filteredActiveWorkspaces`
  and `filteredArchivedWorkspaces`. `projectOptions` now holds only the "No project" entry, so the
  sidebar UI contract is unchanged.
- `features/create-mode/model/CreateModeProvider.tsx` — `remoteWorkspaces` → `[]`,
  `remoteWorkspacesLoading` → `false`.
- `shared/providers/ActionsProvider.tsx` — dropped the `UserContext`/`ProjectContext` reads and their
  deps; dropped the now-unused `useContext` import.

`web-core:check` 26 → 18; `local-web:check` 25 → 17.

**Still outstanding (next batch):** `ActionExecutorContext.remoteWorkspaces` (declared in
`shared/types/actions.ts` L80, importing `RemoteWorkspace` from `shared/remote-types`) is now always
`[]` but still exists. Remove it together with its 5 consumers in `shared/actions/index.ts`
(L100, L184, L286, L362, L842) and the `remoteWorkspaces` parameter of
`shared/lib/workspaceDefaults.ts` (L17, L43, L74) — the type field cannot go before its consumers do.

## Batch 15 — remote project data hooks

Deleted 3 files: `shared/lib/projectOrder.ts` (orphan — its only consumer, `SharedAppLayout`, was
cleaned in batch 14), `shared/hooks/useOrganizationProjects.ts`,
`shared/hooks/useAllOrganizationProjects.ts`.

Repaired 2 referrers: `pages/export/ExportPage.tsx` (remote project list → empty local list) and
`shared/dialogs/settings/settings/ReposSettingsSection.tsx` (linked-remote-projects scan → empty).

**Deferred (deliberately):** `pages/workspaces/WorkspacesSidebarContainer.tsx`. It consumes
`useAllOrganizationProjects` **and** `useUserContext` **and** `import type { Project } from 'shared/remote-types'`,
and the project filter it builds (`projectGroups`, `remoteProjectByLocalId`) is threaded through the
sidebar's filter dropdowns. Doing it piecemeal would leave it half-broken, so it moves to its own batch
with the `useUserContext`/`useProjectContext` removal.

`web-core:check` 30 → 26; `local-web:check` 28 → 25.

## ⚠️ TOOLING HAZARDS — read before any file edit

1. **Never issue a `bash` write and an `edit`/`write` to the SAME file in the same tool block.** They
   race and truncate the file to 0 bytes. This destroyed `shared/hooks/useActionVisibilityContext.ts`
   twice in batch 13. Recovery: `git checkout HEAD -- <file>`, redo as a single writer.
   **Always** confirm `wc -l <file>` after a bulk edit; 0 means clobbered.
2. **Line-range `sed` is dangerous on files that were already edited this session** — line numbers
   drift and a range can swallow a needed closing token. In batch 14 `sed '102,107d'` ate the closing
   `}, [...]); ` of a `useEffect`, producing `')' expected` at EOF with only 1–2 reported errors.
   Prefer the `edit` tool with unique anchored text; if you must use ranges, re-read the region
   immediately before and after, and re-run the type check right away.
3. **Short `oldText` is ambiguous easily** — `  onProjectClick: ...` is a substring of the
   6-space-indented variant. Always include a neighbouring line.

## Batch 14 — de-remote the app shell (`SharedAppLayout`)

Removed the remote project data layer and project navigation from the shell:
- imports: `useShape`, `sortProjectsByOrder`, `PROJECTS_SHAPE` / `PROJECT_MUTATION` / `RemoteProject`,
  `NavbarContainer` (module was deleted in batch 3), `DropResult`, `KanbanIcon`.
- removed the `useShape(PROJECTS_SHAPE, …)` call, `orgProjects`, `sortedProjects`, `orderedProjects`,
  `isSavingProjectOrder`, `isLoading`, the sync `useEffect`, and `handleProjectsDragEnd`.
- removed both `<NavbarContainer>` renders (desktop + mobile) and the mobile drawer's project list.
- `<AppBar projects={[]} …>`, dropped `onProjectsDragEnd` / `isSavingProjectOrder` / `isLoadingProjects`.
- `packages/ui/AppBar.tsx`: `onProjectsDragEnd` now optional, guarded with `?? (() => {})`.

`web-core:check` 33 → 30; `local-web:check` 32 → 28; `ui:check` 0.

## Batch 13 — remove the project/kanban navigation model (one unit)

Rewrote `shared/lib/routes/appNavigation.ts` to drop all 5 project destination kinds, the 5
`goToProject*` methods, `ProjectDestination`, `isProjectDestination`, `getProjectDestination`,
`KanbanSidebarMode`, `KanbanRouteState`, `resolveKanbanRouteState`.

Deleted 3 kanban-only files: `shared/hooks/useProjectWorkspaceCreateDraft.ts` (orphan),
`shared/hooks/useCurrentKanbanRouteState.ts`, `shared/lib/firstProjectDestination.ts`.

Repaired 7 consumers: `local-web/AppNavigation.ts` (8 route `case`s, 5 destination `case`s, 5
`goToProject*` methods), `SharedAppLayout`, `useActionVisibilityContext`, `RootRedirectPage`,
`OnboardingSignInPage`, `types/commandBar.ts` (`issueActions` page id), `command-bar/actions/pages.ts`,
and `packages/ui/AppBar.tsx` (`onProjectClick` now optional).

**Error path: 36 → 90 (referrer spike) → 33.** Net −3 web-core / −3 local-web despite deleting a whole
navigation model.

## Batch 12 — kanban selection handlers + issue actions (one unit)

Executed exactly as scoped in batch 11. Removed all 6 command-bar selection handlers as one unit with
their 11 consumers:

- `shared/types/actions.ts` + `shared/hooks/useActions.ts`: dropped the 6 declarations.
- `shared/providers/ActionsProvider.tsx`: dropped the 6 `useCallback` impls (each dynamically imported a
  deleted dialog), the `executorContext` entries + deps, and a **third** block the earlier recon missed —
  the `value` useMemo entries + its dep array. Verified 0 remaining references.
- `shared/actions/index.ts`: removed 11 actions (`ChangeIssueStatus`, `ChangePriority`, `ChangeAssignees`,
  `ChangeNewIssueAssignees`, `MakeSubIssueOf`, `AddSubIssue`, `LinkWorkspace`, `MarkBlocking`,
  `MarkBlockedBy`, `MarkRelated`, `MarkDuplicateOf`) plus `RemoveParentIssue` (used the already-dead
  `bulkUpdateIssues` import), via a block-aware script rather than 18 anchors.
- `shared/command-bar/actions/pages.ts`: removed the whole `issueActions` page (`layoutMode === 'kanban'`).
- Deleted `shared/keyboard/useIssueShortcuts.ts` + its `keyboard/index.ts` export and `_app.tsx` usage.
- Fixed orphans: 6 icons in `actions/index.ts`, `XIcon`, `useParams` in `WorkspacesSidebarContainer`.

**Error path: 45 → 63 (expected referrer spike) → 36.** `web-core` 45 → 36, `local-web` 44 → 35.

**Caution:** the batch-11 recon under-counted `ActionsProvider` handler sites — there were three
(impls, `executorContext`, `value`), not two. Always grep the handler name after deletion:
`grep -n <handler> <file>` must return nothing.

## Batch 11 — kanban bulk-action bar + dangling command-bar action refs

- Deleted `features/kanban/ui/BulkActionBarContainer.tsx` — **orphaned** (its only importer was the
  deleted kanban page). `features/kanban/` is now gone entirely.
- `shared/command-bar/actions/pages.ts`: removed the 3 dangling references to actions deleted in
  batch 5 (`Actions.ProjectSettings`, `Actions.ChangeNewIssueStatus`, `Actions.ChangeNewIssuePriority`).

`web-core:check` 48 → 45; `local-web:check` 47 → 44.

## Batch 12 — FULLY SCOPED, execute next (do not re-investigate)

The 6 command-bar selection handlers must be removed **as one unit with their 11 consumers**, or the
error count rises. Exact scope:

**Handlers (6)** — declared in `shared/types/actions.ts` (L71–90), `shared/hooks/useActions.ts`
(L30–60), implemented in `shared/providers/ActionsProvider.tsx` (L109–200), and wired into
`executorContext` (L217–222) + its dep array:
`openStatusSelection`, `openPrioritySelection`, `openAssigneeSelection`, `openSubIssueSelection`,
`openWorkspaceSelection`, `openRelationshipSelection`.
Each impl dynamically imports a **deleted** dialog (`ProjectSelectionDialog` ×4, `AssigneeSelectionDialog`,
`WorkspaceSelectionDialog`) — that is the whole reason `ActionsProvider` has 6 errors.

**Consumers (11 actions in `shared/actions/index.ts`)** — all use one of the above, all kanban/issue
only: `ChangeIssueStatus` (L1217), `ChangePriority` (L1230), `ChangeAssignees` (L1243),
`ChangeNewIssueAssignees` (L1256), `MakeSubIssueOf` (L1269), `AddSubIssue` (L1282) (also calls
`navigateToCreateSubIssue`), `LinkWorkspace` (L1342), `MarkBlocking` (L1402), `MarkBlockedBy` (L1422),
`MarkRelated` (L1442), `MarkDuplicateOf` (L1462).

**Watch for orphans** after removal: `ArrowsLeftRightIcon`, `ArrowFatLineUpIcon`, `UsersIcon`,
`TreeStructureIcon`, `PlusIcon`, `LinkIcon`, `ProhibitIcon`, `CopyIcon`, `navigateToCreateSubIssue`.

## Batch 10 — remote project creation + cloud hosts (3 layers)

Deleted 2 files: `shared/dialogs/org/CreateRemoteProjectDialog.tsx` (dir now empty and removed),
`shared/hooks/useRemoteCloudHosts.ts`.

Repaired all three layers that referenced them:
- `packages/ui/src/components/AppBar.tsx`: `onCreateProject` made optional and the "Create project"
  item only pushed when it is provided.
- `packages/ui/src/components/WorkspacesSidebar.tsx`: removed the `activeRemoteHost` /
  `onOpenRemoteHostSettings` props, the remote-host indicator block, and the now-unused
  `AppBarHostStatus` import.
- `web-core/.../SharedAppLayout.tsx`: removed `CreateRemoteProjectDialog`, `handleCreateProject`,
  the `onCreateProject` / `hosts` props and the "Create Project" button (+ orphaned `PlusIcon`).
- `web-core/.../WorkspacesSidebarContainer.tsx`: removed `useRemoteCloudHosts`, `activeRemoteHost`,
  `handleOpenRemoteHostSettings`, and the now-orphaned `SettingsDialog` import and `routeHostId`.

`web-core:check` 51 → 48; `local-web:check` 50 → 47; `ui:check` 0.

**Caution learned:** when replacing an `if (...) {` line, keep the lines that follow it. A guard edit
here silently deleted `projectSectionItems.push({` and its `key:`, producing 8 syntax errors in
`AppBar.tsx`. Always re-run the type check immediately after a guard-style edit.

## Batch 9 — dead org dialogs + sync-error provider

Deleted 5 files (verified zero live referrers before deletion):
- `shared/dialogs/org/CreateOrganizationDialog.tsx`, `DeleteRemoteProjectDialog.tsx`,
  `InviteMemberDialog.tsx` — org/member remote dialogs referenced by nothing.
- `shared/providers/SyncErrorProvider.tsx` + `shared/hooks/useSyncErrorContext.ts` — Electric sync-error
  UI. The hook was referenced only by the provider; the provider only by `SharedAppLayout`.

Repaired the single referrer, `SharedAppLayout.tsx`: removed the `SyncErrorProvider` import and the
`<SyncErrorProvider>` / `</SyncErrorProvider>` wrapper tags (children preserved). Indentation drift
is intentional — `pnpm run format` fixes it at the end.

`web-core:check` 53 → 51; `local-web:check` 52 → 50. No new errors.

**Next batch is pre-scoped** (verified by a domain-importer scan) — it needs `packages/ui` edits, so
it was split out to keep this batch low-risk:
- `shared/dialogs/org/CreateRemoteProjectDialog.tsx` ← `SharedAppLayout.handleCreateProject`
- `shared/hooks/useRemoteCloudHosts.ts` ← `SharedAppLayout` (`hosts={remoteCloudHosts}`) and
  `WorkspacesSidebarContainer` (`activeRemoteHost`)
- `AppBar.tsx`: `hosts` is optional (drop the prop), but `onCreateProject` is **required**, so
  making it optional + removing the "Create Project" button is part of that batch.

## Batch 8 — delete the kanban page domain

Deleted 14 files:
- `web-core/src/pages/kanban/` (whole dir): `IssueRelationshipsSectionContainer`, `IssueWorkspacesSectionContainer`,
  `LocalProjectKanban`, `ProjectKanban`, `ProjectSunsetPage`.
- `local-web/src/routes/_app.projects.*` (all 8 project/issue routes).
- `web-core/src/shared/hooks/useOrgContext.ts` — newly orphaned once the kanban domain went.

Verified via a domain-importer scan that every importer of `pages/kanban/**` was either inside that
dir or one of the 8 deleted routes. `shared/dialogs/kanban/` no longer exists (removed in batch 3).

`web-core:check` 58 → 53; `local-web:check` 53 → 52.

**Deliberately excluded:** `features/create-mode/**`. `useCreateMode` is imported by
`CreateChatBoxContainer` / `CreateModeRepoPickerBar` (core workspace creation), so it is entangled
with a core feature and needs inspection before removal, not blanket deletion.

**Known latent issue (next batch):** `local-web/src/app/navigation/AppNavigation.ts` still maps the
8 deleted project/issue routes (8 `case` blocks ~L79–165, 9 `to:` entries ~L238–301). It compiles
only because `routeTree.gen.ts` is stale; a regen would break it. Must be repaired, not deleted —
several of those paths also host workspace pages.

## Batch 7 — delete the notification domain (domain-based, not graph-based)

The leaf finder now reports `doomed=0`: every remaining broken file has a live importer, so leaf-first
deletion is exhausted. Switched to **domain-based** deletion — pick a whole remote-backed feature
and remove it, then repair the (few) core files that referenced it.

Deleted (8 files):
- `web-core`: `shared/hooks/useNotifications.ts`, `shared/hooks/useNotificationMembers.ts`,
  `shared/lib/notifications.ts`, `shared/lib/notificationMessage.ts`,
  `pages/workspaces/NotificationsPage.tsx`, `pages/workspaces/AppBarNotificationBellContainer.tsx`
- `local-web`: `app/notifications/AppSystemNotifications.tsx`, `routes/_app.notifications.tsx`

Repaired the 2 core referrers: `SharedAppLayout.tsx` (dropped the `notificationBell` prop) and
`local-web/src/app/entry/App.tsx` (dropped `<AppSystemNotifications />`).

`web-core:check` 65 → 58; `local-web:check` 61 → 53. No new errors.

## Batch 6 — delete the Electric test page (biggest single win)

- `web-core/src/pages/workspaces/ElectricTestPage.tsx` — **30 errors by itself**.
- `local-web/src/routes/_app.workspaces_.electric-test.tsx` — its only importer.

`web-core:check` 95 → 65 errors. `routeTree.gen.ts` still lists the deleted route, but it carries
`// @ts-nocheck`, so the stale entries are harmless and vanish on the next `vite` run (see
`ASSUMPTIONS.md` #3).

## Batch 5 (previous) — remove remote settings sections and their entry points

Deletions are done; the remaining red is a **dependency chain**: removing a node resolves its own
errors and exposes the errors in whatever referenced it.

1. **`settingsRegistry.tsx`**: dropped `organizations` and `remote-projects` from
   `SettingsSectionType`, `SettingsSectionInitialState`, `SETTINGS_SECTION_DEFINITIONS`, the switch,
   and the now-unused icons/imports.
2. **`RelaySettingsSection.tsx`**: the deleted `RemoteCloudHostsSettingsCard` was its only remote
   dependency. Removed the import, the client-role panel + client role choice, the
   `RemoteRelaySettingsSectionContent` cloud panel, the now-unused `SignInPrompt` / `InlineNotice` /
   `DesktopIcon` / `useAppRuntime`. `RelaySettingsSectionContent` now always renders the local
   content. See `ASSUMPTIONS.md` #7.
3. **`SettingsDialog.tsx`**: the "no hosts" fallback no longer points at `'organizations'`.
4. **`AppBarUserPopoverContainer.tsx`**: removed `handleOrgSettings` (opened `'organizations'`).
5. **`shared/actions/index.ts`**: removed the `ProjectSettings` action (`'remote-projects'`), the
   `ChangeNewIssueStatus` / `ChangeNewIssuePriority` actions (used the deleted
   `ProjectSelectionDialog`), and the dead `bulkUpdateIssues` import from `shared/lib/remoteApi`.

Net error delta 95 → 95: 6 resolved (`actions/index.ts` TS2307 ×3, `RelaySettingsSection` TS2307,
`settingsRegistry` TS2307 ×2), 6 exposed (`command-bar/actions/pages.ts` ×3,
`keyboard/useIssueShortcuts.ts` ×2, `actions/index.ts` TS2304 ×1).

## Next steps

**The frontend half of the goal is done (GOAL.md milestones 4 + 5). The whole build gate is green.**
Remaining work is the backend/repo half — GOAL.md milestones 6–12:

6. `crates/server/src/routes/remote/` (10 files) + its `.nest("/remote", ...)` registration.
7. `crates/services/src/services/remote_client.rs` (+ its `mod`/re-export) and the `crates/remote-info` crate.
8. Config plumbing: `shared_api_base`, `remote_auth_degraded`, `VK_SHARED_API_BASE` in `crates/server/`,
   `crates/local-deployment/`, `npx-cli/` (flips S13/S14).
9. `crates/remote/` + the root `Cargo.toml` `[workspace] exclude` entry (flips S01/S07).
10. Root `package.json` remote scripts + their `check`/`format`/`backend:*` chain references;
    `.github/workflows/remote-*.yml`; `scripts/migrate-remote-web-structure.mjs` (flips S08/S09/S10).
11. `docs/cloud/` + `docs/remote-access.mdx` + inbound links in `docs/docs.json` (flips S11/S12).
12. `@tanstack/electric-db-collection` / `@tanstack/react-db` deps + `pnpm install` (flips S20).

Note: steps 6–9 will break `cargo check --workspace` until each referrer is repaired — the Rust side
now becomes the source of the error count, exactly as the frontend did during batches 3–21.

## Decisions

- Interpretation locked in `GOAL.md` ("Evidence"): `crates/server/src/routes/remote/*` proxies the
  cloud client, so local kanban/issues/org UI is in scope.
- `relay-*` crates out of scope; see `ASSUMPTIONS.md` for how that interacted with the host picker
  and the relay client-role panel.
- Build gate uses `cargo check --workspace --offline` (no git credentials for the `ts-rs` git dep).
- **Never delete a file just because the finder lists it as a leaf.** Verify its imports are
  *remote* deletions; if it imports a core file, repair the file instead.
- `scripts/find-remote-only-web-core.mjs` is a temporary goal aid — delete at the end
  (tracked in `IMPROVEMENTS.md`).
