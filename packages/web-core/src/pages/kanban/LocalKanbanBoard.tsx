import { useEffect, useMemo, useState } from 'react';
import { cn } from '@/shared/lib/utils';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import type { Task, TaskStatus } from 'shared/types';
import {
  localProjectsApi,
  localTasksApi,
  workspacesApi,
} from '@/shared/lib/api';
import { useAppNavigation } from '@/shared/hooks/useAppNavigation';
import { usePageTitle } from '@/shared/hooks/usePageTitle';
import {
  DEFAULT_WORKSPACE_CREATE_DRAFT_ID,
  buildWorkspaceCreateInitialState,
  buildWorkspaceCreatePrompt,
  persistWorkspaceCreateDraft,
} from '@/shared/lib/workspaceCreateState';
import {
  COLUMNS,
  STATUS_LABEL,
  groupTasksByColumn,
  stepStatus,
} from './localKanbanModel';
import { groupWorkspacesByTaskId } from './taskWorkspaceLinkModel';
import { TaskDetailPanel } from './TaskDetailPanel';
import { canTransitionTaskStatus } from './taskStatus';
import {
  EMPTY_TASK_FILTERS,
  filterTasks,
  isFiltering,
  type TaskFilters,
} from './taskFilters';

interface LocalKanbanBoardProps {
  projectId: string;
  /** Task selected by the URL, shown in the detail panel. */
  selectedTaskId?: string | null;
}

export function LocalKanbanBoard({
  projectId,
  selectedTaskId = null,
}: LocalKanbanBoardProps) {
  const { t } = useTranslation('common');
  const appNavigation = useAppNavigation();
  const { data: workspaces = [] } = useQuery({
    queryKey: ['workspaces'],
    queryFn: workspacesApi.getAllWorkspaces,
  });
  const workspacesByTaskId = useMemo(
    () => groupWorkspacesByTaskId(workspaces),
    [workspaces]
  );
  const [projectName, setProjectName] = useState<string | null>(null);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [newTaskTitle, setNewTaskTitle] = useState('');
  const [filters, setFilters] = useState<TaskFilters>(EMPTY_TASK_FILTERS);
  const [isCreating, setIsCreating] = useState(false);
  const [busyTaskId, setBusyTaskId] = useState<string | null>(null);
  const [reloadToken, setReloadToken] = useState(0);
  const [editingTaskId, setEditingTaskId] = useState<string | null>(null);
  const [editingTitle, setEditingTitle] = useState('');
  const [editingDescription, setEditingDescription] = useState('');

  usePageTitle(projectName, 'Projects');

  useEffect(() => {
    if (!selectedTaskId) {
      return;
    }

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        appNavigation.goToProject(projectId);
      }
    };

    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [appNavigation, projectId, selectedTaskId]);

  const selectedTask = tasks.find((task) => task.id === selectedTaskId) ?? null;

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setError(null);
    Promise.all([localProjectsApi.list(), localTasksApi.list(projectId)])
      .then(([projects, projectTasks]) => {
        if (cancelled) return;
        setProjectName(projects.find((p) => p.id === projectId)?.name ?? null);
        setTasks(projectTasks);
        setIsLoading(false);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(err instanceof Error ? err.message : 'Failed to load board');
        setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, reloadToken]);

  const visibleTasks = useMemo(
    () => filterTasks(tasks, filters),
    [tasks, filters]
  );
  const tasksByColumn = groupTasksByColumn(visibleTasks);

  const handleCreate = async () => {
    const title = newTaskTitle.trim();
    if (!title || isCreating) return;
    setIsCreating(true);
    try {
      const created = await localTasksApi.create({
        project_id: projectId,
        title,
        description: null,
      });
      setTasks((prev) => [...prev, created]);
      setNewTaskTitle('');
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to create task'
      );
    } finally {
      setIsCreating(false);
    }
  };

  const handleMove = async (task: Task, direction: -1 | 1) => {
    const next = stepStatus(task.status, direction);
    // The automation refuses to walk a task backwards; the board matches it so a
    // manual move cannot put the card somewhere the services would not follow.
    if (!next || !canTransitionTaskStatus(task.status, next)) {
      return;
    }
    if (!next || busyTaskId) return;
    setBusyTaskId(task.id);
    try {
      const updated = await localTasksApi.update(task.id, {
        title: null,
        description: null,
        status: next,
      });
      setTasks((prev) => prev.map((t) => (t.id === task.id ? updated : t)));
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to move task'
      );
    } finally {
      setBusyTaskId(null);
    }
  };

  const startEditing = (task: Task) => {
    setEditingTaskId(task.id);
    setEditingTitle(task.title);
    setEditingDescription(task.description ?? '');
  };

  const handleSaveEdit = async (task: Task) => {
    if (editingTaskId !== task.id) return;
    const title = editingTitle.trim();
    const description = editingDescription.trim();
    setEditingTaskId(null);
    if (!title || busyTaskId) return;
    if (title === task.title && description === (task.description ?? ''))
      return;
    setBusyTaskId(task.id);
    try {
      const updated = await localTasksApi.update(task.id, {
        title,
        description,
        status: null,
      });
      setTasks((prev) => prev.map((t) => (t.id === task.id ? updated : t)));
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to save task'
      );
    } finally {
      setBusyTaskId(null);
    }
  };

  /**
   * Opens the local create flow for this task. The draft carries the task's
   * title/description as the prompt plus the task id, which the start request
   * forwards so the new workspace is linked back to the task.
   */
  const handleSelectTask = (taskId: string) => {
    if (selectedTaskId === taskId) {
      return;
    }

    appNavigation.goToProjectIssue(projectId, taskId);
  };

  const handleCreateWorkspace = async (task: Task) => {
    // 1:1 — when the task already has a workspace, opening it is the only
    // sensible answer to "create one" (the database enforces the same rule).
    const existing = workspacesByTaskId.get(task.id)?.[0];
    if (existing) {
      appNavigation.goToWorkspace(existing.id);
      return;
    }

    const prompt = buildWorkspaceCreatePrompt(task.title, task.description);
    await persistWorkspaceCreateDraft(
      buildWorkspaceCreateInitialState({ prompt, taskId: task.id }),
      DEFAULT_WORKSPACE_CREATE_DRAFT_ID
    );
    appNavigation.goToWorkspacesCreate();
  };

  const handleDelete = async (taskId: string) => {
    if (busyTaskId) return;
    setBusyTaskId(taskId);
    try {
      await localTasksApi.remove(taskId);
      setTasks((prev) => prev.filter((t) => t.id !== taskId));
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to delete task'
      );
    } finally {
      setBusyTaskId(null);
    }
  };

  if (isLoading) {
    return (
      <div className="flex h-full w-full items-center justify-center">
        <p className="text-low">Loading board…</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-full w-full items-center justify-center p-base">
        <div className="flex flex-col items-center gap-half">
          <p className="text-low">Could not load tasks: {error}</p>
          <button
            type="button"
            onClick={() => setReloadToken((t) => t + 1)}
            className="rounded-sm border border-border bg-secondary px-base py-half text-sm text-normal"
          >
            Retry
          </button>
        </div>
      </div>
    );
  }

  if (projectName === null) {
    return (
      <div className="flex h-full w-full items-center justify-center p-base">
        <p className="text-low">Project not found</p>
      </div>
    );
  }

  return (
    <div className="flex h-full w-full flex-col bg-primary">
      <div className="flex shrink-0 items-baseline justify-between gap-half px-base pt-base">
        <h1 className="truncate text-lg font-semibold text-high">
          {projectName}
        </h1>
        <span className="shrink-0 text-xs text-low">
          {visibleTasks.length} {visibleTasks.length === 1 ? 'task' : 'tasks'}
        </span>
      </div>
      <div className="flex shrink-0 gap-half p-base pb-0">
        <input
          aria-label="New task title"
          value={newTaskTitle}
          onChange={(e) => setNewTaskTitle(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') void handleCreate();
          }}
          placeholder="New task…"
          className="min-w-0 flex-1 rounded-sm border border-border bg-secondary px-half py-half text-sm text-normal placeholder:text-low"
        />
        <button
          type="button"
          onClick={() => void handleCreate()}
          disabled={!newTaskTitle.trim() || isCreating}
          className="shrink-0 rounded-sm bg-brand px-base py-half text-sm font-medium text-on-brand disabled:opacity-50"
        >
          Add
        </button>
      </div>
      <div className="flex shrink-0 items-center gap-half px-base pt-half">
        <input
          data-testid="kanban-filter-input"
          aria-label={t('kanban.filter.placeholder')}
          value={filters.text}
          onChange={(event) =>
            setFilters((previous) => ({
              ...previous,
              text: event.target.value,
            }))
          }
          placeholder={t('kanban.filter.placeholder')}
          className="min-w-0 flex-1 rounded-sm border border-border bg-secondary px-half py-half text-xs text-normal placeholder:text-low"
        />
        <select
          data-testid="kanban-filter-status"
          aria-label={t('kanban.filter.status')}
          value={filters.status}
          onChange={(event) =>
            setFilters((previous) => ({
              ...previous,
              status: event.target.value as TaskFilters['status'],
            }))
          }
          className="shrink-0 rounded-sm border border-border bg-secondary px-half py-half text-xs text-normal"
        >
          <option value="all">{t('kanban.filter.all')}</option>
          {(Object.keys(STATUS_LABEL) as TaskStatus[]).map((status) => (
            <option key={status} value={status}>
              {STATUS_LABEL[status]}
            </option>
          ))}
        </select>
        {isFiltering(filters) ? (
          <button
            type="button"
            data-testid="kanban-filter-clear"
            aria-label={t('kanban.filter.clear')}
            onClick={() => setFilters(EMPTY_TASK_FILTERS)}
            className="shrink-0 rounded-sm border border-border px-half py-half text-xs text-low"
          >
            ×
          </button>
        ) : null}
      </div>
      {actionError ? (
        <div className="flex shrink-0 items-center justify-between gap-half px-base pt-half">
          <p role="alert" className="truncate text-xs text-low">
            {actionError}
          </p>
          <button
            type="button"
            aria-label="Dismiss error"
            onClick={() => setActionError(null)}
            className="shrink-0 rounded-sm px-half text-xs text-low"
          >
            ×
          </button>
        </div>
      ) : null}
      <div className="flex min-h-0 flex-1">
        <div className="flex min-h-0 min-w-0 flex-1 snap-x snap-mandatory gap-base overflow-x-auto p-base sm:snap-none">
          {COLUMNS.map((column) => {
            const columnTasks = column.status.flatMap(
              (status) => tasksByColumn.get(status) ?? []
            );
            return (
              <section
                key={column.label}
                aria-label={column.label}
                className="flex w-[85vw] shrink-0 snap-center flex-col rounded-sm border border-border bg-secondary sm:w-72"
              >
                <header className="flex items-center justify-between px-base py-half">
                  <h2 className="text-sm font-semibold text-high">
                    {column.label}
                  </h2>
                  <span className="text-xs text-low">{columnTasks.length}</span>
                </header>
                <div className="flex min-h-0 flex-1 flex-col gap-half overflow-y-auto p-half">
                  {columnTasks.length === 0 ? (
                    <p className="px-half py-base text-center text-xs text-low">
                      No tasks
                    </p>
                  ) : (
                    columnTasks.map((task) => {
                      const atStart =
                        task.status === 'todo' || busyTaskId === task.id;
                      const atEnd =
                        task.status === 'done' ||
                        task.status === 'cancelled' ||
                        busyTaskId === task.id;
                      return (
                        <article
                          key={task.id}
                          data-testid={`task-card-${task.id}`}
                          role="button"
                          tabIndex={0}
                          aria-label={task.title}
                          onClick={() => handleSelectTask(task.id)}
                          onKeyDown={(event) => {
                            if (event.key === 'Enter' || event.key === ' ') {
                              event.preventDefault();
                              handleSelectTask(task.id);
                            }
                          }}
                          className={cn(
                            'cursor-pointer rounded-sm border bg-primary p-half',
                            selectedTaskId === task.id
                              ? 'border-brand'
                              : 'border-border'
                          )}
                        >
                          {editingTaskId === task.id ? (
                            <div
                              className="flex flex-col gap-half"
                              onClick={(event) => event.stopPropagation()}
                            >
                              <input
                                aria-label="Edit task title"
                                autoFocus
                                value={editingTitle}
                                onChange={(e) =>
                                  setEditingTitle(e.target.value)
                                }
                                onKeyDown={(e) => {
                                  if (e.key === 'Enter')
                                    void handleSaveEdit(task);
                                  if (e.key === 'Escape')
                                    setEditingTaskId(null);
                                }}
                                className="w-full rounded-sm border border-border bg-secondary px-half py-half text-sm text-normal"
                              />
                              <textarea
                                aria-label="Edit task description"
                                value={editingDescription}
                                onChange={(e) =>
                                  setEditingDescription(e.target.value)
                                }
                                onKeyDown={(e) => {
                                  if (e.key === 'Escape')
                                    setEditingTaskId(null);
                                }}
                                onBlur={() => void handleSaveEdit(task)}
                                rows={3}
                                placeholder="Description (optional)"
                                className="w-full rounded-sm border border-border bg-secondary px-half py-half text-xs text-normal placeholder:text-low"
                              />
                            </div>
                          ) : (
                            <div
                              className="cursor-text"
                              onDoubleClick={() => startEditing(task)}
                              title="Double-click to edit"
                            >
                              <p className="text-sm text-normal">
                                {task.title}
                              </p>
                              {task.description ? (
                                <p className="mt-half line-clamp-3 text-xs text-low">
                                  {task.description}
                                </p>
                              ) : null}
                            </div>
                          )}
                          {(workspacesByTaskId.get(task.id) ?? []).length >
                          0 ? (
                            <div
                              className="mt-half flex flex-wrap items-center gap-half"
                              onClick={(event) => event.stopPropagation()}
                            >
                              {(workspacesByTaskId.get(task.id) ?? []).map(
                                (workspace) => (
                                  <button
                                    key={workspace.id}
                                    type="button"
                                    data-testid={`task-open-workspace-${workspace.id}`}
                                    aria-label={t('kanban.task.openWorkspace')}
                                    title={t('kanban.task.openWorkspace')}
                                    onClick={() =>
                                      appNavigation.goToWorkspace(workspace.id)
                                    }
                                    className="rounded-sm border border-border px-half text-xs text-low"
                                  >
                                    {workspace.name ??
                                      t('kanban.task.openWorkspace')}
                                  </button>
                                )
                              )}
                            </div>
                          ) : null}
                          <div
                            className="mt-half flex items-center justify-end gap-half"
                            onClick={(event) => event.stopPropagation()}
                          >
                            <button
                              type="button"
                              aria-label={`Move ${task.title} back`}
                              title={`Move back from ${STATUS_LABEL[task.status]}`}
                              disabled={atStart}
                              onClick={() => void handleMove(task, -1)}
                              className="rounded-sm px-half text-xs text-low disabled:opacity-30"
                            >
                              ‹
                            </button>
                            <button
                              type="button"
                              aria-label={`Move ${task.title} forward`}
                              title={`Move forward from ${STATUS_LABEL[task.status]}`}
                              disabled={atEnd}
                              onClick={() => void handleMove(task, 1)}
                              className="rounded-sm px-half text-xs text-low disabled:opacity-30"
                            >
                              ›
                            </button>
                            <button
                              type="button"
                              data-testid={`task-create-workspace-${task.id}`}
                              aria-label={t('kanban.task.createWorkspace')}
                              title={t('kanban.task.createWorkspace')}
                              disabled={busyTaskId === task.id}
                              onClick={() => void handleCreateWorkspace(task)}
                              className="rounded-sm px-half text-xs text-low disabled:opacity-30"
                            >
                              +
                            </button>
                            <button
                              type="button"
                              aria-label={`Delete ${task.title}`}
                              disabled={busyTaskId === task.id}
                              onClick={() => void handleDelete(task.id)}
                              className="rounded-sm px-half text-xs text-low disabled:opacity-30"
                            >
                              ×
                            </button>
                          </div>
                        </article>
                      );
                    })
                  )}
                </div>
              </section>
            );
          })}
        </div>
        {selectedTask ? (
          <TaskDetailPanel
            key={selectedTask.id}
            task={selectedTask}
            workspace={workspacesByTaskId.get(selectedTask.id)?.[0] ?? null}
            onOpenWorkspace={() => {
              const workspace = workspacesByTaskId.get(selectedTask.id)?.[0];
              if (workspace) {
                appNavigation.goToWorkspace(workspace.id);
              }
            }}
            onCreateWorkspace={() => void handleCreateWorkspace(selectedTask)}
            onClose={() => appNavigation.goToProject(projectId)}
            onUpdated={(updated) =>
              setTasks((previous) =>
                previous.map((task) =>
                  task.id === updated.id ? updated : task
                )
              )
            }
            onDeleted={(taskId) => {
              setTasks((previous) =>
                previous.filter((task) => task.id !== taskId)
              );
              appNavigation.goToProject(projectId);
            }}
          />
        ) : null}
      </div>
    </div>
  );
}
