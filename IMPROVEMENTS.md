# IMPROVEMENTS — backlog (only after `SCORE == MAX`)

- The MCP `create_task_attempt` tool still builds a cloud `linked_issue` from
  `/api/remote/issues/{id}`, a route deleted with the remote feature; its workspace therefore gets
  no local `task_id`. Adapt it to local tasks or retire the tool.
- `Task.parent_workspace_id` remains unwritable (the reverse column); `workspace.task_id` is the
  single source of truth by design.
- `linked_issue` on the start request is now dead weight locally — remove it once nothing reads it.
- Repo-wide: 26 unformatted `web-core` files on `main`; 104 unused i18n keys on `main`; tracked
  `.pi-loop-log.jsonl`.
