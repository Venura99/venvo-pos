import 'dart:io';

import 'package:path/path.dart' as p;

import '../constants/app_constants.dart';
import '../errors/failures.dart';

/// Resolves and creates the application's data directories.
///
/// Everything the business owns lives under one folder so that a backup is a
/// single archive and a restore is a single replace:
///
/// ```
/// %APPDATA%\lk.venvoglobal\VenvoPOS\      (desktop client)
/// /var/lib/venvo-pos/                     (server, set by configuration)
///   venvo_pos.sqlite       the database
///   attachments\           uploaded bills, receipts, cheque images
///     2026\11\<uuid>.pdf
///   backups\               generated archives
///   exports\               generated PDF / CSV output
/// ```
///
/// Attachment binaries are stored on disk and only referenced from SQLite, so
/// the database file stays small and quick to copy.
class AppPaths {
  AppPaths._(this.root);

  /// Points every directory at [root].
  ///
  /// This is the only way in. Resolving a *per-user* application directory
  /// needs `path_provider`, which is Flutter-only and therefore cannot live in
  /// this package; the client does that step in `resolveClientAppPaths()` and
  /// hands the result here. A server is told its data root by configuration,
  /// and tests pass a temporary folder.
  static Future<AppPaths> at(Directory root) async {
    final paths = AppPaths._(root);
    await paths.ensureDirectories();
    return paths;
  }

  final Directory root;

  File get databaseFile =>
      File(p.join(root.path, AppConstants.databaseFileName));

  Directory get attachmentsDir =>
      Directory(p.join(root.path, AppConstants.attachmentsFolderName));

  Directory get backupsDir =>
      Directory(p.join(root.path, AppConstants.backupsFolderName));

  Directory get exportsDir =>
      Directory(p.join(root.path, AppConstants.exportsFolderName));

  Future<void> ensureDirectories() async {
    try {
      for (final dir in [root, attachmentsDir, backupsDir, exportsDir]) {
        if (!dir.existsSync()) {
          await dir.create(recursive: true);
        }
      }
    } on FileSystemException catch (error) {
      throw StorageFailure(
        'Could not create the application data folder.',
        details: '${error.path}: ${error.message}',
      );
    }
  }

  /// Builds the year/month-partitioned relative path an attachment is stored
  /// at. Partitioning keeps any single directory from growing unbounded, which
  /// Windows Explorer and backup archiving both dislike.
  String attachmentRelativePath({
    required DateTime when,
    required String storedFileName,
  }) {
    final year = when.year.toString().padLeft(4, '0');
    final month = when.month.toString().padLeft(2, '0');
    return p.join(year, month, storedFileName);
  }

  /// Turns a stored relative path back into an absolute file.
  File attachmentFile(String relativePath) =>
      File(p.join(attachmentsDir.path, relativePath));

  Future<Directory> ensureAttachmentDirFor(String relativePath) async {
    final dir = Directory(p.dirname(attachmentFile(relativePath).path));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
