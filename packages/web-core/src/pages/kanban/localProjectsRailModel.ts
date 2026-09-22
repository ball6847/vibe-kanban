import type { AppBarProject } from '@vibe/ui/components/AppBar';
import type { Project } from 'shared/types';
import type { AppDestination } from '@/shared/lib/routes/appNavigation';

/**
 * Colours handed out to rail project tiles. `AppBar` renders the value inside
 * `hsl(${color})` and `hsl(${color} / 0.2)`, so each entry must be a full
 * `H S% L%` triple — a bare hue makes the second template invalid and the
 * active highlight renders transparent. Local projects carry no colour of
 * their own, so one is derived deterministically from the id.
 */
const PROJECT_COLORS = [
  '210 70% 55%',
  '160 65% 45%',
  '30 80% 55%',
  '280 60% 60%',
  '340 70% 58%',
  '100 50% 45%',
  '20 75% 55%',
  '250 65% 60%',
] as const;

const FALLBACK_COLOR = '210 70% 55%';

function colorForProjectId(projectId: string): string {
  let hash = 0;
  for (let index = 0; index < projectId.length; index += 1) {
    hash = (hash * 31 + projectId.charCodeAt(index)) % 1000003;
  }
  return PROJECT_COLORS[hash % PROJECT_COLORS.length] ?? FALLBACK_COLOR;
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
