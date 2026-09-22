import type { AppBarProject } from '@vibe/ui/components/AppBar';
import type { Project } from 'shared/types';
import type { AppDestination } from '@/shared/lib/routes/appNavigation';

/**
 * Hues handed out to rail project tiles. `AppBar` renders the value as
 * `hsl(${color})`, so these are hue strings, not hex colours. Local projects
 * carry no colour of their own, so one is derived deterministically from the id.
 */
const PROJECT_COLOR_HUES = [
  '210',
  '160',
  '30',
  '280',
  '340',
  '100',
  '20',
  '250',
] as const;

const FALLBACK_HUE = '210';

function colorForProjectId(projectId: string): string {
  let hash = 0;
  for (let index = 0; index < projectId.length; index += 1) {
    hash = (hash * 31 + projectId.charCodeAt(index)) % 1000003;
  }
  return PROJECT_COLOR_HUES[hash % PROJECT_COLOR_HUES.length] ?? FALLBACK_HUE;
}

/** Maps local projects (REST shape) onto the rail's project tile shape. */
export function toAppBarProjects(projects: Project[]): AppBarProject[] {
  return projects.map((project) => ({
    id: project.id,
    name: project.name,
    color: colorForProjectId(project.id),
  }));
}

/**
 * Project id for the destination currently rendered, or null when the route is
 * not inside a project (including the projects index, which has no project id).
 */
export function resolveActiveProjectId(
  destination: AppDestination | null
): string | null {
  if (!destination) {
    return null;
  }

  switch (destination.kind) {
    case 'project':
    case 'project-issue':
    case 'project-issue-workspace':
    case 'project-issue-workspace-create':
    case 'project-workspace-create':
      return destination.projectId;
    default:
      return null;
  }
}
