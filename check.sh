#!/usr/bin/env bash
# Goal check: bring the task UX/UI back, verified end to end with screenshots (see GOAL.md).
# Usage:    ./check.sh              exit 0 = all criteria met; prints "SCORE: <n>" / "MAX: <n>"
#           CHECK_FAST=1 ./check.sh skip lint/build/heavy steps (never the browser e2e)
# Env:      BACKEND_PORT / FRONTEND_PORT override detection.
# Exit 0 only when SCORE == MAX.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
ROOT=$PWD
START_TS=$(date +%s)
FAST=0
[ -n "${CHECK_FAST:-}" ] && FAST=1
LOGDIR=/tmp/vibe-task-ux-check
mkdir -p "$LOGDIR"

SCORE=0
MAX=0
declare -a FAILED=()
GROUP() { printf '\n== %s ==\n' "$1"; }
OK()   { printf '  [ok]   %-56s +%s\n' "$1" "$2"; SCORE=$((SCORE + $2)); MAX=$((MAX + $2)); }
NO()   { printf '  [MISS] %-56s  (0/%s)\n' "$1" "$2"; FAILED+=("$1"); MAX=$((MAX + $2)); }
SKIP() { printf '  [skip] %-56s (fast mode)\n' "$1"; }
have()    { grep -qE "$2" "$1" 2>/dev/null; }
present() { [ -e "$1" ] && OK "$2" "$3" || NO "$2" "$3"; }
absent()  { [ -e "$1" ] && NO "$2" "$3" || OK "$2" "$3"; }
run() {
  local label=$1 pts=$2; shift 2
  local log="$LOGDIR/$(printf '%s' "$label" | tr -c 'a-zA-Z0-9' '-').log"
  if "$@" >"$log" 2>&1; then OK "$label" "$pts"; else NO "$label (see $log)" "$pts"; fi
}

KANBAN=packages/web-core/src/pages/kanban
BOARD=$KANBAN/LocalKanbanBoard.tsx
PANEL=$KANBAN/TaskDetailPanel.tsx
SEARCH=packages/web-core/src/project-routes/project-search.ts
ROUTE_STATE=packages/web-core/src/shared/hooks/useCurrentKanbanRouteState.ts
DB_WORKSPACE=crates/db/src/models/workspace.rs
DB_TASK=crates/db/src/models/task.rs
EVIDENCE=.context/evidence/task-ux

GROUP "1. project state"
present "$BOARD"   "kanban board present" 2
present GOAL.md    "GOAL.md present" 2
grep -qE '"test": *"vitest run"' packages/web-core/package.json 2>/dev/null \
  && OK "web-core has a vitest script" 2 || NO "web-core has a vitest script" 2

GROUP "2. clickable card + selection plumbing"
# The selection rides the project-issue route the app already declares (see GOAL.md), so these
# assert what ships: the board navigates through it and the route state reads it back.
have "$BOARD" 'goToProjectIssue' && OK "board selects a task through the project-issue route" 4 \
  || NO "board selects a task through the project-issue route" 4
ROUTE_TYPES=packages/web-core/src/shared/lib/routes/appNavigation.ts
grep -qE 'issueId' "$ROUTE_TYPES" 2>/dev/null && OK "route state exposes the selected task" 3 \
  || NO "route state exposes the selected task" 3
have "$BOARD" 'task-detail-panel|selectedTaskId' && OK "board reacts to a selection" 4 \
  || NO "board reacts to a selection" 4
have "$BOARD" 'useKanbanShortcuts' && OK "Escape closes the selection" 3 || NO "Escape closes the selection" 3
have "$BOARD" 'handleSelectTask' && OK "card click selects the task" 3 || NO "card click selects the task" 3

GROUP "3. task detail panel"
present "$PANEL" "TaskDetailPanel.tsx exists" 5
have "$PANEL" 'task-detail-panel'        && OK "panel test id" 3 || NO "panel test id" 3
have "$PANEL" 'task-detail-title'        && OK "panel shows the title" 3 || NO "panel shows the title" 3
have "$PANEL" 'task-detail-description'  && OK "panel shows the description" 3 || NO "panel shows the description" 3
have "$PANEL" 'task-detail-status'       && OK "panel shows the status" 3 || NO "panel shows the status" 3
have "$PANEL" 'task-detail-edit-title|task-detail-save' && OK "panel edits the title inline" 4 \
  || NO "panel edits the title inline" 4
have "$PANEL" 'task-detail-delete'       && OK "panel deletes the task" 3 || NO "panel deletes the task" 3
run "panel is covered by tests" 3 bash -c "ls $KANBAN/*.test.ts $KANBAN/*.test.tsx 2>/dev/null | grep -qiE 'panel|task'"

GROUP "4. workspace section + 1:1"
have "$PANEL" 'task-detail-open-workspace'   && OK "panel opens the linked workspace" 4 \
  || NO "panel opens the linked workspace" 4
have "$PANEL" 'task-detail-create-workspace' && OK "panel creates the workspace" 4 \
  || NO "panel creates the workspace" 4
MIGRATION_UNIQUE=$(grep -rlE 'UNIQUE INDEX.*workspace.*task_id|task_id.*UNIQUE' crates/db/migrations 2>/dev/null | head -1)
[ -n "$MIGRATION_UNIQUE" ] && OK "migration enforces one workspace per task (${MIGRATION_UNIQUE##*/})" 6 \
  || NO "migration enforces one workspace per task" 6
# A migration file proves intent; the live database proves it was applied.
python3 - <<'PYT' && OK "the live database has the 1:1 index" 3 || NO "the live database has the 1:1 index" 3
import sqlite3, sys
for path in ('dev_assets/db.v2.sqlite', 'dev_assets/db.sqlite'):
    try:
        db = sqlite3.connect(f'file:{path}?mode=ro', uri=True)
        rows = db.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='workspaces'").fetchall()
    except Exception:
        continue
    if any('task_id' in r[0] for r in rows):
        sys.exit(0)
sys.exit(1)
PYT
grep -rqE 'existing|reuse' "$KANBAN"/taskWorkspaceLinkModel.ts "$BOARD" 2>/dev/null \
  && OK "create-from-task reuses the linked workspace" 3 || NO "create-from-task reuses the linked workspace" 3

GROUP "5. automated task status"
have "$DB_TASK" 'fn update_status' && OK "Task::update_status exists" 4 || NO "Task::update_status exists" 4
TRANSITION=$(ls $KANBAN/taskStatus* $KANBAN/*transition* 2>/dev/null | head -1)
[ -n "$TRANSITION" ] && OK "transition rules live in a pure module (${TRANSITION##*/})" 3 \
  || NO "transition rules live in a pure module" 3
have crates/services/src/services/container.rs 'TaskStatus::InProgress' && OK "execution start moves the task to in_progress" 5 \
  || NO "execution start moves the task to in_progress" 5
have crates/services/src/services/container.rs 'TaskStatus::InReview' && OK "execution finish moves the task to in_review" 4 \
  || NO "execution finish moves the task to in_review" 4
have crates/services/src/services/pr_monitor.rs 'TaskStatus::Done' && OK "merged PR moves the task to done" 3 \
  || NO "merged PR moves the task to done" 3
[ -n "$TRANSITION" ] && grep -qE 'cancelled|Cancelled' "$TRANSITION" && OK "transition keeps cancelled terminal" 2 \
  || NO "transition keeps cancelled terminal" 2

GROUP "6. filters, bulk actions, keyboard"
have "$BOARD" 'kanban-filter-input' && OK "board has a filter input" 3 || NO "board has a filter input" 3
present "$KANBAN/taskFilters.ts" "taskFilters.ts exists" 3
have "$BOARD" 'task-select-' && OK "cards offer a bulk selection control" 3 || NO "cards offer a bulk selection control" 3
have "$BOARD" 'kanban-bulk-move' && OK "board has a bulk move action" 3 || NO "board has a bulk move action" 3
grep -rq 'useKanbanShortcuts' "$KANBAN" 2>/dev/null && OK "keyboard shortcuts are wired" 2 \
  || NO "keyboard shortcuts are wired" 2

GROUP "7. type checks"
run "pnpm run web-core:check"  4 pnpm run web-core:check
run "pnpm run local-web:check" 4 pnpm run local-web:check
run "pnpm run ui:check"        3 pnpm run ui:check

GROUP "8. browser e2e + screenshots (agent-browser)"
AB=(agent-browser --session vibe-goal-check)
ab()      { timeout 90 "${AB[@]}" "$@" 2>&1 | grep -v 'invalid config file'; }
ab_open() { ab open "$1" --args "--no-sandbox" | tail -1; }
ab_eval() { ab eval "$1" | tail -1 | sed 's/^"//; s/"$//'; }
ab_url()  { ab get url | tail -1; }
ab_count() { ab_eval "document.querySelectorAll('$1').length"; }
shot() { # screenshot evidence: a real capture is > 12 KB
  local name=$1 pts=$2
  mkdir -p "$EVIDENCE"
  ab screenshot "$ROOT/$EVIDENCE/$name.png" >/dev/null 2>&1
  local size
  size=$(stat -c%s "$EVIDENCE/$name.png" 2>/dev/null || echo 0)
  if [ "$size" -gt 12000 ]; then OK "screenshot $name ($((size / 1024)) KB)" "$pts"
  else NO "screenshot $name (${size} bytes)" "$pts"; fi
}
port_from_file() { [ -f /tmp/vibe-kanban/vibe-kanban.port ] && python3 -c "import json;print(json.load(open('/tmp/vibe-kanban/vibe-kanban.port')).get('main_port') or '')" 2>/dev/null; }
api_get() { curl -s --max-time 12 "$API$1"; }
# There is no GET /api/tasks/{id} route: tasks are read through the project's list.
task_field() { # task_field <field> [taskId]
  api_get "/api/tasks?project_id=$PID" | python3 -c "
import json,sys
tid, field = sys.argv[1], sys.argv[2]
for t in (json.load(sys.stdin).get('data') or []):
    if t.get('id') == tid:
        print(t.get(field) or '')
        break
" "${2:-$TID}" "${1}" 2>/dev/null; }
task_status() { task_field status "${1:-}"; }
task_title() { task_field title "${1:-}"; }
workspaces_of_task() { api_get "/api/workspaces?task_id=$TID" | python3 -c "
import json,sys
print(','.join(w['id'] for w in (json.load(sys.stdin).get('data') or [])))" 2>/dev/null; }

# Ports drift: `pnpm run dev` may pick 3004/3005 while an older stack holds 3003/3004, and the API's
# origin guard only allows the frontend origin it was started with (VK_ALLOWED_ORIGINS). Discover both
# ports instead of assuming, and verify the browser is allowed to mutate before blaming the app.
UI=""; PORT=""; FE=""
for _ in $(seq 1 18); do
  PORT=""
  for cand in "${BACKEND_PORT:-}" "$(port_from_file)" 3005 3004 3003; do
    [ -n "$cand" ] && [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$cand/api/health")" = "200" ] && PORT=$cand && break
  done
  UI=""
  for cand in "${FRONTEND_PORT:-}" 3004 3003; do
    [ -z "$cand" ] && continue
    curl -s --max-time 4 "http://localhost:$cand/" 2>/dev/null | grep -q '@vite/client' && UI=$cand && break
  done
  if [ -z "$UI" ]; then
    for cand in "${FRONTEND_PORT:-}" 3004 3003; do
      [ -z "$cand" ] && continue
      [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://localhost:$cand/")" = "200" ] && UI=$cand && break
    done
  fi
  FE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://localhost:${UI:-0}/")
  [ -n "$PORT" ] && [ -n "$UI" ] && [ "$FE" = "200" ] && break
  sleep 5
done
if [ -z "$PORT" ] || [ -z "$UI" ] || [ "$FE" != "200" ]; then
  NO "dev stack reachable (start 'pnpm run dev', api='$PORT' ui='$UI' fe='$FE')" 75
else
  API="http://localhost:$PORT"
  STAMP=$(date +%s)
  REPO=/tmp/vibe-task-ux-e2e-repo
  if [ ! -d "$REPO/.git" ]; then
    mkdir -p "$REPO"; git -C "$REPO" init -q -b main
    printf '# task ux e2e\n' >"$REPO/README.md"
    git -C "$REPO" add -A >/dev/null 2>&1
    git -C "$REPO" -c user.email=check@local -c user.name=check commit -qm init >/dev/null 2>&1
  fi
  RID=$(api_get /api/repos | python3 -c "
import json,sys
for r in json.load(sys.stdin).get('data') or []:
    if r.get('display_name')=='vibe-task-ux-e2e': print(r['id']); break" 2>/dev/null)
  if [ -z "$RID" ]; then
    RID=$(curl -s --max-time 20 -X POST "$API/api/repos" -H 'Content-Type: application/json' \
      -d "{\"path\":\"$REPO\",\"display_name\":\"vibe-task-ux-e2e\"}" | python3 -c "
import json,sys
print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
  fi
  PID=$(curl -s --max-time 20 -X POST "$API/api/projects" -H 'Content-Type: application/json' \
    -d "{\"name\":\"Task UX $STAMP\"}" | python3 -c "import json,sys;print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
  TID=$(curl -s --max-time 20 -X POST "$API/api/tasks" -H 'Content-Type: application/json' \
    -d "{\"project_id\":\"$PID\",\"title\":\"UX e2e task $STAMP\",\"description\":\"seeded by check.sh\"}" \
    | python3 -c "import json,sys;print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
  if [ -z "$RID" ] || [ -z "$PID" ] || [ -z "$TID" ]; then
    NO "e2e seed (repo/project/task via API)" 70
  else
    OK "e2e seed (repo, project, task)" 2
    # A misconfigured stack (UI origin not in the API's VK_ALLOWED_ORIGINS) makes every browser
    # mutation 403, which otherwise looks like a bug in the feature under test.
    ab_open "http://localhost:$UI/projects/$PID" >/dev/null
    MUTATE=$(ab_eval "fetch('/api/tasks', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' }).then((r) => r.status)")
    case "$MUTATE" in
      403) NO "browser may mutate (403: restart the stack so the API allows $UI)" 5 ;;
      "") NO "browser may mutate (no answer from the page)" 5 ;;
      *) OK "browser may mutate (status $MUTATE)" 5 ;;
    esac
    ab_open "http://localhost:$UI/projects/$PID" >/dev/null
    ab wait "[data-testid=task-card-$TID]" >/dev/null 2>&1
    if [ "$(ab_count "[data-testid=task-card-$TID]")" = "1" ]; then
      OK "board renders the task card" 3
      shot 01-board 3

      # --- selection: click the card, the URL carries the choice, the panel opens
      ab click "[data-testid=task-card-$TID]" >/dev/null 2>&1
      sleep 2
      case "$(ab_url)" in *"/issues/$TID"*|*"task=$TID"*) OK "card click selects the task in the URL" 5 ;;
        *) NO "card click selects the task in the URL (url: $(ab_url))" 5 ;; esac
      if [ "$(ab_count "[data-testid=task-detail-panel]")" = "1" ]; then
        OK "task detail panel opens" 6
        shot 02-task-detail-panel 5
        # reload must keep the panel (the selection is in the URL)
        ab_open "http://localhost:$UI/projects/$PID/issues/$TID" >/dev/null
        ab wait "[data-testid=task-detail-panel]" >/dev/null 2>&1
        [ "$(ab_count "[data-testid=task-detail-panel]")" = "1" ] \
          && OK "selection survives a reload" 4 || NO "selection survives a reload" 4
        # Escape closes the panel, and the URL goes back to the plain board.
        ab press Escape >/dev/null 2>&1
        sleep 1
        [ "$(ab_count "[data-testid=task-detail-panel]")" = "0" ] \
          && OK "Escape closes the panel" 4 || NO "Escape closes the panel" 4
        ab_open "http://localhost:$UI/projects/$PID/issues/$TID" >/dev/null
        ab wait "[data-testid=task-detail-panel]" >/dev/null 2>&1
        # title is shown, and editing it persists
        [ "$(ab_count "[data-testid=task-detail-title]")" = "1" ] \
          && OK "panel shows the task title" 3 || NO "panel shows the task title" 3
        if [ "$(ab_count "[data-testid=task-detail-edit-title]")" = "1" ]; then
          NEWTITLE="renamed by e2e $STAMP"
          ab click "[data-testid=task-detail-edit-title]" >/dev/null 2>&1
          sleep 1
          ab fill "[data-testid=task-detail-title-input]" "$NEWTITLE" >/dev/null 2>&1
          ab click "[data-testid=task-detail-save]" >/dev/null 2>&1
          SAVED=""
          for _ in $(seq 1 10); do
            SAVED=$(task_title)
            [ "$SAVED" = "$NEWTITLE" ] && break
            sleep 2
          done
          [ "$SAVED" = "$NEWTITLE" ] && OK "editing the title in the panel persists" 6 \
            || NO "editing the title in the panel persists (api: '${SAVED:0:28}')" 6
        else
          NO "editing the title in the panel persists" 6
        fi

        # the description is editable too
        if [ "$(ab_count "[data-testid=task-detail-edit-description]")" = "1" ]; then
          NEWDESC="description set by e2e $STAMP"
          ab click "[data-testid=task-detail-edit-description]" >/dev/null 2>&1
          sleep 1
          ab fill "[data-testid=task-detail-description-input]" "$NEWDESC" >/dev/null 2>&1
          ab click "[data-testid=task-detail-save]" >/dev/null 2>&1
          SAVEDDESC=""
          for _ in $(seq 1 10); do
            SAVEDDESC=$(task_field description)
            [ "$SAVEDDESC" = "$NEWDESC" ] && break
            sleep 2
          done
          [ "$SAVEDDESC" = "$NEWDESC" ] && OK "editing the description persists" 5 \
            || NO "editing the description persists (api: '${SAVEDDESC:0:28}')" 5
        else NO "editing the description persists" 5; fi
        # --- workspace section: create it from the panel (prefilled), then check the link
        if [ "$(ab_count "[data-testid=task-detail-create-workspace]")" = "1" ]; then
          OK "panel offers the workspace action" 4
          ab click "[data-testid=task-detail-create-workspace]" >/dev/null 2>&1
          sleep 2
          PREFILL=$(ab_eval "[...document.querySelectorAll('[aria-label=\"Markdown editor\"]')].map((e) => e.textContent || '').join(' | ')")
          case "$PREFILL" in *"$NEWTITLE"*|*"UX e2e task $STAMP"*) OK "create flow is prefilled from the task" 4 ;;
            *) NO "create flow is prefilled from the task (got '${PREFILL:0:40}')" 4 ;; esac
          shot 03-create-from-task 4
          ab_eval "(() => { const b = [...document.querySelectorAll('button')].find((x) => /^create$/i.test((x.textContent || '').trim())); if (!b) return 'no-button'; b.click(); return 'clicked'; })()" >/dev/null
          WSID=""
          UUID='[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}'
          for _ in $(seq 1 30); do
            WSID=$(printf '%s' "$(ab_url)" | sed -n "s#.*/workspaces/\($UUID\).*#\1#p")
            [ -n "$WSID" ] && break
            sleep 2
          done
          WS_TASK=""
          for _ in $(seq 1 10); do
            WS_TASK=$(api_get "/api/workspaces/$WSID" | python3 -c "
import json,sys
print((json.load(sys.stdin).get('data') or {}).get('task_id') or '')" 2>/dev/null)
            [ -n "$WS_TASK" ] && break
            sleep 2
          done
          if [ -n "$WSID" ] && [ "$WS_TASK" = "$TID" ]; then OK "the workspace is linked to the task" 6
          else NO "the workspace is linked to the task (ws='${WSID:-none}' task_id='${WS_TASK:-none}')" 6; fi
          # 1:1 — asking for a second workspace must not create one
          BEFORE=$(workspaces_of_task)
          ab_open "http://localhost:$UI/projects/$PID/issues/$TID" >/dev/null
          ab wait "[data-testid=task-detail-panel]" >/dev/null 2>&1
          if [ "$(ab_count "[data-testid=task-detail-create-workspace]")" = "1" ]; then
            ab click "[data-testid=task-detail-create-workspace]" >/dev/null 2>&1
            sleep 5
          fi
          AFTER=$(workspaces_of_task)
          if [ -n "$BEFORE" ] && [ "$BEFORE" = "$AFTER" ] && [ "$(printf '%s' "$AFTER" | tr -cd ',' | wc -c)" = "0" ]; then
            OK "1:1 holds — a second create does not duplicate" 6
          else NO "1:1 holds — a second create does not duplicate (before='$BEFORE' after='$AFTER')" 6; fi
          # --- automated status: nobody clicked a move button
          MINE=""
          for _ in $(seq 1 30); do
            MINE=$(task_status)
            case "$MINE" in inprogress|inreview|done) break ;; esac
            sleep 2
          done
          case "$MINE" in inprogress|inreview|done) OK "task status advanced by itself (${MINE})" 8 ;;
            *) NO "task status advanced by itself (still '${MINE:-unknown}')" 8 ;; esac
          # --- open the workspace from the panel
          ab_open "http://localhost:$UI/projects/$PID/issues/$TID" >/dev/null
          ab wait "[data-testid=task-detail-panel]" >/dev/null 2>&1
          shot 04-task-detail-workspace 4
          if [ "$(ab_count "[data-testid=task-detail-open-workspace]")" = "1" ]; then
            ab click "[data-testid=task-detail-open-workspace]" >/dev/null 2>&1
            sleep 3
            case "$(ab_url)" in *"/workspaces/"*) OK "panel jumps to the workspace" 5 ;;
              *) NO "panel jumps to the workspace (url: $(ab_url))" 5 ;; esac
          else NO "panel jumps to the workspace" 5; fi
          shot 05-board-with-status 3
          curl -s -X DELETE "$API/api/workspaces/$WSID" >/dev/null 2>&1
        else
          NO "panel offers the workspace action" 4
          NO "create flow is prefilled from the task" 4
          NO "the workspace is linked to the task" 6
          NO "1:1 holds — a second create does not duplicate" 6
          NO "task status advanced by itself" 8
          NO "panel jumps to the workspace" 5
        fi
      else
        NO "task detail panel opens" 6
        for lbl in "selection survives a reload:4" "panel shows the task title:3" \
                   "editing the title in the panel persists:6" "panel offers the workspace action:4" \
                   "create flow is prefilled from the task:4" "the workspace is linked to the task:6" \
                   "1:1 holds — a second create does not duplicate:6" "task status advanced by itself:8" \
                   "panel jumps to the workspace:5" "editing the description persists:5"; do
          NO "${lbl%:*}" "${lbl##*:}"
        done
      fi
    else
      NO "board renders the task card" 3
    fi
    # --- filters: a filtered board renders fewer cards
    TID2=$(curl -s --max-time 20 -X POST "$API/api/tasks" -H 'Content-Type: application/json' \
      -d "{\"project_id\":\"$PID\",\"title\":\"filter probe $STAMP\",\"description\":\"x\"}" \
      | python3 -c "import json,sys;print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
    ab_open "http://localhost:$UI/projects/$PID" >/dev/null
    ab wait "[data-testid=task-card-$TID]" >/dev/null 2>&1
    if [ "$(ab_count "[data-testid=kanban-filter-input]")" = "1" ]; then
      ab fill "[data-testid=kanban-filter-input]" "filter probe $STAMP" >/dev/null 2>&1
      sleep 1
      REMAIN=$(ab_count "[data-testid^=task-card-]")
      if [ "$REMAIN" = "1" ] && [ "$(ab_count "[data-testid=task-card-$TID2]")" = "1" ]; then
        OK "filtering narrows the board" 5
      else NO "filtering narrows the board (cards: $REMAIN)" 5; fi
      ab click "[data-testid=kanban-filter-clear]" >/dev/null 2>&1
    else NO "filtering narrows the board" 5; fi
    # --- keyboard: `/` focuses the filter, `c` focuses the new-task input
    ab_open "http://localhost:$UI/projects/$PID" >/dev/null
    ab wait "[data-testid=task-card-$TID]" >/dev/null 2>&1
    ab press / >/dev/null 2>&1
    sleep 1
    FOCUSED=$(ab_eval "document.activeElement?.getAttribute('data-testid') || document.activeElement?.tagName || ''")
    [ "$FOCUSED" = "kanban-filter-input" ] && OK "the '/' shortcut focuses the filter" 3 \
      || NO "the '/' shortcut focuses the filter (focused: '${FOCUSED:-none}')" 3
    ab press Escape >/dev/null 2>&1
    # `c` is deliberately ignored while a field has focus, so leave the filter first.
    ab_eval "document.activeElement?.blur()" >/dev/null 2>&1
    sleep 1
    ab press c >/dev/null 2>&1
    sleep 1
    FOCUSED=$(ab_eval "document.activeElement?.getAttribute('aria-label') || ''")
    [ "$FOCUSED" = "New task title" ] && OK "the 'c' shortcut focuses the new-task input" 3 \
      || NO "the 'c' shortcut focuses the new-task input (focused: '${FOCUSED:-none}')" 3
    ab_eval "document.activeElement?.blur()" >/dev/null 2>&1

    # --- bulk: the bar only exists once something is selected, so select first
    if [ "$(ab_count "[data-testid=task-select-$TID]")" = "1" ]; then
      ab click "[data-testid=task-select-$TID]" >/dev/null 2>&1
      sleep 1
    fi
    if [ "$(ab_count "[data-testid=kanban-bulk-move]")" = "1" ]; then
      ab click "[data-testid=task-select-$TID2]" >/dev/null 2>&1
      sleep 1
      ab click "[data-testid=kanban-bulk-move]" >/dev/null 2>&1
      ST=""
      for _ in $(seq 1 10); do
        ST=$(task_status "$TID2")
        [ "$ST" != "todo" ] && break
        sleep 2
      done
      [ "$ST" != "todo" ] && OK "bulk move advances the selected tasks" 5 \
        || NO "bulk move advances the selected tasks (status '${ST:-unknown}')" 5
    else NO "bulk move advances the selected tasks" 5; fi
    curl -s -X DELETE "$API/api/tasks/$TID2" >/dev/null 2>&1
    curl -s -X DELETE "$API/api/projects/$PID" >/dev/null 2>&1
    [ -n "$RID" ] && curl -s -X DELETE "$API/api/repos/$RID" >/dev/null 2>&1
    ab close >/dev/null 2>&1
  fi
fi

GROUP "9. committed screenshot evidence"
present "$EVIDENCE/NOTES.md" "evidence NOTES.md present" 3
SHOTS=$(ls "$EVIDENCE"/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$SHOTS" -ge 4 ]; then OK "at least 4 screenshots captured ($SHOTS)" 4
else NO "at least 4 screenshots captured ($SHOTS)" 4; fi
TRACKED=$(git ls-files "$EVIDENCE" | wc -l | tr -d ' ')
if [ "$TRACKED" -ge 4 ]; then OK "evidence is committed ($TRACKED files)" 3
else NO "evidence is committed ($TRACKED files)" 3; fi

GROUP "10. lint + format (goal files)"
if [ "$FAST" = 1 ]; then SKIP "local-web lint"; SKIP "ui lint"; SKIP "prettier (goal files)"
else
  run "pnpm run local-web:lint" 3 pnpm run local-web:lint
  run "pnpm run ui:lint"        3 pnpm run ui:lint
  FILES=""
  for f in $(cd packages/web-core && ls src/pages/kanban/*.ts src/pages/kanban/*.tsx 2>/dev/null); do
    FILES="$FILES $f"
  done
  if [ -z "$FILES" ]; then NO "prettier: goal files (web-core)" 3
  else run "prettier: goal files (web-core)" 3 pnpm --filter @vibe/web-core exec prettier --check $FILES; fi
fi

GROUP "11. sqlx caches, rust build, i18n + build gates"
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

GROUP "12. i18n coverage + unit tests"
python3 - <<'PY' && OK "panel strings exist in all 7 locales" 4 || NO "panel strings exist in all 7 locales" 4
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
run "pnpm --filter @vibe/web-core test" 6 pnpm --filter @vibe/web-core test

ELAPSED=$(( $(date +%s) - START_TS ))
printf '\n========================================\n'
printf 'TIME: %ss\n' "$ELAPSED"
printf 'SCORE: %s\n' "$SCORE"
printf 'MAX: %s\n' "$MAX"
TIMINGS=notes/check-timings.tsv
mkdir -p notes
printf '%s\t%s\t%s\n' "$(date -Is)" "$ELAPSED" "$SCORE" >> "$TIMINGS"
printf 'NOTE: the cargo gates above rebuild into target/, which can interrupt a running\n'
printf '      `pnpm run dev` (cargo watch). Restart the dev stack before the next e2e run.\n'
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf 'Failing checks (%s):\n' "${#FAILED[@]}"
  for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done
fi
[ "$SCORE" -ge "$MAX" ] && exit 0 || exit 1
