# GOAL — Completely drop the `remote` feature (UI + API)

## Refined objective

Remove the **Vibe Kanban Cloud / shared-API "remote" feature** from this repository, end to end:
the cloud server, the hosted SPA, the local server's remote bridge, the desktop/local client's
remote API + ElectricSQL sync layer, and every UI surface that depends on them — while keeping the
repository building, type-checking, and passing its remaining tests.

"Remote" here means *the cloud/shared-API product surface*, NOT git remotes or SSH remotes.

### Evidence for this interpretation (do not re-litigate mid-run)
- `crates/server/src/routes/remote/issues.rs:28` → `deployment.remote_client()?` — the local
  server's `/api/remote/*` routes are **thin proxies to the cloud client**. There is no local
  issues/projects DB. So the local kanban/issue/project UI is cloud-backed and is in scope.
- `crates/server/src/routes/mod.rs:57` → `.nest("/remote", remote::router())`.
- `packages/local-web/src/app/providers/ConfigProvider.tsx:29` → `setRemoteApiBase(...shared_api_base)`.

## Scope

### In scope (delete or de-remote)
1. `crates/remote/` (357 files) — cloud Axum server + Electric + migrations.
2. `packages/remote-web/` (87 files) — hosted React SPA.
3. `shared/remote-types.ts` — generated remote TS types.
4. `crates/server/src/routes/remote/` (10 files) + its `.nest("/remote", ...)` registration.
5. `crates/services/src/services/remote_client.rs` + re-exports in `crates/services/src/lib.rs`.
6. `crates/remote-info/` crate.
7. Remote config plumbing: `shared_api_base`, `remote_auth_degraded`, `VK_SHARED_API_BASE` in
   `crates/server/`, `crates/local-deployment/`, `packages/local-web/`, `npx-cli/`.
8. `packages/web-core/` remote UI: `shared/providers/remote/`, `shared/lib/electric/`,
   `shared/integrations/electric/`, `integrations/remote/`, `shared/lib/remoteApi.ts`,
   and the pages/routes/hooks that consume them.
9. `packages/local-web/` remote wiring: `UserProvider` in `routes/__root.tsx`, remote-only routes
   (`notifications`, `projects.*`, `issues.*`, `electric-test`), and ConfigProvider remote callbacks.
10. Build/CI/docs/deps: root `Cargo.toml` `exclude`, root `package.json` remote scripts,
    `.github/workflows/remote-*.yml`, `scripts/migrate-remote-web-structure.mjs`,
    `docs/cloud/`, `docs/remote-access.mdx`, `@tanstack/electric-db-collection` / `@tanstack/react-db`
    dependencies, lint/format/check script chains.

### Non-goals (do NOT touch)
- `crates/relay-*`, `crates/relay-tunnel*`, relay hosts/webrtc/ws — a **separate** feature.
- Git/SSH "remote" wording (`git remote`, remote SSH host settings) — legitimate, unrelated.
- The `api-types` crate itself — it is shared by `server`, `services`, `mcp`, `local-deployment`.
  Prune a module from it **only** after proving nothing outside the removed code references it.
- Rewriting or re-designing remaining local features (workspaces, hosts, diffs, terminals, PRs).
- Adding replacement features. This goal deletes; it does not build alternatives.

## Measurable completion criteria

`bash check.sh` exits 0 **and** prints `SCORE: N/N`.

Hard gates (all must hold):
- All 22 structural checks in `check.sh` pass.
- `pnpm run local-web:legacy-path-guard`, `local-web:check`, `web-core:check`, `ui:check` all exit 0.
- `cargo check --workspace --offline` exits 0.
- No source file imports the deleted modules (checked structurally by S13/S19/S21/S22).

Loop mode is **endless**: after `SCORE: N/N`, keep raising quality via `IMPROVEMENTS.md`
(see Quality standards). Declare `LOOP_DONE:` only when the check is green.

## Milestone roadmap (small, ordered steps)

Work top to bottom. Keep `PROGRESS.md` current after every step. Commit after each numbered step.

1. **Baseline.** Run `bash check.sh` and record the score in `PROGRESS.md`. Confirm `git status` clean.
2. **Delete the hosted SPA.** Remove `packages/remote-web/`. Fix `pnpm-workspace.yaml` if needed.
3. **Delete generated remote types.** Remove `shared/remote-types.ts`.
   (Executed together with step 4 as one substrate-deletion batch: the sync layer and the generated
   types are worthless without each other. Importers are then fixed in step 4 / step 13.)
4. **Remove remote UI from `web-core`.** Delete `shared/providers/remote/`, `shared/lib/electric/`,
   `shared/integrations/electric/`, `integrations/remote/`, `shared/lib/remoteApi.ts`.
   Then fix every importer (≈100 files) — delete remote-only pages/hooks/components rather than
   stubbing them.
5. **Remove remote wiring from `local-web`.** Drop `UserProvider` from `routes/__root.tsx`, delete
   remote-only routes (`_app.notifications.tsx`, `_app.projects.*`, `_app.workspaces_.electric-test.tsx`),
   and the `setRemoteApiBase` call in `ConfigProvider.tsx`.
6. **Remove the local server bridge.** Delete `crates/server/src/routes/remote/` and its `nest`.
7. **Remove remote client + info.** Delete `crates/services/src/services/remote_client.rs`
   (and its `mod`/re-export) and the `crates/remote-info/` crate.
8. **Remove remote config plumbing.** Strip `shared_api_base`, `remote_auth_degraded`,
   `VK_SHARED_API_BASE` from `crates/server/`, `crates/local-deployment/`, `npx-cli/`, and build scripts.
9. **Delete the cloud server.** Remove `crates/remote/` and the `crates/remote` entry in the root
   `Cargo.toml` `[workspace] exclude`.
10. **Clean manifests and CI.** Root `package.json`: drop `remote:*`, `remote-web:*` scripts and their
    references inside `check`/`format`/`backend:*` chains. Delete `.github/workflows/remote-*.yml`
    and `scripts/migrate-remote-web-structure.mjs`.
11. **Clean docs.** Delete `docs/cloud/` and `docs/remote-access.mdx`; fix inbound links in `docs/docs.json`.
12. **Clean deps.** Remove `@tanstack/electric-db-collection` and `@tanstack/react-db` from
    `packages/*/package.json`; run `pnpm install` to refresh the lockfile.
13. **Green the build.** Fix all remaining compile/type errors. `bash check.sh` must report `N/N`.
14. **Improvement backlog.** Populate `IMPROVEMENTS.md` with ≥5 concrete items (exact file paths +
    one-line acceptance criterion each) for continued cleanup, then work them top-down.

## Quality standards

- **Verification:** after every milestone run `bash check.sh`; before declaring `LOOP_DONE:` run the
  full `bash check.sh` (build gate included) and `cargo test --workspace`.
- **Tests:** delete tests that only cover removed code; never delete or weaken unrelated tests.
  New logic is not expected — this is a removal goal.
- **Docs:** any remaining doc that links to a deleted page must be fixed, not left dangling.
- **Git:** one commit per milestone, Conventional Commits style, e.g.
  `refactor(remote): delete packages/remote-web`. Never commit with the build knowingly red
  (milestones 4–9 may be transiently red; restore green at 13).
- **Scope discipline:** do not "improve" adjacent code. Delete only what `remote` requires.
- **Artifacts:** keep `PROGRESS.md` (state/decisions/next steps) and `IMPROVEMENTS.md`
  (concrete backlog) updated each iteration.

## Assumptions

1. `crates/server/src/routes/remote/*` is a cloud proxy, so local kanban/issues/org UI is in scope
   and will be removed. If the operator disagrees, they will stop the loop before milestone 6.
2. `relay-*` crates are a separate product feature and stay.
3. `api-types` stays as a crate; only provably-orphaned modules are pruned.
4. The authoritative build gates are the per-package frontend type checks plus
   `cargo check --workspace --offline` (network `cargo check` fails for environmental reasons).
5. Deleting a UI surface is acceptable; leaving dead code or commented-out blocks is not.
6. Transient red builds between milestones are acceptable as long as milestone 13 restores green.

## Goal check

`bash check.sh` — 22 structural checks + build gate. Exit 0 ⇒ goal met. Prints `SCORE: <n>/22`.
Set `SKIP_BUILD=1` for a fast structural-only run during rapid iteration.

```bash
bash check.sh              # full check (used by /loop --check)
SKIP_BUILD=1 bash check.sh # structural only
```

**Environment note:** the build gate runs `cargo check --workspace --offline` because this
machine has no git credentials to fetch the `ts-rs` git dependency; the crate is already cached.
Do not switch this to a networked `cargo check` — it will fail for reasons unrelated to the goal.
