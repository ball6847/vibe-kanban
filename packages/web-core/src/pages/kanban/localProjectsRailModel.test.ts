import { describe, expect, it } from 'vitest';
import type { Project } from 'shared/types';
import type { AppDestination } from '@/shared/lib/routes/appNavigation';
import {
  resolveActiveProjectId,
  toAppBarProjects,
} from './localProjectsRailModel';

function makeProject(id: string, name = id): Project {
  return {
    id,
    name,
    default_agent_working_dir: null,
    remote_project_id: null,
    created_at: new Date(0),
    updated_at: new Date(0),
  };
}

const HUES = new Set(['210', '160', '30', '280', '340', '100', '20', '250']);

describe('toAppBarProjects', () => {
  it('maps id and name and assigns a palette hue', () => {
    const result = toAppBarProjects([
      makeProject('p1', 'Alpha'),
      makeProject('p2', 'Beta'),
    ]);

    expect(result).toEqual([
      { id: 'p1', name: 'Alpha', color: expect.any(String) },
      { id: 'p2', name: 'Beta', color: expect.any(String) },
    ]);
    for (const project of result) {
      expect(HUES.has(project.color)).toBe(true);
    }
  });

  it('returns an empty list for no projects', () => {
    expect(toAppBarProjects([])).toEqual([]);
  });

  it('derives the colour deterministically from the id', () => {
    const first = toAppBarProjects([makeProject('stable-id')]);
    const second = toAppBarProjects([makeProject('stable-id')]);
    const other = toAppBarProjects([makeProject('stable-id')]);

    expect(first).toEqual(second);
    expect(other).toEqual(first);
    expect(first[0]?.color).toBe(second[0]?.color);
  });
});

describe('resolveActiveProjectId', () => {
  it('returns null without a destination', () => {
    expect(resolveActiveProjectId(null)).toBeNull();
  });

  const projectDestinations: AppDestination[] = [
    { kind: 'project', projectId: 'p1' },
    { kind: 'project-issue', projectId: 'p1', issueId: 'i1' },
    {
      kind: 'project-issue-workspace',
      projectId: 'p1',
      issueId: 'i1',
      workspaceId: 'w1',
    },
    {
      kind: 'project-issue-workspace-create',
      projectId: 'p1',
      issueId: 'i1',
      draftId: 'd1',
    },
    { kind: 'project-workspace-create', projectId: 'p1', draftId: 'd1' },
  ];

  it.each(projectDestinations.map((d) => [d.kind, d] as const))(
    'returns the project id for %s',
    (_kind, destination) => {
      expect(resolveActiveProjectId(destination)).toBe('p1');
    }
  );

  const otherDestinations: AppDestination[] = [
    { kind: 'root' },
    { kind: 'onboarding' },
    { kind: 'onboarding-sign-in' },
    { kind: 'workspaces' },
    { kind: 'workspaces-create' },
    { kind: 'workspace', workspaceId: 'w1' },
    { kind: 'workspace-vscode', workspaceId: 'w1' },
    { kind: 'export' },
    { kind: 'projects' },
  ];

  it.each(otherDestinations.map((d) => [d.kind, d] as const))(
    'returns null for %s',
    (_kind, destination) => {
      expect(resolveActiveProjectId(destination)).toBeNull();
    }
  );
});
