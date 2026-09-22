import { LocalKanbanBoard } from '@/pages/kanban/LocalKanbanBoard';
import { useCurrentKanbanRouteState } from '@/shared/hooks/useCurrentKanbanRouteState';

export function LocalProjectKanban() {
  const { projectId } = useCurrentKanbanRouteState();

  if (!projectId) {
    return (
      <div className="flex h-full w-full items-center justify-center">
        <p className="text-low">No project selected</p>
      </div>
    );
  }

  return <LocalKanbanBoard projectId={projectId} />;
}
