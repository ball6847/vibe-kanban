#!/usr/bin/env bash
# Goal check: cloud-style local projects rail (see GOAL.md).
# Usage:    ./check.sh              exit 0 = all criteria met; prints "SCORE: <n>"
#           CHECK_FAST=1 ./check.sh skip build + lint + i18n-regression (static/type only)
# Env:      BACKEND_PORT / FRONTEND_PORT override live-check ports.
# Exit 0 only when SCORE == MAX.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
ROOT=$PWD
START_TS=$(date +%s)
FAST=0
[ -n "${CHECK_FAST:-}" ] && FAST=1
LOGDIR=/tmp/vibe-rail-check
mkdir -p "$LOGDIR"

SCORE=0
MAX=0
declare -a FAILED=()
GROUP() { printf '\n== %s ==\n' "$1"; }
OK()   { printf '  [ok]   %-58s +%s\n' "$1" "$2"; SCORE=$((SCORE + $2)); MAX=$((MAX + $2)); }
NO()   { printf '  [MISS] %-58s  (0/%s)\n' "$1" "$2"; FAILED+=("$1"); MAX=$((MAX + $2)); }
SKIP() { printf '  [skip] %-58s (fast mode)\n' "$1"; }

have()     { grep -qE "$2" "$1" 2>/dev/null; }
present()  { [ -e "$1" ] && OK "$2" "$3" || NO "$2" "$3"; }
absent()   { [ -e "$1" ] && NO "$2" "$3" || OK "$2" "$3"; }
# run <label> <points> <command...>
run() {
  local label=$1 pts=$2; shift 2
  local log="$LOGDIR/$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-').log"
  if "$@" >"$log" 2>&1; then OK "$label" "$pts"; else NO "$label (see $log)" "$pts"; fi
}

WEB_CORE_NAV=packages/web-core/src/shared/lib/routes/appNavigation.ts
LOCAL_NAV=packages/local-web/src/app/navigation/AppNavigation.ts
APPBAR=packages/ui/src/components/AppBar.tsx
SHELL_LAYOUT=packages/web-core/src/shared/components/ui-new/containers/SharedAppLayout.tsx
RAIL_MODEL=packages/web-core/src/pages/kanban/localProjectsRailModel.ts
RAIL_TEST=packages/web-core/src/pages/kanban/localProjectsRailModel.test.ts

GROUP "1. navigation model (web-core)"
have "$WEB_CORE_NAV" "kind: 'projects'"            && OK "AppDestination has { kind: 'projects' }" 4 || NO "AppDestination has { kind: 'projects' }" 4
have "$WEB_CORE_NAV" 'goToProjects'                && OK "AppNavigation interface declares goToProjects" 4 || NO "AppNavigation interface declares goToProjects" 4
# 'projects' must NOT join ProjectDestinationKind (it drives kanban issue/workspace resolution).
PDK=$(sed -n '/^type ProjectDestinationKind =/,/;/p' "$WEB_CORE_NAV" 2>/dev/null)
case "$PDK" in
  *"'projects'"*) NO "ProjectDestinationKind left unpolluted by 'projects'" 3 ;;
  "")             NO "ProjectDestinationKind found and unpolluted" 3 ;;
  *)              OK "ProjectDestinationKind left unpolluted by 'projects'" 3 ;;
esac

GROUP "2. local-web navigation"
have "$LOCAL_NAV" 'goToProjects'                   && OK "goToProjects implemented" 4 || NO "goToProjects implemented" 4
have "$LOCAL_NAV" "case 'projects':"               && OK "forward map: case 'projects'" 4 || NO "forward map: case 'projects'" 4
have "$LOCAL_NAV" "case '/_app/projects':"         && OK "reverse map: case '/_app/projects'" 4 || NO "reverse map: case '/_app/projects'" 4

GROUP "3. pure rail model"
present "$RAIL_MODEL" "localProjectsRailModel.ts exists" 3
have "$RAIL_MODEL" 'toAppBarProjects'              && OK "exports toAppBarProjects" 3 || NO "exports toAppBarProjects" 3
have "$RAIL_MODEL" 'resolveActiveProjectId'        && OK "exports resolveActiveProjectId" 3 || NO "exports resolveActiveProjectId" 3
present "$RAIL_TEST"  "localProjectsRailModel.test.ts exists" 2

GROUP "4. AppBar local mode"
APPBAR_HITS=$(grep -o 'projectsEnabled' "$APPBAR" 2>/dev/null | wc -l | tr -d ' ')
if [ "${APPBAR_HITS:-0}" -ge 3 ]; then OK "projectsEnabled prop wired ($APPBAR_HITS refs)" 4
else NO "projectsEnabled prop wired (got ${APPBAR_HITS:-0} refs, need >=3)" 4; fi
have "$APPBAR" '!isSignedIn && !projectsEnabled'   && OK "cloud CTA gated by !projectsEnabled" 4 || NO "cloud CTA gated by !projectsEnabled" 4
have "$APPBAR" '\(isSignedIn \|\| projectsEnabled\)' && OK "create button gated by projectsEnabled" 4 || NO "create button gated by projectsEnabled" 4

GROUP "5. shell wiring"
have "$SHELL_LAYOUT" 'localProjectsApi'            && OK "SharedAppLayout fetches local projects" 4 || NO "SharedAppLayout fetches local projects" 4
have "$SHELL_LAYOUT" 'projectsEnabled'             && OK "passes projectsEnabled to AppBar" 3 || NO "passes projectsEnabled to AppBar" 3
have "$SHELL_LAYOUT" 'projects={\[\]}'             && NO "placeholder projects={[]} removed" 3 || OK "placeholder projects={[]} removed" 3
have "$SHELL_LAYOUT" 'activeProjectId = null'      && NO "activeProjectId no longer hardcoded null" 3 || OK "activeProjectId no longer hardcoded null" 3
have "$SHELL_LAYOUT" 'onProjectClick'              && OK "passes onProjectClick" 3 || NO "passes onProjectClick" 3
have "$SHELL_LAYOUT" 'onCreateProject'             && OK "passes onCreateProject" 3 || NO "passes onCreateProject" 3
have "$SHELL_LAYOUT" 'Row-1 filler'                && OK "grid row-1 filler marker kept" 2 || NO "grid row-1 filler marker kept" 2
have "$SHELL_LAYOUT" 'NavbarContainer'             && NO "deleted NavbarContainer not resurrected" 2 || OK "deleted NavbarContainer not resurrected" 2

GROUP "6. i18n key in all 7 locales"
python3 - <<'PY' && OK "appBar.projects.create in all locales" 4 || NO "appBar.projects.create in all locales" 4
import json, pathlib, sys
base = pathlib.Path('packages/web-core/src/i18n/locales')
missing = []
for loc in sorted(p.name for p in base.iterdir() if p.is_dir()):
    f = base / loc / 'common.json'
    try:
        d = json.load(open(f))
    except Exception:
        missing.append(f'{loc}:unreadable'); continue
    if not isinstance(d.get('appBar', {}).get('projects', {}), dict) or 'create' not in d.get('appBar', {}).get('projects', {}):
        missing.append(loc)
if missing:
    print('missing:', ', '.join(missing), file=sys.stderr); sys.exit(1)
PY

GROUP "7. no cloud regression"
absent shared/remote-types.ts            "shared/remote-types.ts still deleted" 2
absent crates/remote                     "crates/remote still deleted" 2
absent packages/remote-web               "packages/remote-web still deleted" 2
if grep -qE '@tanstack/(electric-db-collection|react-db)' packages/local-web/package.json packages/web-core/package.json 2>/dev/null; then
  NO "Electric deps stay removed" 2
else OK "Electric deps stay removed" 2; fi
if grep -rqE "from 'shared/remote-types'|from \"shared/remote-types\"" packages/*/src --include='*.ts' --include='*.tsx' 2>/dev/null; then
  NO "no source imports shared/remote-types" 2
else OK "no source imports shared/remote-types" 2; fi

GROUP "8. type checks"
run "pnpm run web-core:check"  5 pnpm run web-core:check
run "pnpm run local-web:check" 5 pnpm run local-web:check
run "pnpm run ui:check"        5 pnpm run ui:check

GROUP "9. format (goal-owned files only)"
# Repo-wide format drift on main is pre-existing (26 unformatted web-core files, unchanged by
# this branch). Only the files this goal touches must be formatted, to keep the diff surgical.
if [ "$FAST" = 1 ]; then
  SKIP "prettier --check (goal files)"
else
  F_CORE=""; F_WEB=""; F_UI=""
  for f in shared/lib/routes/appNavigation.ts pages/kanban/localProjectsRailModel.ts \
           pages/kanban/localProjectsRailModel.test.ts i18n/locales/en/common.json; do
    [ -f "packages/web-core/src/$f" ] && F_CORE="$F_CORE src/$f"
  done
  [ -f "$LOCAL_NAV" ] && F_WEB="src/app/navigation/AppNavigation.ts"
  [ -f "$APPBAR" ] && F_UI="src/components/AppBar.tsx"
  if [ -z "$F_CORE" ]; then NO "prettier: goal files (web-core) — none created yet" 3
  else run "prettier: goal files (web-core)" 3 pnpm --filter @vibe/web-core exec prettier --check $F_CORE; fi
  if [ -z "$F_WEB" ]; then NO "prettier: goal files (local-web) — none created yet" 2
  else run "prettier: goal files (local-web)" 2 pnpm --filter @vibe/local-web exec prettier --check $F_WEB; fi
  if [ -z "$F_UI" ]; then NO "prettier: goal files (ui) — none created yet" 1
  else run "prettier: goal files (ui)" 1 pnpm --filter @vibe/ui exec prettier --config ../../packages/local-web/.prettierrc.json --check $F_UI; fi
fi

GROUP "10. build + i18n regression"
if [ "$FAST" = 1 ]; then
  SKIP "check-i18n regression"; SKIP "unused i18n keys vs baseline"; SKIP "legacy path guard"; SKIP "local-web build"
else
  run "check-i18n regression" 4 env GITHUB_BASE_REF="${GITHUB_BASE_REF:-main}" ./scripts/check-i18n.sh
  # The repo already carries 104 unused keys on main (remote-era leftovers). This is a
  # REGRESSION gate: do not increase the count; prune keys you orphan.
  UNUSED_BASELINE=104
  UNUSED_N=$(node scripts/check-unused-i18n-keys.mjs 2>/dev/null | grep -oE 'Found [0-9]+ unused' | grep -oE '[0-9]+' | head -1)
  if [ -z "$UNUSED_N" ]; then OK "unused i18n keys at/below baseline (none)" 4
  elif [ "$UNUSED_N" -le "$UNUSED_BASELINE" ]; then OK "unused i18n keys <= baseline ($UNUSED_N/$UNUSED_BASELINE)" 4
  else NO "unused i18n keys <= baseline ($UNUSED_N > $UNUSED_BASELINE)" 4; fi
  run "legacy path guard" 2 ./scripts/check-legacy-frontend-paths.sh
  # CI builds local-web with an 8 GB heap (.github/workflows/test.yml); the default heap OOMs here.
  run "local-web build (CI heap)" 5 env NODE_OPTIONS=--max-old-space-size=8192 pnpm --filter @vibe/local-web run build
fi

GROUP "11. unit tests (pure rail model)"
if grep -qE '"test": *"vitest run"' packages/web-core/package.json 2>/dev/null; then
  run "pnpm --filter @vibe/web-core test" 6 pnpm --filter @vibe/web-core test
else
  NO "web-core has a 'vitest run' test script" 6
fi

GROUP "12. live check (self-skips when nothing is running)"
port_from_file() { [ -f /tmp/vibe-kanban/vibe-kanban.port ] && python3 -c "import json;print(json.load(open('/tmp/vibe-kanban/vibe-kanban.port')).get('main_port') or '')" 2>/dev/null; }
health_on()  { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$1/api/health" 2>/dev/null)" = "200" ]; }
API_PORT=""
for cand in "${BACKEND_PORT:-}" "$(port_from_file)" 3004; do
  [ -n "$cand" ] && health_on "$cand" && API_PORT=$cand && break
done
if [ -z "$API_PORT" ]; then
  echo "  [skip] no backend reachable — live checks cost no points"
else
  OK "backend health on :$API_PORT" 2
  PROJECTS_JSON=$(curl -s --max-time 8 "http://localhost:$API_PORT/api/projects" 2>/dev/null)
  if printf '%s' "$PROJECTS_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d.get('data'), list) else 1)" 2>/dev/null; then
    OK "GET /api/projects returns a list" 4
    N=$(printf '%s' "$PROJECTS_JSON" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('data') or []))" 2>/dev/null || echo 0)
    echo "  [info] local projects visible to the rail: ${N:-0} (create one via the UI to eyeball the rail)"
  else
    NO "GET /api/projects returns a list" 4
  fi
  UI_PORT="${FRONTEND_PORT:-3003}"
  FE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://localhost:$UI_PORT/" 2>/dev/null)
  if [ "$FE" = "200" ]; then OK "frontend serves on :$UI_PORT" 2; else NO "frontend serves on :$UI_PORT (got ${FE:-none})" 2; fi
fi

ELAPSED=$(( $(date +%s) - START_TS ))
printf '\n========================================\n'
printf 'TIME: %ss\n' "$ELAPSED"
printf 'SCORE: %s\n' "$SCORE"
printf 'MAX: %s\n' "$MAX"
TIMINGS=notes/check-timings.tsv
mkdir -p notes
printf '%s\t%s\t%s\n' "$(date -Is)" "$ELAPSED" "$SCORE" >> "$TIMINGS"
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf 'Failing checks (%s):\n' "${#FAILED[@]}"
  for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done
fi
[ "$SCORE" -ge "$MAX" ] && exit 0 || exit 1
