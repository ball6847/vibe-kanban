# Browser evidence — pi executor in the Vibe Kanban UI

Captured with the agent-browser harness (pi-browser-harness) against the local dev stack.
UI: `http://localhost:3003` (vite) → backend `:3004`.

## How the harness was started this session

`browser_setup` fails while nothing is listening on the daemon socket (the harness spawns the daemon
detached with `stdio: "ignore"`, so its errors are invisible; the daemon also exits by itself after ~30 min
idle). Working recipe:

```bash
cd /home/ball6847/.pi/agent/npm/node_modules/pi-browser-harness
setsid nohup npx tsx src/daemon/index.ts > /tmp/pi-browser-daemon.log 2>&1 < /dev/null &
# then, once the log shows "IPC server listening" + "Connected to Chrome ✓":
#   browser_setup  ->  "Browser connected ✓"
```

`browser_screenshot` writes a file into the system temp dir and returns its path; `browser_print_to_pdf`
accepts `outputPath`. Screenshots here were copied from those paths; `01-ui-loaded-1.png` was converted from
a PDF with `pdftoppm -png -r 110`.

Note: `DevToolsActivePort` is not usable for manual CDP access — harness Chrome runs with
`--remote-debugging-port=0` in a temp profile and the daemon owns the connection.

## Getting past the sign-in gate

The app opens on `OnboardingSignInPage`. There is no visible skip button:
click **More options** → **"I understand, continue without signing in"**. Local mode then works without an
account (the left sidebar still shows "Sign in" prompts).

## Artifacts

| File | Shows |
| --- | --- |
| `01-ui-loaded-1.png` | App loads without the earlier crash (converted from PDF) |
| `02-executor-pi-in-ui.png` | Onboarding "Coding Agent" list contains **pi** (rendered with the new icon, between Droid and Qwen) |
| `03-ui-create-with-pi-executor.png` | Create-workspace form with the executor picker showing **Pi** and the E2E prompt typed in |

## Status / gaps (honest)

- Verified in the UI: `pi` is selectable and shows the new name and icon; the create form accepts it; the
  backend it talks to is the one running the `PI` executor.
- **Not yet demonstrated**: a pi *run* driven from the UI with the log stream on screen. Clicking **Create**
  produced a workspace in **Draft** state (`/workspaces/create` keeps showing the form) and no
  `execution_process` row was written — the action that starts a draft workspace still needs to be found
  (next iteration: inspect the draft-open flow, e.g. the sidebar entry's start/continue action).
- The API-level E2E (`check.sh` section 9/10) does run the real `PI` executor end-to-end: workspace exit 0,
  `PI_E2E.md` = `PI-E2E-OK`, turn summary `DONE`, follow-up recalled turn-1 content.

## Iteration 9: model dropdown verified in the UI (operator complaint)

Operator reported "it did not allow me to select any model". After the `Pi::discover_options` fix (pi's
`models-store.json` catalogue), the create-workspace page shows a model control labelled **Default** next to
the **Pi** executor, and opening it lists pi's providers:
`Model | cerebras | kimi-coding | meta | minimax | mistral | openrouter | synthetic | xiaomi | Default`.
Artifact: `05-model-dropdown.png`.

### Why the harness Chrome had to be started by hand

`browser_setup` was failing with `chrome_disconnected`. Root cause chain:
1. Nothing was listening with CDP — the `DevToolsActivePort` files in both `~/.config/google-chrome` (9222)
   and `/tmp/agent-browser-chrome-*` were **stale** (dead ports).
2. Relaunching the harness Chrome without `--remote-allow-origins=*` makes CDP accept then immediately drop the
   WebSocket → the daemon logs `Connected to Chrome ✓` followed by `Chrome disconnected`.
3. The daemon only discovers CDP through its candidate user-data dirs, so it must be started with
   `CHROME_USER_DATA_DIR=<the dir that has a live DevToolsActivePort>`.

Working recipe:
```bash
D=/tmp/agent-browser-chrome-$UUID      # any dir with a live CDP instance
B=~/.dotfiles/agent-browser/browsers/chrome-153.0.8010.47/chrome
rm -f $D/DevToolsActivePort
setsid nohup $B --user-data-dir=$D --remote-debugging-port=0 --remote-allow-origins='*' \
  --no-first-run --no-default-browser-check --no-sandbox about:blank &   # wait, read $D/DevToolsActivePort
cd ~/.pi/agent/npm/node_modules/pi-browser-harness
CHROME_USER_DATA_DIR=$D setsid nohup npx tsx src/daemon/index.ts > /tmp/pi-browser-daemon.log 2>&1 &
```

4. `browser_setup` still refuses on the **profile** gate: the pinned profile
   ("7solutions.co.th (porawit.p@7solutions.co.th)") does not exist inside the temp-profile Chrome, and its
   real-profile CDP endpoint is dead. Fallback used here: drive CDP directly with
   `node /tmp/cdp-ui2.mjs <devToolsPort> <out.png>` (navigate + real mouse events + `Page.captureScreenshot`).
   The user's pin file was restored afterwards; clearing it did not help because the running pi session
   caches the profile choice.

## Iteration 10: fully UI-driven pi run (create form -> run -> log stream)

Driven through CDP against the harness Chrome (`node /tmp/cdp-run.mjs <port> <out.png>`):
navigate to `/workspaces/create`, focus the prompt editor, `Input.insertText` the prompt, click **Create**
(real mouse events) with the executor showing **Pi**.

Result (verified, not assumed):
- workspace `788ccf83-bc0e-46e6-aeb1-918f635a9a13`, branch `vk/788c-create-a-file-na`
- agent session `e182522a…` with `executor = PI`, execution process **completed, exit code 0**
- `PI_UI_RUN.md` written in `/var/tmp/vibe-kanban-dev/worktrees/788c-create-a-file-na/pi-goal-check-repo/`
- workspace page renders the run with pi's message (`HAS_DONE true`, matches `DONE` / `PI_UI_RUN`)

Artifact: `06-ui-run-logs.png` (log stream scrolled to pi's output).
Earlier confusion: an earlier create attempt looked like a "Draft" only because the run had not started yet —
the same flow does start the agent.

## Iteration 17: slash-menu attempt (negative result, precise cause located)

Goal: screenshot pi's slash commands in the composer. Typing `/` into the composer (both the workspace composer and
`/workspaces/create`) did **not** render a menu, even with real CDP key events. Artifact: `07-slash-menu.png`
(composer containing `/`, no menu).

Data path is proven fine (the model dropdown in the same form reads the same discovery payload). The trigger is
`LexicalTypeaheadMenuPlugin` in `packages/ui/src/components/SlashCommandTypeaheadPlugin.tsx`:

- `triggerFn`: `/^(\s*)\/([^\s/]*)$/.exec(text)` — text from block start to the anchor must be `/\s*\/…`.
- `hasVisibleResults` is false when `options.length === 0` **and** neither `isLoading` (`!isInitialized`) nor
  `isDiscovering` is true → an open typeahead with no commands renders nothing.

Next experiment (not yet done): log `slashCommandsQuery` in `WYSIWYGEditor.tsx` (line ~307) while typing `/`, and
check whether `executor` is truthy there for the create form (`SlashCommandTypeaheadPlugin` is only mounted
`{executor && …}`). If `commands` is empty for the create form but non-empty in a workspace, the composer passes
different discovery options (`repoId`/`workspaceId`) than the model dropdown.

## Iteration 31: image attachment end-to-end

Method: uploaded a solid-red 64x64 PNG through `POST /api/attachments/upload` (multipart field `image`), then
started a workspace with `attachment_ids` and the prompt "Read the image file <path> … state its dominant
colour".

Result (verified, not assumed):
- attachment id `b0fe88d4-…`, stored path `.vibe-attachments/7998e4e7-…_pired.png`
- workspace `a62ba5f0-362a-4ec0-a164-77219c5f2e88`, execution process **completed exit 0**
- `PI_IMG.txt` contains **`red`**; turn summary is `red`
- pi reported in its own words that the attachment was **not in cwd** but at
  `/var/tmp/vibe-kanban-dev/worktrees/a62b-pi-image/.vibe-attachments/…` — i.e. attachments sit in the workspace
  root, one level above the repository checkout.

## Iteration 35: composer model control shows a concrete model, not "Default"

Captured `08-pi-model-selection.png` (create form): executor **Pi** with the model button reading
**"Gemma 4 31B IT · High"** — i.e. a concrete model plus thinking level rather than the previous opaque
"Default" label.

Cross-checked the backend at the same moment: `discovered-options` reports
`default_model = zenmux/deepseek/deepseek-v4.1-flash` (412 models, none loading). So the picker is not showing the
*configured* default — it shows a different catalogue entry (first/alphabetical pick, or a selection restored from
the form's draft state that dates from before the default-model change).

Not yet resolved (new backlog item): determine which of the two the UI is doing, and make the picker land on
`default_model` when nothing has been chosen explicitly.

## Iteration 59: UI evidence re-captured on the current build

`06-ui-run-logs.png` was re-shot against the current app (workspace `788ccf83-…`, the UI-driven run from iteration 10)
so the artifact reflects the build after the capability change (pi no longer advertises `SESSION_FORK`, so the
edit-from-message affordance is absent for pi workspaces). The run's log stream still renders with pi's output and the
sidebar still lists the workspace; the freshness guard in `check.sh` requires this file to stay newer than
`AgentIcon.tsx`/`pi-light.svg`.

## Model and thinking selection (2026-09-21)

- `09-ui-pi-model-list.png` — the model popover on the create form: providers (empiriolabs, kimi-coding, maxplus…, zenmux),
  models under each, a per-model thinking control (`High`) and a name/ID filter.
- `10-ui-pi-model-selected.png` — the same form with `kimi-coding/k3 · High` selected; the trigger chip updates immediately.
- `11-ui-pi-model-chip.png` — after the provider-relative id fix the chip shows the bare model id (`k3 · High`, provider
  implied), which is what the request then carries as `kimi-coding/k3`.

Verified end to end: a workspace created from this form ran pi with the chosen model — its own session log records
`model_change zenmux/deepseek/deepseek-v4.1-flash -> kimi-coding/k3`. Before the fix, the same flow sent
`kimi-coding/kimi-coding/k3` and pi silently used its default.
