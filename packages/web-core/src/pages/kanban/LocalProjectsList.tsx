import { useEffect, useRef, useState } from 'react';
import type { Project } from 'shared/types';
import { localProjectsApi } from '@/shared/lib/api';
import { useAppNavigation } from '@/shared/hooks/useAppNavigation';
import { usePageTitle } from '@/shared/hooks/usePageTitle';

export function LocalProjectsList() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [newProjectName, setNewProjectName] = useState('');
  const [isCreating, setIsCreating] = useState(false);
  const [busyProjectId, setBusyProjectId] = useState<string | null>(null);
  const [editingProjectId, setEditingProjectId] = useState<string | null>(null);
  const [editingName, setEditingName] = useState('');
  const openTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const appNavigation = useAppNavigation();

  usePageTitle('Projects');

  useEffect(() => {
    let cancelled = false;
    localProjectsApi
      .list()
      .then((result) => {
        if (cancelled) return;
        setProjects(result);
        setIsLoading(false);
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        setError(
          err instanceof Error ? err.message : 'Failed to load projects'
        );
        setIsLoading(false);
      });
    return () => {
      cancelled = true;
      if (openTimer.current) clearTimeout(openTimer.current);
    };
  }, []);

  const handleCreate = async () => {
    const name = newProjectName.trim();
    if (!name || isCreating) return;
    setIsCreating(true);
    try {
      const created = await localProjectsApi.create({ name });
      setProjects((prev) => [created, ...prev]);
      setNewProjectName('');
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to create project'
      );
    } finally {
      setIsCreating(false);
    }
  };

  const handleSaveEdit = async (project: Project) => {
    if (editingProjectId !== project.id) return;
    const name = editingName.trim();
    setEditingProjectId(null);
    if (!name || name === project.name || busyProjectId) return;
    setBusyProjectId(project.id);
    try {
      const updated = await localProjectsApi.update(project.id, { name });
      setProjects((prev) =>
        prev.map((p) => (p.id === project.id ? updated : p))
      );
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to save project'
      );
    } finally {
      setBusyProjectId(null);
    }
  };

  const handleDelete = async (projectId: string) => {
    if (busyProjectId) return;
    setBusyProjectId(projectId);
    try {
      await localProjectsApi.remove(projectId);
      setProjects((prev) => prev.filter((p) => p.id !== projectId));
      setActionError(null);
    } catch (err: unknown) {
      setActionError(
        err instanceof Error ? err.message : 'Failed to delete project'
      );
    } finally {
      setBusyProjectId(null);
    }
  };

  if (isLoading) {
    return (
      <div className="flex h-full w-full items-center justify-center">
        <p className="text-low">Loading projects…</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-full w-full items-center justify-center p-base">
        <p className="text-low">Could not load projects: {error}</p>
      </div>
    );
  }

  return (
    <div className="h-full w-full overflow-y-auto bg-primary p-base">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-base">
        {actionError ? (
          <div className="flex shrink-0 items-center justify-between gap-half">
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
        <div className="flex shrink-0 gap-half">
          <input
            aria-label="New project name"
            value={newProjectName}
            onChange={(e) => setNewProjectName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') void handleCreate();
            }}
            placeholder="New project…"
            className="min-w-0 flex-1 rounded-sm border border-border bg-secondary px-half py-half text-sm text-normal placeholder:text-low"
          />
          <button
            type="button"
            onClick={() => void handleCreate()}
            disabled={!newProjectName.trim() || isCreating}
            className="shrink-0 rounded-sm bg-brand px-base py-half text-sm font-medium text-on-brand disabled:opacity-50"
          >
            Add
          </button>
        </div>
        {projects.length === 0 ? (
          <p className="py-base text-center text-sm text-low">
            No projects yet
          </p>
        ) : (
          <ul className="flex w-full flex-col gap-half">
            {projects.map((project) => (
              <li key={project.id} className="flex gap-half">
                {editingProjectId === project.id ? (
                  <input
                    aria-label="Edit project name"
                    autoFocus
                    value={editingName}
                    onChange={(e) => setEditingName(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') void handleSaveEdit(project);
                      if (e.key === 'Escape') setEditingProjectId(null);
                    }}
                    onBlur={() => void handleSaveEdit(project)}
                    className="min-w-0 flex-1 rounded-sm border border-border bg-secondary px-base py-half text-sm text-normal"
                  />
                ) : (
                  <button
                    type="button"
                    onClick={() => {
                      if (openTimer.current) clearTimeout(openTimer.current);
                      openTimer.current = setTimeout(() => {
                        appNavigation.goToProject(project.id);
                      }, 250);
                    }}
                    onDoubleClick={(e) => {
                      e.preventDefault();
                      if (openTimer.current) clearTimeout(openTimer.current);
                      setEditingProjectId(project.id);
                      setEditingName(project.name);
                    }}
                    title="Open (double-click to rename)"
                    className="min-w-0 flex-1 rounded-sm border border-border bg-secondary px-base py-half text-left transition-colors hover:bg-tertiary"
                  >
                    <span className="text-sm font-medium text-high">
                      {project.name}
                    </span>
                  </button>
                )}
                <button
                  type="button"
                  aria-label={`Delete ${project.name}`}
                  disabled={busyProjectId === project.id}
                  onClick={() => void handleDelete(project.id)}
                  className="shrink-0 rounded-sm border border-border bg-secondary px-base text-sm text-low disabled:opacity-30"
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
