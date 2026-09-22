# IMPROVEMENTS

Concrete backlog for the endless phase of the loop. Every item needs exact file paths and a
one-line acceptance criterion. Take the top open item when the goal check is green.

## Open

- [ ] `packages/web-core/src/shared/components/WYSIWYGEditor.tsx` — `fetchAttachmentSasUrl` is now a stub
      returning `''`; cloud attachment images no longer resolve. Decide whether to drop attachment support
      and make `fetchAttachmentUrl` optional in `packages/ui/src/components/{image-node,attachment-node}.tsx`.
      Done when: either the stub is gone and the option is optional, or the attachment UI is removed.
- [ ] `scripts/find-remote-only-web-core.mjs` — temporary goal aid; delete once the final
      `bash check.sh` is green. Done when: file no longer exists.
- [ ] `packages/web-core/src/shared/lib/relayBackendApi.ts` — confirm `syncRelayApiBaseWithRemote`
      is unreferenced after remote removal; delete the function if so.
      Done when: `grep -r syncRelayApiBaseWithRemote packages/` returns nothing.
- [ ] `crates/api-types/src/` — prune remote-only modules (organizations, notification, pull_request,
      project, tag, issue*) once no non-remote crate references them.
      Done when: `cargo check --workspace` is green after each deletion.
- [ ] `pnpm-lock.yaml` — refresh after dropping electric/react-db deps.
      Done when: `pnpm install --frozen-lockfile` exits 0.
- [ ] `Cargo.lock` — refresh after removing `crates/remote` and `crates/remote-info`.
      Done when: `cargo metadata --no-deps` no longer lists `remote` or `remote-info`.
- [ ] `docs/` — sweep for lingering links to deleted cloud/remote pages.
      Done when: `grep -rniE 'remote-access|cloud/(issues|projects|organizations)' docs/` returns nothing.

## Done

(none yet)
- [ ] `.github/workflows/test.yml` + `.github/workflows/pre-release.yml` still reference the deleted
      `crates/remote` (job paths, `--manifest-path crates/remote/Cargo.toml`, changed-file filters for
      `crates/remote*`). Their `remote-*.yml` siblings were deleted in batch 31; these two need their
      remote jobs/steps stripped so CI does not try to build a removed crate.
      Done when: `grep -rn "crates/remote" .github/` returns nothing.
- [ ] `Cargo.lock` still lists dependencies that only `crates/remote` used (axum extras, electric/sqlx
      bits, postal, etc.). Run `cargo update --workspace --offline` / regenerate to shrink it.
      Done when: `grep -c "crates/remote" Cargo.lock` is 0 and `cargo check --workspace --offline` passes.
- [ ] Re-check for leftover remote references in non-code assets: `.env.remote`, `Caddyfile.example`,
      `Dockerfile`, `docs/self-hosting/*`, `local-build.sh`, `npx-cli/`.
      Done when: a case-insensitive sweep for `VK_SHARED_API_BASE|shared_api_base|remote:dev|\.env\.remote`
      over the repo (excluding `node_modules`/`target`/`dist`/`crates/remote-info`) returns nothing.
- [ ] `scripts/find-remote-only-web-core.mjs` — temporary goal aid, no longer needed now that
      `SCORE 22/22`; delete it. Done when: file no longer exists.
