import { useContext } from 'react';
import { createHmrContext } from '@/shared/lib/hmrContext';
import type { Workspace } from 'shared/types';
import type {
  ActionDefinition,
  ActionExecutorContext,
  ActionVisibilityContext,
  ProjectMutations,
} from '@/shared/types/actions';

export interface ActionsContextValue {
  // Execute an action with optional workspaceId and repoId/projectId
  // For git actions: repoIdOrProjectId is repoId
  // For issue actions: repoIdOrProjectId is projectId, issueIds are required
  executeAction: (
    action: ActionDefinition,
    workspaceId?: string,
    repoIdOrProjectId?: string,
    issueIds?: string[]
  ) => Promise<void>;

  // Get resolved label for an action (supports dynamic labels via visibility context)
  getLabel: (
    action: ActionDefinition,
    workspace?: Workspace,
    ctx?: ActionVisibilityContext
  ) => string;

  // Set default status for issue creation based on current kanban tab
  setDefaultCreateStatusId: (statusId: string | undefined) => void;

  // Register project mutations (called by components inside ProjectProvider)
  registerProjectMutations: (mutations: ProjectMutations | null) => void;

  // The executor context (for components that need direct access)
  executorContext: ActionExecutorContext;
}

export const ActionsContext = createHmrContext<ActionsContextValue | null>(
  'ActionsContext',
  null
);

export function useActions(): ActionsContextValue {
  const context = useContext(ActionsContext);
  if (!context) {
    throw new Error('useActions must be used within an ActionsProvider');
  }
  return context;
}
