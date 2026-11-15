import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/backup/api/backup_api.dart';
import 'package:venvo_core/features/backup/domain/backup_models.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/app_data_table.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/form_dialog.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/kpi_card.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/section_card.dart';
import '../../../core/widgets/status_pill.dart';
import '../../authentication/presentation/auth_controller.dart';
import 'backup_providers.dart';

/// Backups of the server's database.
///
/// The archives live on the server, where the data is: every device shares
/// one database, so there is nothing on this device to back up. This screen
/// shows the state of the server's backups, takes one on demand and prunes old
/// automatic ones.
///
/// Restoring is deliberately not here. On a server a restore replaces the
/// data under every signed-in device at once and needs the server stopped
/// while the file is swapped, so it is done by whoever runs the server, at
/// the server — not by a button a till can reach.
class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (!(user?.can(Permissions.backupRun) ?? false)) {
      return const PageScaffold(
        title: 'Backups',
        child: EmptyState(
          icon: Icons.lock_outline,
          title: 'You do not have access to backups',
        ),
      );
    }

    return PageScaffold(
      title: 'Backups',
      description:
          'Backups are taken on the server: one archive holding the whole '
          'database and every attachment.',
      scrollable: false,
      actions: [
        OutlinedButton.icon(
          onPressed: () => _prune(context, ref),
          icon: const Icon(Icons.cleaning_services_outlined, size: 18),
          label: const Text('Remove old automatic'),
        ),
        FilledButton.icon(
          onPressed: () => _takeBackup(context, ref),
          icon: const Icon(Icons.backup_outlined, size: 18),
          label: const Text('Back up now'),
        ),
      ],
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(),
          AppSpacing.gapLg,
          Expanded(child: _BackupTable()),
        ],
      ),
    );
  }

  Future<void> _takeBackup(BuildContext context, WidgetRef ref) async {
    final noteController = TextEditingController();

    final taken = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppFormDialog(
        title: 'Back up now',
        subtitle:
            'The server writes the database and every attachment to one '
            'archive.',
        submitLabel: 'Take the backup',
        onSubmit: () async {
          await ref
              .read(backupServiceProvider)
              .createBackup(
                ref.read(requireCurrentUserProvider),
                note: noteController.text,
              );
          ref.read(backupRevisionProvider.notifier).state++;
        },
        child: AppTextField(
          controller: noteController,
          label: 'Note',
          autofocus: true,
          maxLength: 200,
          helperText:
              'Why you took it — "before the stock count", "month end". '
              'A note makes an archive worth keeping.',
        ),
      ),
    );

    noteController.dispose();
    if ((taken ?? false) && context.mounted) {
      showSuccessSnackBar(context, 'Backup written on the server.');
    }
  }

  Future<void> _prune(BuildContext context, WidgetRef ref) async {
    try {
      final removed = await ref
          .read(backupServiceProvider)
          .pruneOldBackups(ref.read(requireCurrentUserProvider));
      ref.read(backupRevisionProvider.notifier).state++;
      if (context.mounted) {
        showSuccessSnackBar(
          context,
          removed == 0
              ? 'Nothing to remove.'
              : 'Removed $removed old automatic backup(s).',
        );
      }
    } catch (error) {
      if (context.mounted) showFailureSnackBar(context, error);
    }
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archives = ref.watch(backupListProvider).valueOrNull;
    final settings = ref.watch(settingsServiceProvider);
    final newest = archives == null || archives.isEmpty ? null : archives.first;
    final automatic = settings.getBoolSync(SettingKeys.autoBackupEnabled);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KpiGrid(
          children: [
            KpiCard(
              label: 'Newest backup',
              value: newest == null
                  ? 'None yet'
                  : DateFormat(
                      'd MMM, HH:mm',
                    ).format(newest.manifest.createdAt.toLocal()),
              caption: newest == null
                  ? 'Take one before relying on the server'
                  : '${formatBytes(newest.sizeBytes)} · '
                        '${newest.manifest.automatic ? 'automatic' : 'taken by hand'}',
              icon: Icons.backup_outlined,
              tone: newest == null ? StatusTone.danger : StatusTone.success,
              isLoading: archives == null,
            ),
            KpiCard(
              label: 'Archives kept',
              value: '${archives?.length ?? 0}',
              caption: 'On the server',
              icon: Icons.inventory_2_outlined,
              isLoading: archives == null,
            ),
            KpiCard(
              label: 'Total size',
              value: formatBytes(
                (archives ?? const <ServerBackup>[]).fold<int>(
                  0,
                  (total, archive) => total + archive.sizeBytes,
                ),
              ),
              caption: 'On the server',
              icon: Icons.sd_storage_outlined,
              isLoading: archives == null,
            ),
            KpiCard(
              label: 'Automatic backup',
              value: automatic ? 'On' : 'Off',
              caption: 'One a day, on the first sign-in of the day',
              icon: Icons.schedule,
              tone: automatic ? StatusTone.success : StatusTone.warning,
            ),
          ],
        ),
        if (newest == null) ...[
          AppSpacing.gapLg,
          SectionCard(
            leading: Icon(
              Icons.warning_amber_outlined,
              color: context.statusColors.danger,
            ),
            title: 'The server has no backup yet',
            subtitle:
                'Take one now. Archives sit on the server\'s own disk, so '
                'whoever runs the server should also copy them somewhere '
                'else — a disk failure takes the database and any backup '
                'beside it together.',
          ),
        ],
      ],
    );
  }
}

class _BackupTable extends ConsumerWidget {
  const _BackupTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<ServerBackup>>(
      value: ref.watch(backupListProvider),
      onRetry: () => ref.read(backupRevisionProvider.notifier).state++,
      builder: (context, archives) => SectionCard(
        title: 'Archives on the server',
        subtitle:
            'Restoring one is done on the server itself, by whoever runs it.',
        padding: EdgeInsets.zero,
        fillHeight: true,
        child: AppDataTable<ServerBackup>(
          rows: archives,
          minWidth: 860,
          empty: const EmptyState(
            icon: Icons.backup_outlined,
            title: 'No backups yet',
            message: 'Use "Back up now" to write the first one.',
          ),
          columns: [
            AppTableColumn<ServerBackup>(
              label: 'Taken',
              width: 170,
              cell: (context, row) => TableTwoLineCell(
                primary: DateFormat(
                  'd MMM yyyy, HH:mm',
                ).format(row.manifest.createdAt.toLocal()),
                secondary: row.manifest.createdByUsername == null
                    ? row.fileName
                    : 'by ${row.manifest.createdByUsername}',
              ),
            ),
            AppTableColumn<ServerBackup>(
              label: 'Note',
              flex: 4,
              cell: (context, row) =>
                  TableTextCell(row.manifest.note ?? '—', maxLines: 2),
            ),
            AppTableColumn<ServerBackup>(
              label: 'Contents',
              flex: 3,
              cell: (context, row) => TableTwoLineCell(
                primary: 'Database ${formatBytes(row.manifest.databaseBytes)}',
                secondary: row.manifest.attachmentCount == 0
                    ? 'No attachments'
                    : '${row.manifest.attachmentCount} attachment(s), '
                          '${formatBytes(row.manifest.attachmentBytes)}',
              ),
            ),
            AppTableColumn<ServerBackup>(
              label: 'Archive size',
              width: 130,
              numeric: true,
              cell: (context, row) => TableTextCell(formatBytes(row.sizeBytes)),
            ),
            AppTableColumn<ServerBackup>(
              label: 'Kind',
              width: 120,
              cell: (context, row) => StatusPill(
                row.manifest.automatic ? 'Automatic' : 'By hand',
                tone: row.manifest.automatic
                    ? StatusTone.neutral
                    : StatusTone.info,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
