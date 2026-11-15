import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/features/backup/api/backup_api.dart';

import '../../../core/providers/core_providers.dart';

/// Backups of the server's database.
final backupServiceProvider = Provider<BackupApi>(
  (ref) => BackupApi(ref.watch(apiClientProvider)),
);

/// Bumped after taking or pruning a backup, which is what re-reads the list.
/// The archives are files on the server, so there is no stream to watch.
final backupRevisionProvider = StateProvider<int>((ref) => 0);

final backupListProvider = FutureProvider<List<ServerBackup>>((ref) {
  ref.watch(backupRevisionProvider);
  return ref.watch(backupServiceProvider).listBackups();
});
