import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from 'react';
import { useTranslation } from 'react-i18next';
import { useAppRuntime } from '@/shared/hooks/useAppRuntime';
import { useHostId } from '@/shared/providers/HostIdProvider';
import {
  createMachineClient,
  type MachineClient,
  type MachineTarget,
} from '@/shared/lib/machineClient';

export type SettingsHostTargetId = 'local' | string;

export type SettingsHostTarget = MachineTarget & {
  description?: string;
  status?: 'online' | 'offline';
};

interface SettingsHostContextValue {
  availableHosts: SettingsHostTarget[];
  hostsResolved: boolean;
  selectedHostId: SettingsHostTargetId | null;
  selectedHost: SettingsHostTarget | null;
  setSelectedHostId: (hostId: SettingsHostTargetId) => void;
}

const SettingsHostContext = createContext<SettingsHostContextValue | null>(
  null
);

function toLocalRuntimeTargets(
  getLabel: (key: string, defaultValue: string) => string
): SettingsHostTarget[] {
  return [
    {
      id: 'local',
      apiHostId: null,
      label: getLabel('settings.hostPicker.thisMachine', 'This machine'),
      description: getLabel('settings.hostPicker.localHost', 'Local host'),
      kind: 'local',
    },
  ];
}

function getInitialHostId(
  hosts: SettingsHostTarget[],
  routeHostId: string | null,
  initialHostId?: SettingsHostTargetId
): SettingsHostTargetId | null {
  if (initialHostId && hosts.some((host) => host.id === initialHostId)) {
    return initialHostId;
  }

  if (routeHostId && hosts.some((host) => host.id === routeHostId)) {
    return routeHostId;
  }

  return hosts[0]?.id ?? null;
}

export function SettingsHostProvider({
  initialHostId,
  children,
}: {
  initialHostId?: SettingsHostTargetId;
  children: ReactNode;
}) {
  const { t } = useTranslation('settings');
  const runtime = useAppRuntime();
  const routeHostId = useHostId();

  const availableHosts = useMemo<SettingsHostTarget[]>(
    () => toLocalRuntimeTargets(t),
    [runtime, t]
  );
  const hostsResolved = true;

  const [selectedHostId, setSelectedHostId] =
    useState<SettingsHostTargetId | null>(null);

  useEffect(() => {
    const nextHostId = getInitialHostId(
      availableHosts,
      routeHostId,
      initialHostId
    );

    setSelectedHostId((current) => {
      if (current && availableHosts.some((host) => host.id === current)) {
        return current;
      }
      return nextHostId;
    });
  }, [availableHosts, initialHostId, routeHostId]);

  const selectedHost = useMemo(
    () => availableHosts.find((host) => host.id === selectedHostId) ?? null,
    [availableHosts, selectedHostId]
  );

  const value = useMemo<SettingsHostContextValue>(
    () => ({
      availableHosts,
      hostsResolved,
      selectedHostId,
      selectedHost,
      setSelectedHostId,
    }),
    [availableHosts, hostsResolved, selectedHost, selectedHostId]
  );

  return (
    <SettingsHostContext.Provider value={value}>
      {children}
    </SettingsHostContext.Provider>
  );
}

export function useSettingsHost() {
  const context = useContext(SettingsHostContext);
  if (!context) {
    throw new Error(
      'useSettingsHost must be used within a SettingsHostProvider'
    );
  }
  return context;
}

export function useSettingsMachineClient(): MachineClient | null {
  const runtime = useAppRuntime();
  const { selectedHost } = useSettingsHost();

  return useMemo(() => {
    if (!selectedHost) {
      return null;
    }

    return createMachineClient(runtime, selectedHost);
  }, [runtime, selectedHost]);
}
