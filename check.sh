#!/usr/bin/env bash
# check.sh — objective goal check for "completely drop the remote feature".
#
#   bash check.sh              # 22 structural checks + build gate (used by /loop --check)
#   SKIP_BUILD=1 bash check.sh # fast structural-only run
#
# Exit 0  => goal complete (all structural checks pass AND build gate passes).
# Prints  SCORE: <n>/22  so the loop can track improvement / regressions.

set -uo pipefail
cd "$(dirname "$0")"

SKIP_BUILD="${SKIP_BUILD:-0}"
EXCLUDES=(--exclude-dir=node_modules --exclude-dir=target --exclude-dir=dist
          --exclude-dir=.git --exclude-dir=.sqlx --exclude-dir=coverage
          --exclude-dir=.vite --exclude-dir=.turbo --exclude-dir=build)

pass=0
total=0
fails=()

# ok <name> <condition-cmd...>
ok() {
  local name="$1"; shift
  total=$((total + 1))
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf '  ok   %s\n' "$name"
  else
    printf '  MISS %s\n' "$name"
    fails+=("$name")
  fi
}

# gone <path>
gone() { [ ! -e "$1" ]; }

# no_hits <regex> [paths...] — true when NO file under paths matches the regex
no_hits() {
  local pat="$1"; shift
  local dirs=()
  local d
  for d in "$@"; do [ -e "$d" ] && dirs+=("$d"); done
  [ ${#dirs[@]} -eq 0 ] && return 0
  ! grep -rIlE "${EXCLUDES[@]}" -- "$pat" "${dirs[@]}" 2>/dev/null | grep -q .
}

# no_file_named <glob-pattern> [paths...]
no_file_named() {
  local pat="$1"; shift
  local d
  for d in "$@"; do
    [ -e "$d" ] || continue
    if find "$d" -path '*/node_modules/*' -prune -o -path '*/target/*' -prune -o \
         -type f -name "$pat" -print 2>/dev/null | grep -q .; then
      return 1
    fi
  done
  return 0
}

echo "== structural checks =="

ok "S01 crates/remote removed"                gone crates/remote
ok "S02 packages/remote-web removed"          gone packages/remote-web
ok "S03 shared/remote-types.ts removed"       gone shared/remote-types.ts
ok "S04 server routes/remote removed"         gone crates/server/src/routes/remote
ok "S05 no cloud sync in local container"    no_hits 'remote_sync|remote_client' crates/local-deployment/src/container.rs
ok "S06 no remote sync in workspace routes"  no_hits 'remote_sync|remote_client|RemoteClientError' crates/server/src/routes/workspaces
ok "S07 root Cargo.toml drops crates/remote"  no_hits '"crates/remote"' Cargo.toml
ok "S08 root package.json drops remote scripts" no_hits 'remote:dev|remote:generate-types|remote-web|remote:prepare-db' package.json
ok "S09 remote CI workflows removed"          no_file_named 'remote-*.yml' .github/workflows
ok "S10 remote-web migration script removed"  gone scripts/migrate-remote-web-structure.mjs
ok "S11 docs/cloud removed"                   gone docs/cloud
ok "S12 docs/remote-access.mdx removed"       gone docs/remote-access.mdx
ok "S13 VK_SHARED_API_BASE gone"              no_hits 'VK_SHARED_API_BASE' crates packages scripts npx-cli shared
ok "S14 shared_api_base gone (rust)"          no_hits 'shared_api_base' crates packages npx-cli
ok "S15 remoteApi.ts gone"                    no_file_named 'remoteApi.ts' packages
ok "S16 web-core providers/remote gone"       gone packages/web-core/src/shared/providers/remote
ok "S17 web-core electric dirs gone"          bash -c '[ ! -e packages/web-core/src/shared/lib/electric ] && [ ! -e packages/web-core/src/shared/integrations/electric ]'
ok "S18 web-core integrations/remote gone"    gone packages/web-core/src/integrations/remote
ok "S19 no shared/remote-types imports"       no_hits 'shared/remote-types|remote-types' packages
ok "S20 electric deps removed"                no_hits 'electric-db-collection|"@tanstack/react-db"' packages
ok "S21 no remote client in config route"     no_hits 'RemoteClientError|remote_client' crates/server/src/routes/config.rs
ok "S22 local-web remote wiring gone"         no_hits 'providers/remote|lib/electric|integrations/electric|remoteApi|shared_api_base' packages/local-web/src

echo
echo "structural: $pass/$total"

build_ok=0
build_note="skipped (SKIP_BUILD=1)"
if [ "$SKIP_BUILD" != "1" ]; then
  echo "== build gate =="
  build_ok=1
  # Frontend type checks, run per package so they stay independent of the root
  # check script (which still lists remote-web:check until milestone 10).
  for task in local-web:legacy-path-guard local-web:check web-core:check ui:check; do
    if pnpm run "$task" >/tmp/vk-check.log 2>&1; then
      echo "  ok   pnpm run $task"
    else
      echo "  FAIL pnpm run $task"
      tail -n 20 /tmp/vk-check.log | sed 's/^/    /'
      build_ok=0
    fi
  done
  # --offline: this environment cannot fetch the ts-rs git dependency
  # (no git credentials); the dependency is already cached locally.
  if cargo check --workspace --offline >/tmp/vk-cargo.log 2>&1; then
    echo "  ok   cargo check --workspace --offline"
  else
    echo "  FAIL cargo check --workspace --offline"
    tail -n 20 /tmp/vk-cargo.log | sed 's/^/    /'
    build_ok=0
  fi
  [ "$build_ok" -eq 1 ] && build_note="ok" || build_note="failed"
fi

echo
echo "SCORE: $pass/$total"

if [ "$pass" -eq "$total" ] && { [ "$build_ok" -eq 1 ] || [ "$SKIP_BUILD" = "1" ]; }; then
  if [ "$SKIP_BUILD" = "1" ]; then
    echo "structural goal met; build gate skipped — rerun without SKIP_BUILD=1 to confirm"
  fi
  exit 0
fi

if [ "$build_ok" -ne 1 ] && [ "$SKIP_BUILD" != "1" ]; then
  echo "build: $build_note"
fi
[ ${#fails[@]} -gt 0 ] && { echo "remaining: ${fails[*]}"; }
exit 1
