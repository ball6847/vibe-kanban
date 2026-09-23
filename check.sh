#!/usr/bin/env bash
# Goal check: link tasks to workspaces (see GOAL.md).
# Usage:    ./check.sh              exit 0 = all criteria met; prints "SCORE: <n>"
#           CHECK_FAST=1 ./check.sh skip build/lint/heavy steps (never the browser e2e)
# Env:      BACKEND_PORT / FRONTEND_PORT override detection.
# Exit 0 only when SCORE == MAX.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
ROOT=$PWD
START_TS=$(date +%s)
FAST=0
[ -n "${CHECK_FAST:-}" ] && FAST=1
LOGDIR=/tmp/vibe-link-check
mkdir -p "$LOGDIR"

SCORE=0
MAX=0
declare -a FAILED=()
GROUP() { printf '\n== %s ==\n' "$1"; }
OK()   { printf '  [ok]   %-58s +%s\n' "$1" "$2"; SCORE=$((SCORE + $2)); MAX=$((MAX + $2)); }
NO()   { printf '  [MISS] %-58s  (0/%s)\n' "$1" "$2"; FAILED+=("$1"); MAX=$((MAX + $2)); }
SKIP() { printf '  [skip] %-58s (fast mode)\n' "$1"; }
have()    { grep -qE "$2" "$1" 2>/dev/null; }
present() { [ -e "$1" ] && OK "$2" "$3" || NO "$2" "$3"; }
absent()  { [ -e "$1" ] && NO "$2" "$3" || OK "$2" "$3"; }
run() {
  local label=$1 pts=$2; shift 2
  local log="$LOGDIR/$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-').log"
  if "$@" >"$log" 2>&1; then OK "$label" "$pts"; else NO "$label (see $log)" "$pts"; fi
}

DB_WORKSPACE=crates/db/src/models/workspace.rs
SRV_CREATE=crates/server/src/routes/workspaces/create.rs
TYPES=shared/types.ts
BOARD=packages/web-core/src/pages/kanban/LocalKanbanBoard.tsx
LINK_MODEL=packages/web-core/src/pages/kanban/taskWorkspaceLinkModel.ts
EVIDENCE=.context/evidence/task-workspace-link

GROUP "1. backend write path"
have "$DB_WORKSPACE" 'task_id'                        && OK "workspace.rs mentions task_id" 3 || NO "workspace.rs mentions task_id" 3
# The INSERT's task_id column already exists; the real signal is that the create fn no longer
# binds the literal None there.
CREATE_BODY=$(awk '/pub async fn create\(/,/^    }/' "$DB_WORKSPACE" 2>/dev/null)
if printf '%s' "$CREATE_BODY" | grep -q 'Option::<Uuid>::None'; then
  NO "Workspace::create binds a real task_id (still literal None)" 5
elif printf '%s' "$CREATE_BODY" | grep -q 'task_id'; then
  OK "Workspace::create binds a real task_id" 5
else
  NO "Workspace::create binds a real task_id (create fn not found)" 5
fi
have "$SRV_CREATE" 'task_id'                          && OK "create route threads task_id" 5 || NO "create route threads task_id" 5
if grep -qE 'pub task_id: Option<Uuid>' "$SRV_CREATE" crates/db/src/models/requests.rs crates/server/src/routes/workspaces/mod.rs 2>/dev/null; then
  OK "request struct declares task_id: Option<Uuid>" 4
else NO "request struct declares task_id: Option<Uuid>" 4; fi

GROUP "2. API + generated types"
python3 - <<'PYT' && OK "CreateAndStartWorkspaceRequest carries task_id" 5 || NO "CreateAndStartWorkspaceRequest carries task_id" 5
import re, sys
src = open('shared/types.ts').read()
m = re.search(r'export type CreateAndStartWorkspaceRequest = \{(.*?)\};', src, re.S)
sys.exit(0 if m and 'task_id' in m.group(1) else 1)
PYT
have packages/web-core/src/shared/lib/api.ts 'task_id' && OK "workspaces API surfaces task_id queries" 3 \
  || NO "workspaces API surfaces task_id queries" 3

GROUP "3. frontend actions"
have "$BOARD" 'task-create-workspace-'                 && OK "board has a create-workspace action" 5 || NO "board has a create-workspace action" 5
have "$BOARD" 'task-open-workspace-'                   && OK "board renders linked workspaces" 5 || NO "board renders linked workspaces" 5
have "$BOARD" 'task-card-'                             && OK "task cards carry a test id" 3 || NO "task cards carry a test id" 3
have "$BOARD" 'goToWorkspace'                          && OK "clicking a link opens the workspace" 4 || NO "clicking a link opens the workspace" 4
grep -rq "goToWorkspacesCreate" "$BOARD" 2>/dev/null \
  && OK "create action opens the local create flow" 3 || NO "create action opens the local create flow" 3
grep -rn "task_id" packages/web-core/src/features/create-mode packages/web-core/src/shared/lib/workspaceCreateState.ts 2>/dev/null | grep -q task_id \
  && OK "create flow carries task_id into the request" 4 || NO "create flow carries task_id into the request" 4
present "$LINK_MODEL" "taskWorkspaceLinkModel.ts exists" 3

GROUP "4. i18n keys in all 7 locales"
python3 - <<'PY' && OK "kanban.task.createWorkspace + openWorkspace in all locales" 4 || NO "kanban.task.* keys in all locales" 4
import json, pathlib, sys
base = pathlib.Path('packages/web-core/src/i18n/locales')
need = ('createWorkspace', 'openWorkspace')
missing = []
for loc in sorted(p.name for p in base.iterdir() if p.is_dir()):
    try:
        d = json.load(open(base/loc/'common.json'))
    except Exception:
        missing.append(f'{loc}:unreadable'); continue
    task = (d.get('kanban') or {}).get('task') or {}
    for k in need:
        if k not in task:
            missing.append(f'{loc}:{k}')
if missing:
    print('missing:', ', '.join(missing), file=sys.stderr); sys.exit(1)
PY

GROUP "5. no cloud regression / no new deps"
absent shared/remote-types.ts "shared/remote-types.ts still deleted" 2
absent crates/remote          "crates/remote still deleted" 2
absent packages/remote-web    "packages/remote-web still deleted" 2
grep -qE '@tanstack/(electric-db-collection|react-db)' packages/web-core/package.json packages/local-web/package.json 2>/dev/null \
  && NO "Electric deps stay removed" 2 || OK "Electric deps stay removed" 2

GROUP "6. type checks"
run "pnpm run web-core:check"  4 pnpm run web-core:check
run "pnpm run local-web:check" 4 pnpm run local-web:check
run "pnpm run ui:check"        3 pnpm run ui:check

GROUP "7. browser e2e via agent-browser"
AB=(agent-browser --session vibe-goal-check)
ab()      { timeout 90 "${AB[@]}" "$@" 2>&1 | grep -v 'invalid config file'; }
ab_open() { ab open "$1" --args "--no-sandbox" | tail -1; }
ab_eval() { ab eval "$1" | tail -1 | sed 's/^"//; s/"$//'; }
ab_url()  { ab get url | tail -1; }
port_from_file() { [ -f /tmp/vibe-kanban/vibe-kanban.port ] && python3 -c "import json;print(json.load(open('/tmp/vibe-kanban/vibe-kanban.port')).get('main_port') or '')" 2>/dev/null; }
UI="${FRONTEND_PORT:-3003}"
PORT=""; FE=""
for _ in $(seq 1 18); do
  PORT=""
  for cand in "${BACKEND_PORT:-}" "$(port_from_file)" 3004; do
    [ -n "$cand" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$cand/api/health")" = "200" ] && PORT=$cand && break
  done
  FE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://localhost:$UI/")
  [ -n "$PORT" ] && [ "$FE" = "200" ] && break
  sleep 5
done
if [ -z "$PORT" ] || [ "$FE" != "200" ]; then
  NO "dev stack reachable (start 'pnpm run dev', api=$PORT fe=$FE)" 30
else
  API="http://localhost:$PORT"
  STAMP=$(date +%s)
  REPO=/tmp/vibe-link-e2e-repo
  if [ ! -d "$REPO/.git" ]; then
    mkdir -p "$REPO"; git -C "$REPO" init -q -b main
    printf '# link e2e\n' >"$REPO/README.md"
    git -C "$REPO" add -A >/dev/null 2>&1
    git -C "$REPO" -c user.email=check@local -c user.name=check commit -qm init >/dev/null 2>&1
  fi
  RID=$(curl -s --max-time 20 "$API/api/repos" | python3 -c "
import json,sys
for r in json.load(sys.stdin).get('data') or []:
    if r.get('display_name')=='vibe-link-e2e': print(r['id']); break" 2>/dev/null)
  if [ -z "$RID" ]; then
    RID=$(curl -s --max-time 20 -X POST "$API/api/repos" -H 'Content-Type: application/json' \
      -d "{\"path\":\"$REPO\",\"display_name\":\"vibe-link-e2e\"}" | python3 -c "
import json,sys
print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
  fi
  PID=$(curl -s --max-time 20 -X POST "$API/api/projects" -H 'Content-Type: application/json' \
    -d "{\"name\":\"Link E2E $STAMP\"}" | python3 -c "import json,sys;print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
  TID=$(curl -s --max-time 20 -X POST "$API/api/tasks" -H 'Content-Type: application/json' \
    -d "{\"project_id\":\"$PID\",\"title\":\"Link e2e task $STAMP\",\"description\":\"seeded by check.sh\"}" \
    | python3 -c "import json,sys;print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
  if [ -z "$RID" ] || [ -z "$PID" ] || [ -z "$TID" ]; then
    NO "e2e seed (repo/project/task via API)" 30
  else
    OK "e2e seed (repo, project, task)" 2
    mkdir -p "$EVIDENCE"
    ab_open "http://localhost:$UI/projects/$PID" >/dev/null
    ab wait "[data-testid=task-card-$TID]" >/dev/null 2>&1
    if [ "$(ab_eval "document.querySelectorAll('[data-testid=task-create-workspace-$TID]').length")" = "1" ]; then
      OK "task card offers 'Create workspace'" 3
      ab click "[data-testid=task-create-workspace-$TID]" >/dev/null 2>&1
      sleep 1
      case "$(ab_url)" in */workspaces/create*) OK "create action opens the create flow" 4 ;;
        *) NO "create action opens the create flow (url: $(ab_url))" 4 ;; esac
      PREFILL=$(ab_eval "[...document.querySelectorAll('[aria-label=\"Markdown editor\"]')].map((e) => e.textContent || '').join(' | ')")
      case "$PREFILL" in *"Link e2e task $STAMP"*) OK "create flow is prefilled from the task" 4 ;;
        *) NO "create flow is prefilled from the task (got '${PREFILL:0:40}')" 4 ;; esac
      SUBMIT=$(ab_eval "(() => { const b = [...document.querySelectorAll('button')].find((x) => /^create$/i.test((x.textContent || '').trim())); if (!b) return 'no-button'; b.click(); return 'clicked'; })()")
      [ "$SUBMIT" = "clicked" ] || echo "  [info] submit button: $SUBMIT"
      WSID=""
      UUID='[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}'
      for _ in $(seq 1 30); do
        U=$(ab_url)
        WSID=$(printf '%s' "$U" | sed -n "s#.*/workspaces/\($UUID\).*#\1#p")
        [ -n "$WSID" ] && break
        sleep 2
      done
      if [ -n "$WSID" ]; then
        OK "submitting creates the workspace and opens it" 6
        # The authoritative check: the workspace the UI opened must carry this task id.
        WS_TASK=""
        for _ in $(seq 1 10); do
          WS_TASK=$(curl -s --max-time 8 "$API/api/workspaces/$WSID" | python3 -c "
import json,sys
print((json.load(sys.stdin).get('data') or {}).get('task_id') or '')" 2>/dev/null)
          [ -n "$WS_TASK" ] && break
          sleep 2
        done
        LIST=$(curl -s --max-time 10 "$API/api/workspaces?task_id=$TID" | python3 -c "
import json,sys
d=json.load(sys.stdin).get('data') or []
print(','.join(w['id'] for w in d))" 2>/dev/null)
        if [ "$WS_TASK" = "$TID" ] && [ "$LIST" = "$WSID" ]; then OK "workspace is linked to the task (API)" 6
        else NO "workspace is linked to the task (ws.task_id='${WS_TASK:-none}' list='${LIST:-none}' task='$TID')" 6; fi
        ab_open "http://localhost:$UI/projects/$PID" >/dev/null
        ab wait "[data-testid=task-card-$TID]" >/dev/null 2>&1
        if [ "$(ab_eval "document.querySelectorAll('[data-testid=task-open-workspace-$WSID]').length")" = "1" ]; then
          OK "task card shows the linked workspace" 4
          ab click "[data-testid=task-open-workspace-$WSID]" >/dev/null 2>&1
          sleep 2
          case "$(ab_url)" in *"/workspaces/$WSID"*) OK "clicking the link opens the workspace" 3 ;;
            *) NO "clicking the link opens the workspace (url: $(ab_url))" 3 ;; esac
        else NO "task card shows the linked workspace" 4; fi
        # agent-browser resolves relative paths against the daemon's cwd, so pass an absolute one.
        ab screenshot "$ROOT/$EVIDENCE/e2e-create-from-task.png" >/dev/null 2>&1
        [ -f "$EVIDENCE/e2e-create-from-task.png" ] && OK "e2e screenshot written" 2 || NO "e2e screenshot written" 2
        curl -s -X DELETE "$API/api/workspaces/$WSID" >/dev/null 2>&1
      else NO "submitting creates the workspace and opens it (url: $(ab_url))" 6; fi
    else NO "task card offers 'Create workspace'" 3; fi
    curl -s -X DELETE "$API/api/projects/$PID" >/dev/null 2>&1
    [ -n "$RID" ] && curl -s -X DELETE "$API/api/repos/$RID" >/dev/null 2>&1
    # close our session so the next run launches a browser with the right args
    ab close >/dev/null 2>&1
  fi
fi

GROUP "8. committed e2e evidence"
present "$EVIDENCE/NOTES.md" "evidence NOTES.md committed" 2
if ls "$EVIDENCE"/*.png >/dev/null 2>&1; then OK "evidence screenshots present" 2; else NO "evidence screenshots present" 2; fi


GROUP "9. lint + format (goal files)"
if [ "$FAST" = 1 ]; then SKIP "local-web lint"; SKIP "ui lint"; SKIP "prettier (goal files)"
else
  run "pnpm run local-web:lint" 3 pnpm run local-web:lint
  run "pnpm run ui:lint"        3 pnpm run ui:lint
  FILES=""
  for f in src/pages/kanban/LocalKanbanBoard.tsx src/pages/kanban/taskWorkspaceLinkModel.ts; do
    [ -f "packages/web-core/$f" ] && FILES="$FILES $f"
  done
  if [ -z "$FILES" ]; then NO "prettier: goal files (web-core)" 3
  else run "prettier: goal files (web-core)" 3 pnpm --filter @vibe/web-core exec prettier --check $FILES; fi
fi

GROUP "10. sqlx caches, rust build, i18n + build gates"
run "cargo check (excl. tauri)" 8 cargo check --workspace --exclude vibe-kanban-tauri
run "prepare-db:check (sqlx caches)" 6 pnpm run prepare-db:check
if [ "$FAST" = 1 ]; then SKIP "check-i18n"; SKIP "unused i18n keys"; SKIP "legacy guard"; SKIP "local-web build"
else
  run "check-i18n regression" 3 env GITHUB_BASE_REF="${GITHUB_BASE_REF:-main}" ./scripts/check-i18n.sh
  UNUSED_N=$(node scripts/check-unused-i18n-keys.mjs 2>/dev/null | grep -oE 'Found [0-9]+ unused' | grep -oE '[0-9]+' | head -1)
  if [ -z "${UNUSED_N:-}" ] || [ "$UNUSED_N" -le 104 ]; then OK "unused i18n keys <= 104 baseline (${UNUSED_N:-0})" 3
  else NO "unused i18n keys <= 104 (got $UNUSED_N)" 3; fi
  run "legacy path guard" 2 ./scripts/check-legacy-frontend-paths.sh
  run "local-web build (CI heap)" 4 env NODE_OPTIONS=--max-old-space-size=8192 pnpm --filter @vibe/local-web run build
fi

GROUP "11. unit tests (pure link logic)"
if grep -qE '"test": *"vitest run"' packages/web-core/package.json 2>/dev/null; then
  run "pnpm --filter @vibe/web-core test" 6 pnpm --filter @vibe/web-core test
else NO "web-core has a 'vitest run' test script" 6; fi

ELAPSED=$(( $(date +%s) - START_TS ))
printf '\n========================================\n'
printf 'TIME: %ss\n' "$ELAPSED"
printf 'SCORE: %s\n' "$SCORE"
printf 'MAX: %s\n' "$MAX"
TIMINGS=notes/check-timings.tsv
mkdir -p notes
printf '%s\t%s\t%s\n' "$(date -Is)" "$ELAPSED" "$SCORE" >> "$TIMINGS"
printf 'NOTE: the cargo gates above rebuild into target/, which can interrupt a running
'
printf '      `pnpm run dev` (cargo watch). Restart the dev stack before the next e2e run.
'
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf 'Failing checks (%s):\n' "${#FAILED[@]}"
  for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done
fi
[ "$SCORE" -ge "$MAX" ] && exit 0 || exit 1
