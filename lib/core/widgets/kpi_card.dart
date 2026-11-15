import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/design_tokens.dart';
import 'status_pill.dart';

/// A single dashboard figure: label, value, and optional supporting line.
///
/// The value uses tabular figures so a row of cards lines up, and the whole
/// card is tappable when [onTap] is given so a KPI can lead to the report
/// behind it.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone = StatusTone.neutral,
    this.onTap,
    this.isLoading = false,
    this.trailing,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;
  final StatusTone tone;
  final VoidCallback? onTap;
  final bool isLoading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final accent = switch (tone) {
      StatusTone.success => colors.success,
      StatusTone.warning => colors.warning,
      StatusTone.danger => colors.danger,
      StatusTone.info => colors.info,
      StatusTone.neutral => context.colors.primary,
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: AppRadii.smAll,
                      ),
                      child: Icon(icon, size: 18, color: accent),
                    ),
                    AppSpacing.hGapMd,
                  ],
                  Expanded(
                    child: Text(
                      label,
                      style: context.text.labelMedium?.copyWith(
                        color: context.colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: SizedBox(
                    height: 20,
                    width: 80,
                    child: LinearProgressIndicator(),
                  ),
                )
              else
                Text(
                  value,
                  style: AppTheme.monospacedNumbers(
                    context.text.headlineSmall,
                  ).copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (caption != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  caption!,
                  style: context.text.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Lays KPI cards out in a responsive grid that keeps a readable card width
/// instead of stretching to the window.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children, this.minCardWidth = 240});

  final List<Widget> children;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / minCardWidth).floor().clamp(
          1,
          6,
        );
        const spacing = AppSpacing.lg;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: cardWidth, child: child),
          ],
        );
      },
    );
  }
}
