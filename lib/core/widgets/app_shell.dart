import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/app_constants.dart';

import '../../features/authentication/presentation/auth_controller.dart';
import '../providers/core_providers.dart';
import '../router/nav_destinations.dart';
import '../theme/design_tokens.dart';
import '../theme/theme_controller.dart';
import 'app_sidebar.dart';
import 'confirm_dialog.dart';

/// Whether the user has pinned the sidebar collapsed. Window width can also
/// collapse it, but this choice wins when the window is wide enough.
final sidebarCollapsedProvider = StateProvider<bool>((ref) => false);

/// The frame every signed-in screen renders inside: sidebar, top bar and the
/// page body.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      // The router redirects in this case; this is only reached for the frame
      // in between.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pinnedCollapsed = ref.watch(sidebarCollapsedProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isCollapsed =
        pinnedCollapsed || width < AppLayout.sidebarCollapseBreakpoint;
    final currentPath = GoRouterState.of(context).uri.path;

    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            user: user,
            currentPath: currentPath,
            isCollapsed: isCollapsed,
            onToggleCollapsed: () => ref
                .read(sidebarCollapsedProvider.notifier)
                .update((value) => !value),
            onNavigate: (path) {
              if (path != currentPath) context.go(path);
            },
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  showExpandButton: isCollapsed,
                  onExpand: () =>
                      ref.read(sidebarCollapsedProvider.notifier).state = false,
                  currentPath: currentPath,
                ),
                const Divider(height: 1),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.showExpandButton,
    required this.onExpand,
    required this.currentPath,
  });

  final bool showExpandButton;
  final VoidCallback onExpand;
  final String currentPath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destination = destinationForPath(currentPath);
    final themeMode = ref.watch(themeModeProvider);
    final businessName =
        ref
            .watch(settingsServiceProvider)
            .getStringSync(SettingKeys.businessName) ??
        AppConstants.companyName;

    return Container(
      height: AppLayout.topBarHeight,
      color: context.colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: [
          if (showExpandButton)
            IconButton(
              tooltip: 'Expand menu',
              icon: const Icon(Icons.menu, size: 20),
              onPressed: onExpand,
            ),
          if (showExpandButton) AppSpacing.hGapSm,
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination?.label ?? AppConstants.appName,
                  style: context.text.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  businessName,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const _TodayLabel(),
          AppSpacing.hGapMd,
          IconButton(
            tooltip: switch (themeMode) {
              ThemeMode.light => 'Light theme (click for dark)',
              ThemeMode.dark => 'Dark theme (click to follow Windows)',
              ThemeMode.system => 'Following Windows (click for light)',
            },
            icon: Icon(switch (themeMode) {
              ThemeMode.light => Icons.light_mode_outlined,
              ThemeMode.dark => Icons.dark_mode_outlined,
              ThemeMode.system => Icons.brightness_auto_outlined,
            }, size: 20),
            onPressed: () => ref.read(themeModeProvider.notifier).cycle(),
          ),
          AppSpacing.hGapSm,
          const _AccountButton(),
        ],
      ),
    );
  }
}

class _TodayLabel extends ConsumerWidget {
  const _TodayLabel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider).nowUtc().toLocal();
    return Text(
      DateFormat('EEE, d MMM yyyy').format(now),
      style: context.text.bodySmall,
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      onSelected: (value) async {
        switch (value) {
          case 'password':
            context.go(Routes.changePassword);
          case 'settings':
            context.go(Routes.settings);
          case 'signOut':
            final confirmed = await ConfirmDialog.show(
              context,
              title: 'Sign out?',
              message: 'You will need to sign in again to continue working.',
              confirmLabel: 'Sign out',
              icon: Icons.logout,
            );
            if (confirmed) {
              await ref.read(authControllerProvider.notifier).signOut();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.fullName, style: context.text.titleSmall),
              Text(
                '@${user.username} · ${user.roleCodes.join(', ')}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'password',
          child: ListTile(
            leading: Icon(Icons.key_outlined, size: 18),
            title: Text('Change password'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (user.can('settings.manage'))
          const PopupMenuItem(
            value: 'settings',
            child: ListTile(
              leading: Icon(Icons.settings_outlined, size: 18),
              title: Text('Settings'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'signOut',
          child: ListTile(
            leading: Icon(Icons.logout, size: 18),
            title: Text('Sign out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: context.colors.primaryContainer,
            child: Text(
              user.initials,
              style: context.text.labelMedium?.copyWith(
                color: context.colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          AppSpacing.hGapSm,
          Icon(
            Icons.expand_more,
            size: 18,
            color: context.colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
