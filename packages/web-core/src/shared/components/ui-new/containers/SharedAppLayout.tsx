import { useCallback, useEffect, useRef, useState } from 'react';
import { Outlet, useNavigate, useParams } from '@tanstack/react-router';
import { siDiscord, siGithub } from 'simple-icons';
import {
  XIcon,
  LayoutIcon,
  DownloadSimpleIcon,
} from '@phosphor-icons/react';
import { useIsMobile } from '@/shared/hooks/useIsMobile';
import { useUiPreferencesStore } from '@/shared/stores/useUiPreferencesStore';
import { cn } from '@/shared/lib/utils';
import { isTauriMac } from '@/shared/lib/platform';

import { AppBar, type AppBarHostStatus } from '@vibe/ui/components/AppBar';
import { MobileDrawer } from '@vibe/ui/components/MobileDrawer';
import { AppBarUserPopoverContainer } from './AppBarUserPopoverContainer';
import { useOrganizationStore } from '@/shared/stores/useOrganizationStore';
import { useAuth } from '@/shared/hooks/auth/useAuth';
import { useDiscordOnlineCount } from '@/shared/hooks/useDiscordOnlineCount';
import { useGitHubStars } from '@/shared/hooks/useGitHubStars';
import { useUserSystem } from '@/shared/hooks/useUserSystem';
import { useAppUpdateStore } from '@/shared/stores/useAppUpdateStore';
import { useAppNavigation } from '@/shared/hooks/useAppNavigation';
import { useCurrentAppDestination } from '@/shared/hooks/useCurrentAppDestination';
import {
  getDestinationHostId,
  isLocalWorkspacesDestination,
} from '@/shared/lib/routes/appNavigation';
import { OAuthDialog } from '@/shared/dialogs/global/OAuthDialog';
import { SettingsDialog } from '@/shared/dialogs/settings/SettingsDialog';
import { CommandBarDialog } from '@/shared/dialogs/command-bar/CommandBarDialog';
import { useCommandBarShortcut } from '@/shared/hooks/useCommandBarShortcut';
import { useWorkspaceSidebarPreviewController } from '@/shared/hooks/useWorkspaceSidebarPreviewController';
import { WorkspacesSidebarContainer } from '@/pages/workspaces/WorkspacesSidebarContainer';
import { WorkspacesSidebarReopenTag } from '@vibe/ui/components/WorkspacesSidebar';
import { CloudShutdownExportBanner } from '@/shared/components/CloudShutdownExportBanner';

export function SharedAppLayout() {
  const appNavigation = useAppNavigation();
  const currentDestination = useCurrentAppDestination();
  const isMobile = useIsMobile();
  const mobileFontScale = useUiPreferencesStore((s) => s.mobileFontScale);
  const isLeftSidebarVisible = useUiPreferencesStore(
    (s) => s.isLeftSidebarVisible
  );
  const { isSignedIn } = useAuth();
  const { appVersion } = useUserSystem();
  const updateVersion = useAppUpdateStore((s) => s.updateVersion);
  const restartForUpdate = useAppUpdateStore((s) => s.restart);
  const { data: onlineCount } = useDiscordOnlineCount();
  const { data: starCount } = useGitHubStars();
  const [isDrawerOpen, setIsDrawerOpen] = useState(false);
  const [isAppBarHovered, setIsAppBarHovered] = useState(false);
  const { hostId: routeHostId } = useParams({ strict: false });
  const navigate = useNavigate();

  // Register CMD+K shortcut globally for all routes under SharedAppLayout
  useCommandBarShortcut(() => CommandBarDialog.show());

  // Apply mobile font scale CSS variable
  useEffect(() => {
    if (!isMobile) {
      document.documentElement.style.removeProperty('--mobile-font-scale');
      return;
    }
    const scaleMap = { default: '1', small: '0.9', smaller: '0.8' } as const;
    document.documentElement.style.setProperty(
      '--mobile-font-scale',
      scaleMap[mobileFontScale]
    );
    return () => {
      document.documentElement.style.removeProperty('--mobile-font-scale');
    };
  }, [isMobile, mobileFontScale]);

  // AppBar state
  const organizations: never[] = [];

  const selectedOrgId = useOrganizationStore((s) => s.selectedOrgId);
  const setSelectedOrgId = useOrganizationStore((s) => s.setSelectedOrgId);
  const prevOrgIdRef = useRef<string | null>(null);

  // Navigate to the first ordered project when org changes
  useEffect(() => {
    if (
      prevOrgIdRef.current !== null &&
      prevOrgIdRef.current !== selectedOrgId &&
      selectedOrgId
    ) {
      appNavigation.goToWorkspaces();
      prevOrgIdRef.current = selectedOrgId;
    } else if (prevOrgIdRef.current === null && selectedOrgId) {
      prevOrgIdRef.current = selectedOrgId;
    }
  }, [selectedOrgId, appNavigation]);

  // Navigation state for AppBar active indicators
  const isWorkspacesActive = isLocalWorkspacesDestination(currentDestination);
  const isExportActive = currentDestination?.kind === 'export';
  const showCloudShutdownBanner = isExportActive;
  const isWorkspaceSidebarPreviewEnabled =
    !isMobile && isWorkspacesActive && !isLeftSidebarVisible;
  const activeProjectId = null;
  const activeHostId =
    getDestinationHostId(currentDestination) ?? routeHostId ?? null;
  const sidebarPreview = useWorkspaceSidebarPreviewController({
    enabled: isWorkspaceSidebarPreviewEnabled,
    isAppBarHovered,
  });

  // Persist last selected project to scratch store
  const setSelectedProjectId = useUiPreferencesStore(
    (s) => s.setSelectedProjectId
  );
  useEffect(() => {
    if (activeProjectId) {
      setSelectedProjectId(activeProjectId);
    }
  }, [activeProjectId, setSelectedProjectId]);

  const handleWorkspacesClick = useCallback(() => {
    void navigate({ to: '/workspaces' });
  }, [navigate]);

  const handleExportClick = useCallback(() => {
    appNavigation.goToExport();
  }, [appNavigation]);

  const handleSignIn = useCallback(async () => {
    try {
      await OAuthDialog.show({});
    } catch {
      // Dialog cancelled
    }
  }, []);

  const openRelaySettings = useCallback((hostId?: string) => {
    void SettingsDialog.show({
      initialSection: 'relay',
      ...(hostId ? { initialState: { hostId } } : {}),
    });
  }, []);

  const handleHostClick = useCallback(
    (hostId: string, status: AppBarHostStatus) => {
      if (status === 'offline') {
        return;
      }

      void navigate({
        to: '/hosts/$hostId/workspaces',
        params: { hostId },
      });
    },
    [navigate]
  );

  const handlePairHostClick = useCallback(() => {
    openRelaySettings();
  }, [openRelaySettings]);

  return (
      <div
        className={cn(
          'bg-primary',
          isMobile
            ? 'flex fixed inset-0 pb-[env(safe-area-inset-bottom)]'
            : cn(
                'grid grid-cols-[auto_1fr] h-screen',
                showCloudShutdownBanner
                  ? 'grid-rows-[auto_auto_1fr]'
                  : 'grid-rows-[auto_1fr]'
              )
        )}
      >
        {!isMobile && (
          <>
            {showCloudShutdownBanner && (
              <div className="col-span-2">
                <CloudShutdownExportBanner onClick={handleExportClick} />
              </div>
            )}
            {/* Desktop corner spacer. */}
            <div
              data-tauri-drag-region
              className="bg-secondary"
              style={isTauriMac() ? { minWidth: 56 } : undefined}
            />
            {/* Desktop AppBar sidebar. */}
            <AppBar
              projects={[]}
              activeHostId={activeHostId}
              onExportClick={handleExportClick}
              onWorkspacesClick={handleWorkspacesClick}
              onHostClick={handleHostClick}
              onPairHostClick={handlePairHostClick}
              isWorkspacesActive={isWorkspacesActive}
              isExportActive={isExportActive}
              activeProjectId={activeProjectId}
              isSignedIn={isSignedIn}
              onSignIn={handleSignIn}
              onHoverStart={() => setIsAppBarHovered(true)}
              onHoverEnd={() => setIsAppBarHovered(false)}
              userPopover={
                <AppBarUserPopoverContainer
                  organizations={organizations}
                  selectedOrgId={selectedOrgId ?? ''}
                  onOrgSelect={setSelectedOrgId}
                />
              }
              starCount={starCount}
              onlineCount={onlineCount}
              appVersion={appVersion}
              updateVersion={updateVersion}
              onUpdateClick={restartForUpdate ?? undefined}
              githubIconPath={siGithub.path}
              discordIconPath={siDiscord.path}
            />
            {/* Desktop content. */}
            <div className="relative min-h-0 overflow-hidden">
              {isWorkspaceSidebarPreviewEnabled && (
                <div className="absolute inset-y-0 left-0 z-20 flex items-center">
                  <WorkspacesSidebarReopenTag
                    active={sidebarPreview.isPreviewOpen}
                    onHoverStart={sidebarPreview.handleHandleHoverStart}
                    onHoverEnd={sidebarPreview.handleHandleHoverEnd}
                    ariaLabel="Workspaces"
                  />
                </div>
              )}

              {isWorkspaceSidebarPreviewEnabled && (
                <div
                  className={cn(
                    'absolute left-0 top-0 z-30 h-full w-[300px] transition-transform duration-150 ease-out',
                    sidebarPreview.isPreviewOpen
                      ? 'translate-x-0 pointer-events-auto'
                      : '-translate-x-full pointer-events-none'
                  )}
                  onMouseEnter={sidebarPreview.handlePreviewHoverStart}
                  onMouseLeave={sidebarPreview.handlePreviewHoverEnd}
                >
                  <div className="h-full w-full overflow-hidden border-r border-border bg-secondary shadow-lg">
                    <WorkspacesSidebarContainer />
                  </div>
                </div>
              )}

              <Outlet />
            </div>
          </>
        )}

        {isMobile && (
          <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
            {showCloudShutdownBanner && (
              <CloudShutdownExportBanner onClick={handleExportClick} />
            )}
            <div className="flex-1 min-h-0 overflow-hidden">
              <Outlet />
            </div>
          </div>
        )}

        {/* Mobile project navigation drawer */}
        <MobileDrawer
          open={isDrawerOpen && isMobile}
          onClose={() => setIsDrawerOpen(false)}
        >
          <div className="flex flex-col h-full">
            {/* Header: org name + close button */}
            <div className="flex items-center justify-between p-4 border-b border-border">
              <span className="text-sm font-medium text-high truncate">
                Organization
              </span>
              <button
                type="button"
                onClick={() => setIsDrawerOpen(false)}
                className="p-1 rounded-sm text-low hover:text-normal cursor-pointer"
              >
                <XIcon className="h-4 w-4" weight="bold" />
              </button>
            </div>

            {/* Workspaces link */}
            <button
              type="button"
              onClick={() => {
                void navigate({ to: '/workspaces' });
                setIsDrawerOpen(false);
              }}
              className="flex items-center gap-2 px-4 py-3 text-sm text-normal hover:bg-secondary cursor-pointer"
            >
              <LayoutIcon className="h-4 w-4" />
              Workspaces
            </button>

            {/* Divider */}
            <div className="border-t border-border mx-4" />

            {/* Export link */}
            {isSignedIn && (
              <div className="px-4 py-3">
                <p className="mb-2 text-xs font-medium text-low">Export</p>
                <button
                  type="button"
                  onClick={() => {
                    handleExportClick();
                    setIsDrawerOpen(false);
                  }}
                  className="flex w-full items-center gap-2 rounded-md px-3 py-2.5 text-sm text-normal hover:bg-secondary cursor-pointer"
                >
                  <DownloadSimpleIcon className="h-4 w-4" />
                  Export data
                </button>
              </div>
            )}

            {/* Divider */}
            {isSignedIn && <div className="border-t border-border mx-4" />}


          </div>
        </MobileDrawer>
      </div>
  );
}
