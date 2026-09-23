import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import type { Task, Workspace } from 'shared/types';
import { localTasksApi } from '@/shared/lib/api';
import { STATUS_LABEL } from './localKanbanModel';

interface TaskDetailPanelProps {
  task: Task;
  /** The task's single workspace, when it has one. */
  workspace: Workspace | null;
  onClose: () => void;
  onUpdated: (task: Task) => void;
  onDeleted: (taskId: string) => void;
  onOpenWorkspace: () => void;
  onCreateWorkspace: () => void;
}

type EditingField = 'title' | 'description' | null;

/**
 * The task's detail view, shown beside the board whenever the URL selects a task
 * (`/projects/<projectId>/issues/<taskId>`). Title and description are edited
 * inline and saved through the local API; status is shown as the board reports
 * it (it is maintained automatically, see the status automation milestone).
 */
export function TaskDetailPanel({
  task,
  workspace,
  onClose,
  onUpdated,
  onDeleted,
  onOpenWorkspace,
  onCreateWorkspace,
}: TaskDetailPanelProps) {
  const { t } = useTranslation('common');
  const [editing, setEditing] = useState<EditingField>(null);
  const [draft, setDraft] = useState('');
  const [isBusy, setIsBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const startEditing = (field: Exclude<EditingField, null>) => {
    setEditing(field);
    setDraft(field === 'title' ? task.title : (task.description ?? ''));
    setError(null);
  };

  const save = async () => {
    if (!editing || isBusy) {
      return;
    }

    setIsBusy(true);
    setError(null);
    try {
      // UpdateTask's fields are all required in the generated type, so the
      // untouched fields are echoed back unchanged.
      const updated = await localTasksApi.update(task.id, {
        title: editing === 'title' ? draft : task.title,
        description: editing === 'description' ? draft : task.description,
        status: task.status,
      });
      onUpdated(updated);
      setEditing(null);
    } catch (saveError) {
      setError(
        saveError instanceof Error ? saveError.message : 'Could not save task'
      );
    } finally {
      setIsBusy(false);
    }
  };

  const remove = async () => {
    if (isBusy) {
      return;
    }

    setIsBusy(true);
    setError(null);
    try {
      await localTasksApi.remove(task.id);
      onDeleted(task.id);
    } catch (removeError) {
      setError(
        removeError instanceof Error ? removeError.message : 'Could not delete'
      );
      setIsBusy(false);
    }
  };

  return (
    <aside
      data-testid="task-detail-panel"
      aria-label={t('kanban.task.details')}
      className="flex min-h-0 w-80 shrink-0 flex-col gap-base overflow-y-auto border-l border-border bg-primary p-base"
    >
      <div className="flex items-start justify-between gap-half">
        {editing === 'title' ? (
          <div className="flex min-w-0 flex-1 flex-col gap-half">
            <input
              data-testid="task-detail-title-input"
              aria-label={t('kanban.task.title')}
              value={draft}
              autoFocus
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') void save();
                if (event.key === 'Escape') setEditing(null);
              }}
              className="min-w-0 rounded-sm border border-border bg-secondary px-half py-half text-sm text-normal"
            />
            <div className="flex gap-half">
              <button
                type="button"
                data-testid="task-detail-save"
                disabled={isBusy}
                onClick={() => void save()}
                className="rounded-sm bg-brand px-half py-half text-xs font-medium text-on-brand disabled:opacity-50"
              >
                {t('kanban.task.save')}
              </button>
              <button
                type="button"
                onClick={() => setEditing(null)}
                className="rounded-sm px-half py-half text-xs text-low"
              >
                {t('kanban.task.cancel')}
              </button>
            </div>
          </div>
        ) : (
          <>
            <h2
              data-testid="task-detail-title"
              className="min-w-0 break-words text-base font-semibold text-high"
            >
              {task.title}
            </h2>
            <div className="flex shrink-0 items-center gap-half">
              <button
                type="button"
                data-testid="task-detail-edit-title"
                aria-label={t('kanban.task.editTitle')}
                title={t('kanban.task.editTitle')}
                onClick={() => startEditing('title')}
                className="rounded-sm px-half text-xs text-low"
              >
                {t('kanban.task.edit')}
              </button>
              <button
                type="button"
                data-testid="task-detail-close"
                aria-label={t('kanban.task.close')}
                title={t('kanban.task.close')}
                onClick={onClose}
                className="shrink-0 rounded-sm px-half text-sm text-low"
              >
                ×
              </button>
            </div>
          </>
        )}
      </div>

      <span data-testid="task-detail-status" className="text-xs text-low">
        {STATUS_LABEL[task.status] ?? task.status}
      </span>

      <div className="flex flex-col gap-half">
        <div className="flex items-center justify-between gap-half">
          <h3 className="text-xs font-medium text-low">
            {t('kanban.task.description')}
          </h3>
          {editing === 'description' ? null : (
            <button
              type="button"
              data-testid="task-detail-edit-description"
              aria-label={t('kanban.task.editDescription')}
              title={t('kanban.task.editDescription')}
              onClick={() => startEditing('description')}
              className="rounded-sm px-half text-xs text-low"
            >
              {t('kanban.task.edit')}
            </button>
          )}
        </div>
        {editing === 'description' ? (
          <>
            <textarea
              data-testid="task-detail-description-input"
              aria-label={t('kanban.task.description')}
              value={draft}
              autoFocus
              rows={6}
              onChange={(event) => setDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Escape') setEditing(null);
              }}
              className="min-w-0 rounded-sm border border-border bg-secondary px-half py-half text-sm text-normal"
            />
            <div className="flex gap-half">
              <button
                type="button"
                data-testid="task-detail-save"
                disabled={isBusy}
                onClick={() => void save()}
                className="rounded-sm bg-brand px-half py-half text-xs font-medium text-on-brand disabled:opacity-50"
              >
                {t('kanban.task.save')}
              </button>
              <button
                type="button"
                onClick={() => setEditing(null)}
                className="rounded-sm px-half py-half text-xs text-low"
              >
                {t('kanban.task.cancel')}
              </button>
            </div>
          </>
        ) : (
          <p
            data-testid="task-detail-description"
            className="whitespace-pre-wrap break-words text-sm text-normal"
          >
            {task.description || '—'}
          </p>
        )}
      </div>

      <div className="flex flex-col gap-half">
        <h3 className="text-xs font-medium text-low">
          {t('kanban.task.workspace')}
        </h3>
        {workspace ? (
          <div className="flex flex-col gap-half">
            <span className="truncate text-sm text-normal">
              {workspace.name ?? workspace.branch}
            </span>
            <button
              type="button"
              data-testid="task-detail-open-workspace"
              onClick={onOpenWorkspace}
              className="self-start rounded-sm border border-border px-half py-half text-xs text-normal"
            >
              {t('kanban.task.openWorkspace')}
            </button>
          </div>
        ) : (
          <div className="flex flex-col gap-half">
            <span className="text-sm text-low">
              {t('kanban.task.noWorkspace')}
            </span>
            <button
              type="button"
              data-testid="task-detail-create-workspace"
              onClick={onCreateWorkspace}
              className="self-start rounded-sm bg-brand px-half py-half text-xs font-medium text-on-brand"
            >
              {t('kanban.task.createWorkspace')}
            </button>
          </div>
        )}
      </div>

      {error ? (
        <p role="alert" className="text-xs text-low">
          {error}
        </p>
      ) : null}

      <button
        type="button"
        data-testid="task-detail-delete"
        disabled={isBusy}
        onClick={() => void remove()}
        className="mt-auto self-start rounded-sm border border-border px-half py-half text-xs text-low disabled:opacity-50"
      >
        {t('kanban.task.delete')}
      </button>
    </aside>
  );
}
