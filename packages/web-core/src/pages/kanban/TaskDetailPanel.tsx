import { useTranslation } from 'react-i18next';
import type { Task } from 'shared/types';
import { STATUS_LABEL } from './localKanbanModel';

interface TaskDetailPanelProps {
  task: Task;
  onClose: () => void;
}

/**
 * The task's detail view. It is rendered beside the board whenever the URL
 * selects a task (`/projects/<projectId>/issues/<taskId>`), so the panel is
 * linkable and survives a reload.
 */
export function TaskDetailPanel({ task, onClose }: TaskDetailPanelProps) {
  const { t } = useTranslation('common');

  return (
    <aside
      data-testid="task-detail-panel"
      aria-label={t('kanban.task.details')}
      className="flex min-h-0 w-80 shrink-0 flex-col gap-half overflow-y-auto border-l border-border bg-primary p-base"
    >
      <div className="flex items-start justify-between gap-half">
        <h2
          data-testid="task-detail-title"
          className="min-w-0 break-words text-base font-semibold text-high"
        >
          {task.title}
        </h2>
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
      <span data-testid="task-detail-status" className="text-xs text-low">
        {STATUS_LABEL[task.status] ?? task.status}
      </span>
      <p
        data-testid="task-detail-description"
        className="whitespace-pre-wrap break-words text-sm text-normal"
      >
        {task.description}
      </p>
    </aside>
  );
}
