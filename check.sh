#!/usr/bin/env bash
# Goal check: first-class pi (pi-acp) executor support in Vibe Kanban.
# Usage: ./check.sh          exit 0 = all criteria met; prints "SCORE: <0-100>"
#        CHECK_FAST=1 ./check.sh   skip e2e (static + build only)
# Env: BACKEND_PORT overrides the auto-resolved backend port.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
ROOT=$PWD
START_TS=$(date +%s)
FRESH_STATE=0
[ "${1:-}" = "--fresh-state" ] && FRESH_STATE=1
DEV_ASSETS_BAK="${PWD}/dev_assets.fresh-bak"
if [ "$FRESH_STATE" = "1" ]; then
  PF_PORT=$(python3 -c "import json;print(json.load(open('/tmp/vibe-kanban/vibe-kanban.port'))['main_port'])" 2>/dev/null || true)
  for candidate in 3001 3004 "$PF_PORT"; do
    [ -n "$candidate" ] || continue
    if [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$candidate/api/health" 2>/dev/null)" = "200" ]; then
      echo "fresh-state: a backend is already running on :$candidate - stop the dev stack first" >&2
      exit 1
    fi
  done
  if [ -e "$DEV_ASSETS_BAK" ]; then
    echo "fresh-state: $DEV_ASSETS_BAK already exists (previous run crashed?)" >&2
    exit 1
  fi
  [ -d dev_assets ] && mv dev_assets "$DEV_ASSETS_BAK"
  echo "fresh-state: dev_assets moved aside; the check will start its own backend"
fi

SCORE=0
MAX=0
PASSED=""
declare -a FAILED=()
POINT() { SCORE=$((SCORE + $1)); PASSED="$PASSED $2"; }
OK()   { printf '  [ok]   %-56s +%s\n' "$1" "$2"; POINT "$2" "$1"; MAX=$((MAX + $2)); }
NO()   { printf '  [MISS] %-56s  (0/%s)\n' "$1" "$2"; FAILED+=("$1"); MAX=$((MAX + $2)); }
GROUP(){ printf '\n== %s ==\n' "$1"; }
have() { grep -qE "$2" "$1" 2>/dev/null; }

GROUP "1. executor module"
PI_RS=crates/executors/src/executors/pi.rs
if [ -f "$PI_RS" ]; then
  have "$PI_RS" 'impl StandardCodingAgentExecutor' && OK "pi.rs implements StandardCodingAgentExecutor" 3 || NO "pi.rs implements StandardCodingAgentExecutor" 3
  have "$PI_RS" 'AcpAgentHarness' && OK "pi.rs uses AcpAgentHarness" 3 || NO "pi.rs uses AcpAgentHarness" 3
  have "$PI_RS" 'normalize_logs' && OK "pi.rs normalizes ACP logs" 2 || NO "pi.rs normalizes ACP logs" 2
  have "$PI_RS" 'pi-acp' && OK "pi.rs spawns pi-acp" 2 || NO "pi.rs spawns pi-acp" 2
  have "$PI_RS" 'github:ball6847/pi-acp' && OK "pi.rs runs our pi-acp fork" 4 || NO "pi.rs runs our pi-acp fork (github:ball6847/pi-acp)" 4
else
  NO "crates/executors/src/executors/pi.rs exists" 10
fi

GROUP "2. registration in mod.rs"
M=crates/executors/src/executors/mod.rs
have "$M" 'pub mod pi'        && OK "mod.rs: pub mod pi" 2        || NO "mod.rs: pub mod pi" 2
have "$M" 'pi::Pi'            && OK "mod.rs: imports pi::Pi" 2    || NO "mod.rs: imports pi::Pi" 2
have "$M" '^[[:space:]]*Pi\(Pi\)|^[[:space:]]*Pi,' && OK "mod.rs: CodingAgent::Pi variant" 3 || NO "mod.rs: CodingAgent::Pi variant" 3
have "$M" 'Self::Pi\('        && OK "mod.rs: get_mcp_config arm for Pi" 3 || NO "mod.rs: get_mcp_config arm for Pi" 3

GROUP "3. profiles + generated types"
python3 -c "import json,sys;d=json.load(open('crates/executors/default_profiles.json'));sys.exit(0 if 'PI' in d.get('executors',{}) else 1)" 2>/dev/null \
  && OK "default_profiles.json has PI" 4 || NO "default_profiles.json has PI" 4
have shared/types.ts 'PI = "PI"' && OK "shared/types.ts has PI in BaseCodingAgent" 3 || NO "shared/types.ts has PI in BaseCodingAgent" 3
have shared/types.ts 'export type Pi' && OK "shared/types.ts exports the Pi struct type" 3 || NO "shared/types.ts exports the Pi struct type (ts-rs export list)" 3

GROUP "4. frontend surface"
AI=packages/web-core/src/shared/components/AgentIcon.tsx
have "$AI" 'BaseCodingAgent.PI' && OK "AgentIcon.tsx handles PI" 4 || NO "AgentIcon.tsx handles PI" 4
have "$AI" '/agents/pi\$\{suffix\}\.svg' && OK "AgentIcon.tsx maps pi icon path" 3 || NO "AgentIcon.tsx maps pi icon path" 3
if [ -f packages/public/agents/pi-light.svg ] && [ -f packages/public/agents/pi-dark.svg ]; then
  OK "pi-light.svg + pi-dark.svg exist" 3
else NO "pi-light.svg + pi-dark.svg exist" 3; fi

GROUP "5. docs + tests"
python3 - <<'PYEOF'
import json, re, sys
src = open('docs/agents/pi.mdx').read()
problems = []
if not src.startswith('---'):
    problems.append('missing frontmatter')
elif not re.search(r'^title:', src, re.M) or not re.search(r'^description:', src, re.M):
    problems.append('frontmatter lacks title/description')
for open_tag, close_tag in (('<Steps>', '</Steps>'), ('<Step ', '</Step>')):
    if src.count(open_tag) != src.count(close_tag):
        problems.append(f'unbalanced {open_tag.strip("<>")} tags: {src.count(open_tag)}/{src.count(close_tag)}')
try:
    json.load(open('docs/docs.json'))
except Exception as exc:
    problems.append(f'docs.json invalid: {exc}')
print('; '.join(problems))
sys.exit(1 if problems else 0)
PYEOF
if [ $? -eq 0 ]; then OK "docs/agents/pi.mdx is well formed (frontmatter, Step tags, docs.json)" 3
else NO "docs/agents/pi.mdx is well formed (see message above)" 3; fi
have docs/supported-coding-agents.mdx 'href="/agents/pi"' && OK "listed in supported-coding-agents.mdx" 2 || NO "listed in supported-coding-agents.mdx" 2
if [ -f "$PI_RS" ] && have "$PI_RS" '#\[cfg\(test\)\]' && have "$PI_RS" '#\[test\]'; then
  OK "pi.rs has unit tests" 5
else NO "pi.rs has unit tests" 5; fi

GROUP "6. POC hack removed"
if [ ! -f dev_assets/profiles.json ] || ! grep -q 'base_command_override' dev_assets/profiles.json; then
  OK "no base_command_override left in dev_assets/profiles.json" 4
else NO "POC hack still present (dev_assets/profiles.json overrides QWEN_CODE)" 4; fi

GROUP "7. build"
run_check() { timeout 900 cargo check -p "$1" >/tmp/pi-goal-check-$1.log 2>&1; }
run_check executors && OK "cargo check -p executors" 3 || NO "cargo check -p executors (see /tmp/pi-goal-check-executors.log)" 3
run_check server    && OK "cargo check -p server" 3    || NO "cargo check -p server (see /tmp/pi-goal-check-server.log)" 3
timeout 600 pnpm run web-core:check >/tmp/pi-goal-check-webcore.log 2>&1 && OK "web-core tsc --noEmit (generated types compile)" 4 \
  || NO "web-core tsc --noEmit (see /tmp/pi-goal-check-webcore.log)" 4

# Count running pi-acp processes without pgrep (a pattern in this script would match itself).
count_agent_procs() {
  python3 - <<'PYEOF'
import os
needle = 'pi-a' + 'cp'
n = 0
for e in os.listdir('/proc'):
    if not e.isdigit():
        continue
    try:
        cl = open(f'/proc/{e}/cmdline', 'rb').read().decode('utf8', 'replace').replace('\0', ' ')
    except Exception:
        continue
    if needle in cl and 'python3' not in cl:
        n += 1
print(n)
PYEOF
}
AGENTS_BEFORE=$(count_agent_procs | tr -d ' ')
DB_PATH=""
for candidate in dev_assets/db.v2.sqlite dev_assets/db.sqlite; do
  [ -f "$candidate" ] && DB_PATH=$candidate && break
done
count_db_rows() {
  [ -n "$DB_PATH" ] || { echo 0; return; }
  python3 -c "
import sqlite3
c = sqlite3.connect('$DB_PATH')
print(sum(1 for t in ('workspaces','sessions','execution_processes','coding_agent_turns') for _ in c.execute(f'select 1 from {t}')))
" 2>/dev/null || echo 0
}
ROWS_BEFORE=$(count_db_rows | tr -d ' ')
WT_ROOT=/var/tmp/vibe-kanban-dev/worktrees
WT_BEFORE_LIST=$(ls -1 "$WT_ROOT" 2>/dev/null)
WT_BEFORE=$(printf '%s\n' "$WT_BEFORE_LIST" | grep -c . )
PORTFILE=/tmp/vibe-kanban/vibe-kanban.port
port_from_file() { [ -f "$PORTFILE" ] && python3 -c "import json;print(json.load(open('$PORTFILE')).get('main_port') or '')" 2>/dev/null; }
health_on() { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://localhost:$1/api/health" 2>/dev/null)" = "200" ]; }
# Resolve a *reachable* backend: env override -> port file -> default 3001.
PORT=""
for cand in "${BACKEND_PORT:-}" "$(port_from_file)" 3001; do
  [ -n "$cand" ] && health_on "$cand" && PORT=$cand && break
done
PORT=${PORT:-${BACKEND_PORT:-3001}}
API="http://localhost:$PORT"
SERVER_PID=""
cleanup() {
  [ -n "${WS_ID:-}" ] && curl -s --max-time 5 -X DELETE "$API/api/workspaces/$WS_ID" >/dev/null 2>&1
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT
health() { health_on "$PORT"; }
purge_run_worktrees() {
  # Worktree cleanup is disabled in dev (DISABLE_WORKTREE_CLEANUP), so remove any directory this run added.
  for dir in $(ls -1 "$WT_ROOT" 2>/dev/null); do
    printf '%s\n' "$WT_BEFORE_LIST" | grep -qx "$dir" || rm -rf "$WT_ROOT/$dir" 2>/dev/null
  done
}
_cleanup_trap() {
  [ -n "${WS_ID:-}" ] && curl -s --max-time 5 -X DELETE "$API/api/workspaces/$WS_ID" >/dev/null 2>&1
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" >/dev/null 2>&1
  purge_run_worktrees
  if [ "${FRESH_STATE:-0}" = "1" ]; then
    sleep 2
    rm -rf dev_assets
    [ -d "$DEV_ASSETS_BAK" ] && mv "$DEV_ASSETS_BAK" dev_assets
  fi
  return 0
}
trap _cleanup_trap EXIT

GROUP "8. API exposes PI executor"
if health; then
  echo "  (reusing backend already listening on :$PORT)"
else
  cargo build --bin server >/tmp/pi-goal-check-build.log 2>&1
  if [ -x target/debug/server ]; then
    rm -f "$PORTFILE"
    nohup ./target/debug/server >/tmp/pi-goal-check-server.log 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 1 60); do
      p=$(port_from_file); [ -n "$p" ] && PORT=$p && API="http://localhost:$PORT"
      health && break
      sleep 2
    done
  fi
fi
if health && curl -s --max-time 8 "$API/api/profiles" | python3 -c "
import json,sys
d=json.load(sys.stdin); c=d.get('data',{}).get('content') or d.get('data') or {}
c=json.loads(c) if isinstance(c,str) else c
sys.exit(0 if 'PI' in (c.get('executors') or {}) else 1)" 2>/dev/null; then
  OK "/api/profiles lists executor PI" 5
else NO "/api/profiles lists executor PI" 5; fi

GROUP "9. end-to-end run through the API"
if [ -n "${CHECK_FAST:-}" ]; then
  echo "  (CHECK_FAST=1 — e2e skipped)"
elif ! health; then
  NO "backend not reachable on :$PORT" 25
else
  REPO=/tmp/pi-goal-check-repo
  if [ ! -d "$REPO/.git" ]; then
    rm -rf "$REPO"; mkdir -p "$REPO"; git -C "$REPO" init -q -b main
    printf '# pi goal check\n' >"$REPO/README.md"
    git -C "$REPO" add -A >/dev/null 2>&1
    git -C "$REPO" -c user.email=check@local -c user.name=check commit -qm init >/dev/null 2>&1
  fi
  RID=$(curl -s --max-time 20 -X POST "$API/api/repos" -H 'Content-Type: application/json' \
        -d "{\"path\":\"$REPO\",\"display_name\":\"pi-goal-check\"}" |
        python3 -c "import json,sys;print(json.load(sys.stdin).get('data',{}).get('id') or '')" 2>/dev/null)
  # The shared repo carries a setup script, so every run also covers setup-before-agent ordering.
  curl -s --max-time 20 -X PUT "$API/api/repos/$RID" -H 'Content-Type: application/json' \
    -d '{"setup_script":"echo SETUP-CHECK-OK > SETUP_CHECK.txt"}' >/dev/null 2>&1
  curl -s --max-time 60 -X POST "$API/api/workspaces/start" -H 'Content-Type: application/json' \
        -d "{\"name\":\"pi-check\",\"repos\":[{\"repo_id\":\"$RID\",\"target_branch\":\"main\"}],\"executor_config\":{\"executor\":\"PI\"},\"prompt\":\"Create a file named PI_E2E.md containing exactly: PI-E2E-OK. Then reply with the single word DONE.\"}" >/tmp/pi-goal-check-start.json 2>/dev/null
  WS_ID=$(python3 -c "import json;d=json.load(open('/tmp/pi-goal-check-start.json'));x=d.get('data') or {};print((x.get('workspace') or {}).get('id') or '')" 2>/dev/null)
  # Resolve the coding agent process from the session: `start` returns the *setup* process when a repo defines a
  # setup script, so trusting its id would poll (and pass) before the agent ever ran.
  EPID=$(python3 - <<'PYEOF'
import json, sqlite3, time
start = json.load(open('/tmp/pi-goal-check-start.json'))
sid = ((start.get('data') or {}).get('execution_process') or {}).get('session_id')
if not sid:
    print('')
    raise SystemExit
raw = bytes.fromhex(sid.replace('-', ''))
db = sqlite3.connect('dev_assets/db.v2.sqlite')
for _ in range(20):
    rows = [r[0] for r in db.execute(
        "select id from execution_processes where session_id=? and run_reason='codingagent' order by created_at desc limit 1",
        (raw,))]
    if rows:
        print(rows[0].hex())
        break
    time.sleep(2)
PYEOF
)
  SID=$(python3 -c "import json;d=json.load(open('/tmp/pi-goal-check-start.json'));x=d.get('data') or {};print((x.get('execution_process') or {}).get('session_id') or '')" 2>/dev/null)
  STATUS=""
  if [ -n "$EPID" ]; then
    for _ in $(seq 1 60); do
      STATUS=$(curl -s --max-time 10 "$API/api/execution-processes/$EPID" |
        python3 -c "import json,sys;d=json.load(sys.stdin);p=d.get('data') or {};print(f\"{p.get('status')}:{p.get('exit_code')}\")" 2>/dev/null)
      case "$STATUS" in completed:*) break;; esac
      sleep 5
    done
  fi
  case "$STATUS" in
    completed:0) OK "workspace ran pi executor to completion (exit 0)" 4 ;;
    *) NO "workspace ran pi executor to completion (got '${STATUS:-no-process}')" 4 ;;
  esac
  SETUP_MARKER=$(find "$WT_ROOT" -maxdepth 4 -path '*pi-check*' -name SETUP_CHECK.txt -newermt '-30 minutes' 2>/dev/null | head -1)
  if [ -n "$SETUP_MARKER" ] && grep -q 'SETUP-CHECK-OK' "$SETUP_MARKER"; then
    OK "repo setup script ran before pi (marker present)" 1
  else NO "repo setup script ran before pi (marker '${SETUP_MARKER:-none}')" 1; fi
  FOUND=$(find /var/tmp/vibe-kanban-dev/worktrees /tmp/vibe-kanban-worktrees -maxdepth 3 -path '*pi-goal-check-repo*' -name PI_E2E.md -newermt '-30 minutes' 2>/dev/null | head -1)
  if [ -n "$FOUND" ] && grep -q 'PI-E2E-OK' "$FOUND"; then OK "agent wrote PI_E2E.md with expected content" 1
  else NO "agent wrote PI_E2E.md with expected content" 1; fi

  # Attachment contract: an uploaded file must be readable by pi at <workspace>/.vibe-attachments/.
  # Driven from python so the JSON payload cannot be mangled by shell quoting.
  ATT_RESULT=$(curl -s --max-time 30 -F "image=@/tmp/pi-check-blue.png;type=image/png" "$API/api/attachments/upload" > /tmp/pi-check-attach.json; \
    python3 - "$PORT" "$RID" "$WT_ROOT" <<'PYEOF'
import json, subprocess, sys, time, sqlite3

port, repo_id, wt_root = sys.argv[1], sys.argv[2], sys.argv[3]
api = f'http://localhost:{port}'
up = json.load(open('/tmp/pi-check-attach.json'))['data']
path = up['file_path']
prompt = (f"Step 1: read the image file {path} with your read tool. "
          "Step 2: create the file PI_IMG.txt in your working directory containing exactly one word chosen from "
          "red, green, blue, yellow - the closest to the image dominant colour - and nothing else. "
          "Step 3: reply with just that word.")

def post(p, body, t=60):
    out = subprocess.run(['curl', '-s', '--max-time', str(t), '-X', 'POST', f'{api}{p}',
                          '-H', 'Content-Type: application/json', '-d', json.dumps(body)],
                         capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}

def get(p):
    out = subprocess.run(['curl', '-s', '--max-time', '20', f'{api}{p}'], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}

def _agent_pid(sid):
    '''Resolve the coding agent process: start returns the setup process when a repo has one.'''
    if not sid:
        return ''
    raw = bytes.fromhex(sid.replace('-', ''))
    db = sqlite3.connect('dev_assets/db.v2.sqlite')
    for _ in range(20):
        rows = [r[0] for r in db.execute(
            "select id from execution_processes where session_id=? and run_reason='codingagent' order by created_at desc limit 1",
            (raw,))]
        if rows:
            return rows[0].hex()
        time.sleep(2)
    return ''

start = post('/api/workspaces/start', {
    'name': 'pi-check-attach',
    'repos': [{'repo_id': repo_id, 'target_branch': 'main'}],
    'executor_config': {'executor': 'PI'},
    'prompt': prompt,
    'attachment_ids': [up['id']],
})
_data = start.get('data') or {}
_first = _data.get('execution_process') or {}
proc = {'id': _agent_pid(_first.get('session_id'))}
ws = _data.get('workspace') or {}
status = 'no-process'
summary = ''
content = ''
path_found = 'none'

if proc.get('id'):
    for _ in range(40):
        time.sleep(5)
        p = (get(f"/api/execution-processes/{proc['id']}") or {}).get('data') or {}
        status = f"{p.get('status')}:{p.get('exit_code')}"
        if status.startswith(('completed', 'failed', 'killed')):
            break

    # The process can report completion just before the turn row is final.
    rows = []
    for _ in range(10):
        rows = [r[0] or '' for r in sqlite3.connect('dev_assets/db.v2.sqlite').execute(
            'select summary from coding_agent_turns where execution_process_id=?',
            (bytes.fromhex(proc['id'].replace('-', '')),))]
        if any('blue' in r.lower() for r in rows):
            break
        time.sleep(3)
    summary = rows[0].strip() if rows else ''

    found = subprocess.run(['find', wt_root, '-maxdepth', '4', '-path', '*pi-check-attach*',
                            '-name', 'PI_IMG.txt'], capture_output=True, text=True).stdout.split('\n')
    found = [f for f in found if f.strip()]
    if found:
        path_found = found[0]
        try:
            content = open(path_found).read().strip()[:20]
        except Exception:
            content = ''

if ws.get('id'):
    subprocess.run(['curl', '-s', '--max-time', '10', '-X', 'DELETE', f"{api}/api/workspaces/{ws['id']}"],
                   capture_output=True)
print(f"{status}|{content}|{'blue' in summary.lower()}|{up['id']}|{path_found}")
PYEOF
)
  ATT_STATUS=${ATT_RESULT%%|*}
  ATT_REST=${ATT_RESULT#*|}
  ATT_CONTENT=${ATT_REST%%|*}
  ATT_ANSWER_OK=${ATT_REST#*|}; ATT_ANSWER_OK=${ATT_ANSWER_OK%%|*}
  ATT_REST2=${ATT_REST#*|}; ATT_REST2=${ATT_REST2#*|}
  ATT_ID=${ATT_REST2%%|*}
  ATT_FILE=${ATT_REST2#*|}
  if [ "$ATT_CONTENT" = "blue" ] || [ "$ATT_ANSWER_OK" = "true" ]; then
    OK "attached image read by pi (file '${ATT_CONTENT:-none}', status '$ATT_STATUS')" 2
  else NO "attached image read by pi (status '$ATT_STATUS', file '${ATT_FILE:-none}', content '${ATT_CONTENT:-empty}')" 2; fi

  # Concurrency: two workspaces started together on the same repo must not share sessions or worktrees.
  CONC=$(python3 - "$PORT" "$RID" "$WT_ROOT" <<'PYEOF'
import json, sqlite3, subprocess, sys, time
port, repo_id, wt_root = sys.argv[1], sys.argv[2], sys.argv[3]
api = f'http://localhost:{port}'

def post(p, body, t=60):
    out = subprocess.run(['curl', '-s', '--max-time', str(t), '-X', 'POST', f'{api}{p}',
                          '-H', 'Content-Type: application/json', '-d', json.dumps(body)],
                         capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}

def get(p):
    out = subprocess.run(['curl', '-s', '--max-time', '20', f'{api}{p}'], capture_output=True, text=True).stdout
    try:
        return json.loads(out)
    except Exception:
        return {}

def _agent_pid(sid):
    '''Resolve the coding agent process: start returns the setup process when a repo has one.'''
    if not sid:
        return ''
    raw = bytes.fromhex(sid.replace('-', ''))
    db = sqlite3.connect('dev_assets/db.v2.sqlite')
    for _ in range(20):
        rows = [r[0] for r in db.execute(
            "select id from execution_processes where session_id=? and run_reason='codingagent' order by created_at desc limit 1",
            (raw,))]
        if rows:
            return rows[0].hex()
        time.sleep(2)
    return ''

runs = {}
for tag, word in (('c1', 'ALPHA'), ('c2', 'BRAVO')):
    resp = post('/api/workspaces/start', {
        'name': f'pi-check-{tag}',
        'repos': [{'repo_id': repo_id, 'target_branch': 'main'}],
        'executor_config': {'executor': 'PI'},
        'prompt': (f"Create the file CONC_{tag}.txt containing exactly: {word}. "
                   f"Then reply with the single word {word}."),
    })
    data = resp.get('data') or {}
    first = data.get('execution_process') or {}
    runs[tag] = {'pid': _agent_pid(first.get('session_id')),
                 'ws': (data.get('workspace') or {}).get('id'),
                 'word': word, 'status': 'no-process'}

deadline = time.time() + 240
while time.time() < deadline:
    if all(r['status'].startswith(('completed', 'failed', 'killed')) for r in runs.values()):
        break
    time.sleep(5)
    for tag, r in runs.items():
        if not r['pid'] or r['status'].startswith(('completed', 'failed', 'killed')):
            continue
        p = (get(f"/api/execution-processes/{r['pid']}") or {}).get('data') or {}
        r['status'] = f"{p.get('status')}:{p.get('exit_code')}"

out = []
for tag, r in runs.items():
    other = 'BRAVO' if r['word'] == 'ALPHA' else 'ALPHA'
    base = subprocess.run(['bash', '-lc',
        f"ls -d {wt_root}/*pi-check-{tag} 2>/dev/null | head -1"], capture_output=True, text=True).stdout.strip()
    own = ''
    leak = ''
    if base:
        own = subprocess.run(['bash', '-lc', f"cat {base}/*/CONC_{tag}.txt 2>/dev/null | tr -d '[:space:]'"],
                             capture_output=True, text=True).stdout.strip()
        leak = subprocess.run(['bash', '-lc', f"ls {base}/*/CONC_{other}_*.txt 2>/dev/null | head -1"],
                              capture_output=True, text=True).stdout.strip()
    out.append(f"{tag}:{r['status']}:{own}:{'leak' if leak else 'clean'}")
    if r['ws']:
        subprocess.run(['curl', '-s', '--max-time', '20', '-X', 'DELETE', f"{api}/api/workspaces/{r['ws']}"],
                       capture_output=True)

summary = {
    'runs': out,
    'ok': all(f"{tag}:{r['status']}:{r['word']}:clean" in out for tag, r in runs.items()),
}
print(json.dumps(summary))
PYEOF
)
  CONC_OK=$(printf '%s' "$CONC" | python3 -c "import json,sys;print(1 if (json.load(sys.stdin) or {}).get('ok') else 0)" 2>/dev/null || echo 0)
  if [ "${CONC_OK:-0}" = "1" ]; then OK "concurrent pi runs stayed isolated" 1
  else NO "concurrent pi runs stayed isolated (got '${CONC:-none}')" 1; fi

  if [ -n "$ATT_ID" ]; then
    ATTDEL=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X DELETE "$API/api/attachments/$ATT_ID")
    case "$ATTDEL" in 200|204) ;; *) echo "  (warning: deleting attachment $ATT_ID returned $ATTDEL)" ;; esac
    rm -f "$ROOT/.vibe-attachments/"* 2>/dev/null
  fi
  DB=""
  for c in dev_assets/db.v2.sqlite dev_assets/db.sqlite; do [ -f "$c" ] && DB=$c && break; done
  turn_summary_for() {
    local EPHEX
    EPHEX=$(printf '%s' "$1" | tr -d '-')
    python3 -c "
import sqlite3,sys
try: raw=bytes.fromhex('$EPHEX')
except Exception: sys.exit(1)
c=sqlite3.connect('$DB')
rows=[r[0] or '' for r in c.execute('select summary from coding_agent_turns where execution_process_id=?',(raw,))]
print('|'.join(rows))
" 2>/dev/null
  }
  SUMMARY=$(turn_summary_for "$EPID")
  if [ -n "$SUMMARY" ]; then OK "turn recorded for this run (summary: ${SUMMARY:0:40})" 1
  else NO "turn recorded for this run" 1; fi

  # Supervised policy + thinking level must reach the executor and still run. The coding agent process is resolved
  # from the session because `start` returns the setup process when a repo defines a setup script.
  SUP=$(python3 - "$PORT" "$RID" <<'PYEOF'
import json, subprocess, sys, time, sqlite3
port, repo_id = sys.argv[1], sys.argv[2]
api = f'http://localhost:{port}'

def sh(a, t=120):
    return subprocess.run(a, capture_output=True, text=True, timeout=t).stdout

def req(method, p, body=None):
    args = ['curl', '-s', '--max-time', '120', '-X', method, f'{api}{p}']
    if body is not None:
        args += ['-H', 'Content-Type: application/json', '-d', json.dumps(body)]
    try:
        return json.loads(sh(args))
    except Exception:
        return {}

start = req('POST', '/api/workspaces/start', {
    'name': 'pi-check-supervised',
    'repos': [{'repo_id': repo_id, 'target_branch': 'main'}],
    'executor_config': {'executor': 'PI', 'permission_policy': 'SUPERVISED', 'reasoning_id': 'minimal'},
    'prompt': 'Reply with the single word SUPERVISED-OK.',
})
data = start.get('data') or {}
first = data.get('execution_process') or {}
ws = (data.get('workspace') or {}).get('id')
cfg = json.dumps(((first.get('executor_action') or {}).get('typ') or {}).get('executor_config'))

pid = ''
if first.get('session_id'):
    raw = bytes.fromhex(first['session_id'].replace('-', ''))
    db = sqlite3.connect('dev_assets/db.v2.sqlite')
    for _ in range(20):
        rows = [r[0] for r in db.execute(
            "select id from execution_processes where session_id=? and run_reason='codingagent' order by created_at desc limit 1",
            (raw,))]
        if rows:
            pid = rows[0].hex()
            break
        time.sleep(2)

status = 'no-process'
if pid:
    # The durable config lives on the coding agent process (the start response may describe the setup process).
    proc = (req('GET', f'/api/execution-processes/{pid}') or {}).get('data') or {}
    agent_cfg = ((proc.get('executor_action') or {}).get('typ') or {}).get('executor_config')
    if agent_cfg is not None:
        cfg = json.dumps(agent_cfg)
    for _ in range(40):
        time.sleep(5)
        p = (req('GET', f'/api/execution-processes/{pid}') or {}).get('data') or {}
        status = f"{p.get('status')}:{p.get('exit_code')}"
        if status.startswith(('completed', 'failed', 'killed')):
            break

if ws:
    sh(['curl', '-s', '--max-time', '20', '-X', 'DELETE', f'{api}/api/workspaces/{ws}'])
print(json.dumps({'cfg': cfg, 'status': status}))
PYEOF
)
  SUPCFG=$(printf '%s' "$SUP" | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('cfg') or 'null')" 2>/dev/null || echo null)
  SUPSTATUS=$(printf '%s' "$SUP" | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('status') or '')" 2>/dev/null || echo '')
  case "$SUPCFG" in
    *SUPERVISED*) OK "SUPERVISED policy accepted by the API" 1 ;;
    *) NO "SUPERVISED policy accepted by the API (got '$SUPCFG')" 1 ;;
  esac
  case "$SUPCFG" in
    *minimal*) OK "reasoning_id recorded on the request" 1 ;;
    *) NO "reasoning_id recorded on the request (got '$SUPCFG')" 1 ;;
  esac
  case "$SUPSTATUS" in
    completed:0) OK "supervised + thinking-level run completed (exit 0)" 1 ;;
    *) NO "supervised + thinking-level run completed (got '${SUPSTATUS:-none}')" 1 ;;
  esac

  GROUP "10. follow-up keeps context"
  if [ -n "$SID" ]; then
    FUP=$(curl -s --max-time 30 -X POST "$API/api/sessions/$SID/follow-up" -H 'Content-Type: application/json' \
      -d '{"executor_config":{"executor":"PI"},"prompt":"What is the exact content of PI_E2E.md? Reply with only that content."}' |
      python3 -c "import json,sys;print((json.load(sys.stdin).get('data') or {}).get('id') or '')" 2>/dev/null)
    for _ in $(seq 1 24); do
      s=$(curl -s --max-time 10 "$API/api/execution-processes/$FUP" |
        python3 -c "import json,sys;d=json.load(sys.stdin);p=d.get('data') or {};print(p.get('status') or '')" 2>/dev/null)
      case "$s" in completed|failed|killed) break;; esac
      sleep 5
    done
    FS=$(turn_summary_for "$FUP")
    case "$FS" in
      *PI-E2E-OK*) OK "follow-up turn recalled turn-1 content" 5 ;;
      *) NO "follow-up turn recalled turn-1 content (summary: ${FS:0:40})" 5 ;;
    esac
  else NO "follow-up turn recalled turn-1 content (no session found)" 5; fi
fi

GROUP "11. pi model discovery"
have "$PI_RS" 'MODEL_SELECTION_SUPPORTED: bool = true' && OK "pi model selection switched on" 4 || NO "pi model selection switched on (MODEL_SELECTION_SUPPORTED)" 4
if ! health; then
  NO "backend reachable for model discovery" 5
else
  cat > /tmp/pi-goal-models.mjs <<'JS'
const port = process.argv[2] || '3004';
const repoId = process.argv[3];
const query = repoId ? `executor=PI&repo_id=${repoId}` : 'executor=PI';
const ws = new WebSocket(`ws://localhost:${port}/api/agents/discovered-options/ws?${query}`);
let done = false;
const finish = (ok, info) => { if (done) return; done = true; console.log(JSON.stringify(info)); process.exit(ok ? 0 : 1); };
ws.onmessage = (e) => {
  let msg; try { msg = JSON.parse(e.data); } catch { return; }
  const patches = msg.JsonPatch || msg.json_patch || [];
  const sel = patches.map((p) => p.value).find((v) => v && v.model_selector)?.model_selector;
  if (!sel) return;
  const commands = patches.map((p) => p.value).find((v) => v && v.slash_commands !== undefined)?.slash_commands || [];
  finish(true, {
    models: sel.models?.length || 0,
    modelIds: (sel.models || []).slice(0, 400).map((m) => ({ id: m.id, provider: m.provider_id })),
    providers: sel.providers?.length || 0,
    commands: commands.length,
    modelsWithReasoning: (sel.models || []).filter((m) => (m.reasoning_options || []).length > 0).length,
    defaultInList: !!(sel.default_model && (sel.models || []).some(
      (m) => (m.provider_id ? `${m.provider_id}/${m.id}` : m.id) === sel.default_model)),
  });
};
ws.onerror = () => finish(false, { error: 'ws error' });
setTimeout(() => finish(false, { error: 'timeout' }), 30000);
JS
  OUT=$(node /tmp/pi-goal-models.mjs "$PORT" "${RID:-}" 2>/dev/null)
  MODELS=$(printf '%s' "$OUT" | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('models',0))" 2>/dev/null || echo 0)
  CMDS=$(printf '%s' "$OUT" | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('commands',0))" 2>/dev/null || echo 0)
  REASON=$(printf '%s' "$OUT" | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('modelsWithReasoning',0))" 2>/dev/null || echo 0)
  # pi switches models through the ACP session config option, which the pinned protocol crate cannot send; our pi-acp fork
  # accepts the legacy `session/set_model` call those clients send and translates it. So the selector must be offered again.
  if [ "${MODELS:-0}" -gt 0 ]; then OK "discovered-options: $MODELS models advertised" 3
  else NO "discovered-options: models advertised (got '$OUT')" 3; fi
  if [ "${REASON:-0}" -gt 0 ]; then OK "discovered-options: $REASON models expose thinking levels" 2
  else NO "discovered-options: models with thinking levels (got '$OUT')" 2; fi
  if [ "${CMDS:-0}" -gt 0 ]; then OK "discovered-options: $CMDS slash commands" 2
  else NO "discovered-options: slash commands (got '$OUT')" 2; fi
  DEFAULT_IN_LIST=$(printf '%s' "$OUT" | python3 -c "import json,sys;d=json.load(sys.stdin) or {};print(1 if d.get('defaultInList') else 0)" 2>/dev/null || echo 0)
  if [ "${DEFAULT_IN_LIST:-0}" = "1" ]; then OK "discovered-options: default model present in the list" 2
  else NO "discovered-options: default model in list (got '$OUT')" 2; fi
  # Vibe Kanban composes the id it sends as `provider_id/id`, so a model id that already carries its provider would be
  # sent doubled (`kimi-coding/kimi-coding/k3`) and silently ignored by pi.
  DOUBLED=$(printf '%s' "$OUT" | python3 -c "import json,sys;d=json.load(sys.stdin) or {};sel=d.get('modelIds') or [];print(len([m for m in sel if m.get('provider') and str(m.get('id','')).startswith(str(m['provider'])+'/')]))" 2>/dev/null || echo 0)
  if [ "${DOUBLED:-1}" = "0" ]; then OK "discovered-options: model ids stay provider-relative" 3
  else NO "model ids must not repeat their provider ($DOUBLED doubled)" 3; fi
fi

GROUP "12. run hygiene"
# Delete the workspaces this run created, then purge their worktree dirs and compare with the start state.
[ -n "${WS_ID:-}" ] && curl -s --max-time 10 -X DELETE "$API/api/workspaces/$WS_ID" >/dev/null 2>&1
purge_run_worktrees
WT_AFTER=$(ls -1 "$WT_ROOT" 2>/dev/null | wc -l | tr -d ' ')
if [ "${WT_AFTER:-0}" -le "${WT_BEFORE:-0}" ]; then
  OK "check run left no extra worktrees ($WT_BEFORE -> $WT_AFTER)" 1
else NO "check run left extra worktrees ($WT_BEFORE -> $WT_AFTER)" 1; fi
AGENTS_AFTER=$(count_agent_procs | tr -d ' ')
if [ "${AGENTS_AFTER:-0}" -le "${AGENTS_BEFORE:-0}" ]; then
  OK "no leftover pi-acp processes ($AGENTS_BEFORE -> $AGENTS_AFTER)" 1
else NO "leftover pi-acp processes ($AGENTS_BEFORE -> $AGENTS_AFTER)" 1; fi
ROWS_AFTER=$(count_db_rows | tr -d ' ')
if [ "${ROWS_AFTER:-0}" -le "${ROWS_BEFORE:-0}" ]; then
  OK "no leaked workspace/session/turn rows ($ROWS_BEFORE -> $ROWS_AFTER)" 1
else NO "leaked workspace/session/turn rows ($ROWS_BEFORE -> $ROWS_AFTER)" 1; fi

GROUP "13. browser evidence"
# Staleness is judged by CONTENT, not file times: a checkout, rebase or squash rewrites mtimes without changing code, which
# made the time-based version cry wolf. The manifest records the hash of every file the screenshots were captured against;
# it is refreshed (only after re-capturing the evidence) from the repository root with:
#   sha256sum <repo-relative paths> > .context/evidence/pi/code-hashes.txt
UI_SURFACE="packages/web-core/src/shared/components/AgentIcon.tsx packages/public/agents/pi-light.svg"
UI_MANIFEST=.context/evidence/pi/code-hashes.txt
UI_RUN_PNG=$(ls -1 .context/evidence/pi/*ui-run*.png 2>/dev/null | head -1)
if [ -f "$UI_MANIFEST" ]; then
  STALE=""
  while read -r want path; do
    case "$want" in ''|'#'*) continue;; esac # comment or blank line
    have=$(sha256sum "$path" 2>/dev/null | cut -d' ' -f1)
    [ "$have" = "$want" ] || STALE="${STALE:+$STALE, }$path"
  done < "$UI_MANIFEST"
  if [ -z "$STALE" ]; then OK "UI evidence matches the code it was captured against (content hashes)" 1
  else NO "UI evidence is stale - changed since the screenshots: $STALE" 1; fi
elif [ -n "$UI_RUN_PNG" ]; then
  STALE=$(find $UI_SURFACE -newer "$UI_RUN_PNG" 2>/dev/null | head -1)
  if [ -z "$STALE" ]; then OK "UI evidence is newer than the agent icon surface (mtime fallback, no manifest)" 1
  else NO "UI evidence is stale - $STALE changed after $UI_RUN_PNG" 1; fi
else NO "UI evidence is stale - no *ui-run*.png artifact found" 1; fi
EV=.context/evidence/pi
if ls "$EV"/*.png >/dev/null 2>&1 && [ -f "$EV/NOTES.md" ]; then
  OK "browser screenshots + NOTES.md present" 2
  if ls "$EV"/*ui*run*.png "$EV"/*logs*.png >/dev/null 2>&1; then
    OK "UI-driven run artifact (log stream screenshot) present" 2
  else NO "UI-driven run artifact (log stream screenshot, e.g. *logs*.png) present" 1; fi
else NO "browser screenshots + NOTES.md in .context/evidence/pi" 5; fi

GROUP "14. the chosen model reaches pi"
# Model/thinking selection is only useful if the choice lands in the agent. Vibe Kanban's client cannot send the modern
# config-option request, so our pi-acp fork translates the legacy `session/set_model` call. Prove it end to end: start a run
# with a non-default model and a level, then read pi's own session log for that checkout.
if [ -n "${CHECK_FAST:-}" ]; then
  printf '  [skip] %-56s (CHECK_FAST)\n' "chosen model reaches pi (needs a live run)"
elif ! health; then
  NO "backend reachable for the model-selection run" 6
else
  cat > /tmp/pi-goal-c4.py <<'PYC4'
"""Start a run with a chosen model and level, then assert pi actually used them.

Reads pi's own session log (model_change / thinking_level_change events) for the checkout the run used, so the claim is
checked against the agent's record rather than the request we sent.
"""
import json
import glob
import os
import sqlite3
import subprocess
import sys
import time

port = sys.argv[1]
API = f'http://localhost:{port}'
NAME = 'pi-check-model'
MODEL, LEVEL = 'kimi-coding/k3', 'low'
PROVIDER, _, MODEL_ID = MODEL.partition('/')


def sh(args, timeout=180):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout).stdout


def req(method, path, body=None):
    args = ['curl', '-s', '--max-time', '180', '-X', method, f'{API}{path}']
    if body is not None:
        args += ['-H', 'Content-Type: application/json', '-d', json.dumps(body)]
    try:
        return json.loads(sh(args))
    except Exception:
        return {}


def out(**kwargs):
    print(json.dumps(kwargs))
    sys.exit(0)


repos = [r for r in req('GET', '/api/repos')['data'] if r['display_name'] == 'pi-goal-check']
if not repos:
    out(error='pi-goal-check repo missing')
response = req('POST', '/api/workspaces/start', {
    'name': NAME,
    'repos': [{'repo_id': repos[0]['id'], 'target_branch': 'main'}],
    'executor_config': {'executor': 'PI', 'model_id': MODEL, 'reasoning_id': LEVEL},
    'prompt': 'Reply with the single word DONE.',
})
workspace = ((response.get('data') or {}).get('workspace') or {}).get('id')
if not workspace:
    out(error=f'workspace not created: {str(response)[:200]}')

db = sqlite3.connect('dev_assets/db.v2.sqlite')
rows = []
for _ in range(80):
    rows = list(db.execute(
        "select id,run_reason,status,exit_code from execution_processes where session_id in "
        "(select id from sessions where workspace_id=?) order by created_at",
        (bytes.fromhex(workspace.replace('-', '')),)))
    if rows and all(r[2] in ('completed', 'failed', 'killed') for r in rows):
        break
    time.sleep(5)
agent = [r for r in rows if r[1] == 'codingagent']
exit_code = agent[-1][3] if agent else None

session = None
pattern = os.path.expanduser('~/.pi/agent/sessions/*/*.jsonl')
for path in sorted(glob.glob(pattern), key=os.path.getmtime, reverse=True)[:40]:
    try:
        first = json.loads(open(path).readline())
    except Exception:
        continue
    if first.get('type') == 'session' and NAME in str(first.get('cwd', '')):
        session = path
        break

models, levels = [], []
if session:
    for line in open(session):
        try:
            event = json.loads(line)
        except Exception:
            continue
        if event.get('type') == 'model_change':
            models.append(f"{event.get('provider')}/{event.get('modelId')}")
        if event.get('type') == 'thinking_level_change':
            levels.append(event.get('thinkingLevel'))

req('DELETE', f'/api/workspaces/{workspace}')
out(exit_code=exit_code, requested=MODEL, session=bool(session), models=models, levels=levels,
    model_applied=f'{PROVIDER}/{MODEL_ID}' in models, level_applied=LEVEL in levels)
PYC4
  C4=$(python3 /tmp/pi-goal-c4.py "$PORT" 2>/dev/null)
  printf '  [info] %s\n' "model-selection run: $C4"
  C4_MODEL=$(printf '%s' "$C4" | python3 -c "import json,sys;print(1 if (json.load(sys.stdin) or {}).get('model_applied') else 0)" 2>/dev/null || echo 0)
  C4_LEVEL=$(printf '%s' "$C4" | python3 -c "import json,sys;print(1 if (json.load(sys.stdin) or {}).get('level_applied') else 0)" 2>/dev/null || echo 0)
  C4_EXIT=$(printf '%s' "$C4" | python3 -c "import json,sys;print((json.load(sys.stdin) or {}).get('exit_code'))" 2>/dev/null || echo None)
  if [ "$C4_MODEL" = "1" ]; then OK "run with a chosen model shows it in pi's session log" 4
  else NO "chosen model applied to pi (got '$C4')" 4; fi
  if [ "$C4_LEVEL" = "1" ]; then OK "chosen thinking level applied to pi" 2
  else NO "chosen thinking level applied to pi (got '$C4')" 2; fi
  if [ "$C4_EXIT" = "0" ]; then OK "the model-selection run completed (exit 0)" 2
  else NO "model-selection run completed (got exit '$C4_EXIT')" 2; fi
fi

ELAPSED=$(( $(date +%s) - START_TS ))
printf '\n========================================\n'
printf 'TIME: %ss\n' "$ELAPSED"
printf 'SCORE: %s\n' "$SCORE"
printf 'MAX: %s\n' "$MAX"
# Keep a small local trend log so slow drift is visible across iterations (gitignored).
TIMINGS=notes/check-timings.tsv
mkdir -p notes
printf '%s\t%s\t%s\n' "$(date -Is)" "$ELAPSED" "$SCORE" >> "$TIMINGS"
printf 'Recent runs (time/s, score) - %s:\n' "$TIMINGS"
tail -3 "$TIMINGS" | while IFS=$'\t' read -r when secs score; do printf '  %s  %ss  SCORE %s\n' "${when:0:16}" "$secs" "$score"; done
if [ "${#FAILED[@]}" -gt 0 ]; then
  printf 'Failing checks (%s):\n' "${#FAILED[@]}"
  for f in "${FAILED[@]}"; do printf '  - %s\n' "$f"; done
fi
[ "$SCORE" -ge "$MAX" ] && exit 0 || exit 1
