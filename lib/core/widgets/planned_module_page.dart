import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import 'page_scaffold.dart';
import 'section_card.dart';

/// Shown for a navigation item whose module is scheduled for a later phase.
///
/// Deliberately honest: it states that the screen is not built yet and lists
/// what it will do, rather than presenting buttons and empty tables that look
/// functional. Nothing here reads or writes business data.
class PlannedModulePage extends StatelessWidget {
  const PlannedModulePage({
    super.key,
    required this.title,
    required this.phase,
    required this.summary,
    this.capabilities = const [],
  });

  final String title;
  final int phase;
  final String summary;
  final List<String> capabilities;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: title,
      description: summary,
      maxContentWidth: 820,
      child: SectionCard(
        title: 'Scheduled for phase $phase',
        subtitle: 'This screen is not built yet. Nothing on it is functional.',
        leading: Icon(
          Icons.schedule_outlined,
          color: context.statusColors.warning,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'The database schema and business rules this module needs are '
              'already in place, so building it does not require schema '
              'changes.',
              style: context.text.bodyMedium,
            ),
            if (capabilities.isNotEmpty) ...[
              AppSpacing.gapLg,
              Text('Planned capabilities', style: context.text.titleSmall),
              AppSpacing.gapSm,
              for (final capability in capabilities)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Icon(
                          Icons.circle,
                          size: 5,
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                      AppSpacing.hGapSm,
                      Expanded(
                        child: Text(capability, style: context.text.bodyMedium),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
