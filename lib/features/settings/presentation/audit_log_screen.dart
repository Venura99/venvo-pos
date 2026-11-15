import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:venvo_core/core/api/audit_api.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';

/// Filter applied to the audit log query.
class AuditLogFilter {
  const AuditLogFilter({this.action, this.search = '', this.limit = 200});

  final AuditAction? action;
  final String search;
  final int limit;

  AuditLogFilter copyWith({
    AuditAction? action,
    bool clearAction = false,
    String? search,
    int? limit,
  }) {
    return AuditLogFilter(
      action: clearAction ? null : (action ?? this.action),
      search: search ?? this.search,
      limit: limit ?? this.limit,
    );
  }
}

final auditLogFilterProvider = StateProvider<AuditLogFilter>(
  (ref) => const AuditLogFilter(),
);

/// Reads the audit trail newest first, from the server.
///
/// There is only a read. The trail is written by the server as a side effect
/// of the operations it records, and no client can add to it or change it.
final auditLogProvider = FutureProvider<List<AuditLog>>((ref) {
  final filter = ref.watch(auditLogFilterProvider);
  return AuditApi(
    ref.watch(apiClientProvider),
  ).entries(action: filter.action, search: filter.search, limit: filter.limit);
});

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.auditView) ?? false)) {
      return const PageScaffold(
        title: 'Audit Log',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to the audit log',
        ),
      );
    }

    final entries = ref.watch(auditLogProvider);
    final filter = ref.watch(auditLogFilterProvider);

    return PageScaffold(
      title: 'Audit Log',
      description:
          'Every sign-in, posting, cancellation and permission override. '
          'Entries are written as part of the operation itself and can never '
          'be edited or deleted.',
      scrollable: false,
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(auditLogProvider),
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Refresh'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(filter: filter),
          AppSpacing.gapLg,
          Expanded(
            child: AsyncValueView<List<AuditLog>>(
              value: entries,
              onRetry: () => ref.invalidate(auditLogProvider),
              builder: (context, data) {
                if (data.isEmpty) {
                  return const SectionCard(
                    child: EmptyState(
                      icon: Icons.history_outlined,
                      title: 'No matching entries',
                      message:
                          'Nothing in the audit log matches the current filter.',
                    ),
                  );
                }
                return SectionCard(
                  title: data.length >= filter.limit
                      ? 'Latest ${data.length} entries'
                      : '${data.length} entries',
                  padding: EdgeInsets.zero,
                  fillHeight: true,
                  child: _AuditTable(entries: data),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Filters extends ConsumerWidget {
  const _Filters({required this.filter});

  final AuditLogFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A Wrap, like every other filter bar: a Row overflows rather than
    // reflowing once the window is narrow or the labels are long.
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search summary or username',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: (value) => ref
                .read(auditLogFilterProvider.notifier)
                .update((state) => state.copyWith(search: value)),
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<AuditAction?>(
            initialValue: filter.action,
            // Without this the field sizes itself to its widest menu item,
            // which is wider than the box it is given.
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Action'),
            items: [
              const DropdownMenuItem<AuditAction?>(child: Text('All actions')),
              for (final action in AuditAction.values)
                DropdownMenuItem<AuditAction?>(
                  value: action,
                  child: Text(_labelForAction(action)),
                ),
            ],
            onChanged: (value) => ref
                .read(auditLogFilterProvider.notifier)
                .update(
                  (state) => value == null
                      ? state.copyWith(clearAction: true)
                      : state.copyWith(action: value),
                ),
          ),
        ),
        Text(
          'Showing the most recent ${filter.limit}',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}

class _AuditTable extends StatelessWidget {
  const _AuditTable({required this.entries});

  final List<AuditLog> entries;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final hasDetail = entry.beforeJson != null || entry.afterJson != null;

        return ListTile(
          dense: true,
          leading: StatusPill(
            _labelForAction(entry.action),
            tone: _toneForAction(entry.action),
          ),
          title: Text(entry.summary, style: context.text.bodyMedium),
          subtitle: Text(
            '${DateFormat('d MMM yyyy, HH:mm:ss').format(entry.occurredAt.toLocal())}'
            '${entry.username == null ? '' : '  ·  @${entry.username}'}'
            '${entry.entityKind == null ? '' : '  ·  ${entry.entityKind!.name}'
                      '${entry.entityId == null ? '' : ' #${entry.entityId}'}'}',
            style: context.text.bodySmall,
          ),
          trailing: hasDetail
              ? IconButton(
                  tooltip: 'What changed',
                  icon: const Icon(Icons.data_object, size: 18),
                  onPressed: () => _showDetail(context, entry),
                )
              : null,
        );
      },
    );
  }

  void _showDetail(BuildContext context, AuditLog entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recorded change'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(entry.summary, style: context.text.titleSmall),
                AppSpacing.gapLg,
                if (entry.beforeJson != null) ...[
                  Text('Before', style: context.text.labelMedium),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    entry.beforeJson!,
                    style: context.text.bodySmall,
                  ),
                  AppSpacing.gapLg,
                ],
                if (entry.afterJson != null) ...[
                  Text('After', style: context.text.labelMedium),
                  const SizedBox(height: AppSpacing.xs),
                  SelectableText(
                    entry.afterJson!,
                    style: context.text.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

String _labelForAction(AuditAction action) => switch (action) {
  AuditAction.create => 'Created',
  AuditAction.update => 'Updated',
  AuditAction.archive => 'Archived',
  AuditAction.post => 'Posted',
  AuditAction.cancel => 'Cancelled',
  AuditAction.reverse => 'Reversed',
  AuditAction.login => 'Signed in',
  AuditAction.loginFailed => 'Sign-in failed',
  AuditAction.logout => 'Signed out',
  AuditAction.permissionOverride => 'Override',
  AuditAction.backup => 'Backup',
  AuditAction.restore => 'Restore',
  AuditAction.export => 'Export',
};

StatusTone _toneForAction(AuditAction action) => switch (action) {
  AuditAction.create ||
  AuditAction.post ||
  AuditAction.login => StatusTone.success,
  AuditAction.cancel ||
  AuditAction.reverse ||
  AuditAction.loginFailed ||
  AuditAction.restore => StatusTone.danger,
  AuditAction.permissionOverride || AuditAction.archive => StatusTone.warning,
  _ => StatusTone.neutral,
};
