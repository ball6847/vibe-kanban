# Evidence — task ↔ workspace link (agent-browser CLI)

Every claim below was produced by driving the real UI with the `agent-browser` CLI
(`--session vibe-goal-check`, `--args "--no-sandbox"`), then cross-checked against the API.
`./check.sh` section 7 replays the same flow automatically.

## Verified (e2e)

| Claim | How it was checked |
| --- | --- |
| A task card offers **Create workspace** | `[data-testid=task-create-workspace-<taskId>]` exists on the card |
| The action opens the local create flow | URL becomes `/workspaces/create` |
| The flow is prefilled from the task | the composer editor (`aria-label="Markdown editor"`) contains the task title |
| Submitting creates and opens the workspace | URL becomes `/workspaces/<uuid>` |
| The workspace is linked to the task | `GET /api/workspaces/<uuid>` → `task_id == <taskId>`, and `GET /api/workspaces?task_id=<taskId>` returns exactly that workspace |
| The card shows the linked workspace | `[data-testid=task-open-workspace-<workspaceId>]` exists on the card |
| Clicking it opens the workspace | URL becomes `/workspaces/<workspaceId>` |

Screenshot: `e2e-create-from-task.png` (written by the gate at the end of the flow).

## Notes

- The prompt editor is a Lexical `contenteditable` that does not forward `data-testid`, so the gate
  locates it by its `aria-label="Markdown editor"` and submits via the composer's `Create` button.
- `agent-browser screenshot <relative-path>` writes relative to the **daemon's** cwd; the gate passes
  an absolute path.
- The link assertion polls, because the workspace row and the UI navigation are not ordered.
- Fixtures (repo, project, task, workspace) are created and deleted by the gate on every run.
