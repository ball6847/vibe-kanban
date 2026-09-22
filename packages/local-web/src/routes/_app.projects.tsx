import { createFileRoute } from '@tanstack/react-router';
import { LocalProjectsList } from '@/pages/kanban/LocalProjectsList';

export const Route = createFileRoute('/_app/projects')({
  component: LocalProjectsList,
});
