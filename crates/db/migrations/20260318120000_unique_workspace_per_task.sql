-- A task owns at most one workspace: the link is 1:1. Workspaces with no task
-- (created from a PR or the plain create flow) are exempt, hence the partial index.
CREATE UNIQUE INDEX IF NOT EXISTS idx_workspaces_task_id_unique
    ON workspaces (task_id)
    WHERE task_id IS NOT NULL;
