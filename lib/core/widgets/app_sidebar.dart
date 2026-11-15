import 'package:flutter/material.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import '../router/nav_destinations.dart';
import '../theme/design_tokens.dart';
import 'company_logo.dart';

/// The application's primary navigation.
///
/// Collapses to an icon rail on narrow windows or when the user pins it
/// collapsed. Items the signed-in user has no permission for are not rendered
/// at all, and items from a later development phase are marked so nobody
/// mistakes a planned screen for a broken one.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.user,
    required this.currentPath,
    required this.isCollapsed,
    required this.onToggleCollapsed,
    required this.onNavigate,
  });

  final AuthenticatedUser user;
  final String currentPath;
  final bool isCollapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String> onNavigate;

  @override
  Widget build(BuildContext context) {
    final width = isCollapsed
        ? AppLayout.sidebarCollapsedWidth
        : AppLayout.sidebarExpandedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(right: BorderSide(color: context.colors.outlineVariant)),
      ),
      child: Column(
        children: [
          _Brand(isCollapsed: isCollapsed, onToggle: onToggleCollapsed),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                for (final section in kNavSections)
                  ..._buildSection(context, section),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSection(BuildContext context, NavSection section) {
    final visible = section.destinations
        .where((d) => d.isVisibleTo(user))
        .toList();
    if (visible.isEmpty) return const [];

    return [
      if (!isCollapsed)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: Text(
            section.title.toUpperCase(),
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        )
      else
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Divider(height: 1),
        ),
      for (final destination in visible)
        _SidebarItem(
          destination: destination,
          isSelected: destination.path == currentPath,
          isCollapsed: isCollapsed,
          onTap: () => onNavigate(destination.path),
        ),
    ];
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.isCollapsed, required this.onToggle});

  final bool isCollapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final mark = Container(
      height: 32,
      width: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: AppRadii.smAll,
      ),
      child: Text(
        'V',
        style: context.text.titleMedium?.copyWith(
          color: context.colors.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
    return SizedBox(
      height: AppLayout.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            if (isCollapsed) mark,
            if (!isCollapsed) ...[
              // The uploaded company logo when there is one.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: CompanyLogo(
                    height: 30,
                    maxWidth: 160,
                    fallback: Row(
                      children: [
                        mark,
                        AppSpacing.hGapSm,
                        Flexible(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppConstants.appName,
                                style: context.text.titleSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Wholesale',
                                style: context.text.labelSmall?.copyWith(
                                  color: context.colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Collapse menu',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: onToggle,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
  });

  final NavDestination destination;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPlanned = destination.availableFromPhase > kImplementedThroughPhase;
    final foreground = isSelected
        ? context.colors.onSecondaryContainer
        : context.colors.onSurfaceVariant;

    final tile = Container(
      height: 38,
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: isSelected ? context.colors.secondaryContainer : null,
        borderRadius: AppRadii.smAll,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadii.smAll,
        child: InkWell(
          borderRadius: AppRadii.smAll,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 0 : AppSpacing.md,
            ),
            child: Row(
              mainAxisAlignment: isCollapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  isSelected ? destination.selectedIcon : destination.icon,
                  size: 19,
                  color: foreground,
                ),
                if (!isCollapsed) ...[
                  AppSpacing.hGapMd,
                  Expanded(
                    child: Text(
                      destination.label,
                      style: context.text.bodyMedium?.copyWith(
                        color: isSelected
                            ? foreground
                            : context.colors.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isPlanned)
                    Tooltip(
                      message:
                          'Planned for phase ${destination.availableFromPhase}',
                      child: Icon(
                        Icons.schedule,
                        size: 14,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!isCollapsed) return tile;
    return Tooltip(
      message: isPlanned
          ? '${destination.label} (phase ${destination.availableFromPhase})'
          : destination.label,
      child: tile,
    );
  }
}
