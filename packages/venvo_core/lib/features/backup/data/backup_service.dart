import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_connection.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/app_paths.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/settings_service.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/backup_models.dart';

// The formatter lives with the models, which a browser can import; this file
// cannot be, because it opens the database. Re-exported so existing callers
// that import the service still find it.
export '../domain/backup_models.dart' show formatBytes;

/// Takes and restores backups.
///
/// A backup is one ZIP holding the database file, every attachment, and a
/// manifest. Three things about it are deliberate:
///
/// **The write-ahead log is checkpointed first.** SQLite in WAL mode keeps
/// recent commits in a side file, so copying `venvo_pos.sqlite` on its own
/// can silently leave the newest transactions out of the archive. Every backup
/// runs `PRAGMA wal_checkpoint(TRUNCATE)` before the copy, which folds the log
/// back into the main file. Without that a backup looks fine and quietly
/// misses the last few invoices.
///
/// **An archive is validated by opening it, not by trusting it.** [validate]
/// unpacks the database to a scratch file, opens it read-only and runs
/// SQLite's own `PRAGMA integrity_check`, then counts the rows it will be
/// restoring. A backup nobody has checked is a guess.
///
/// **A restore is staged, not applied in place.** The database this process
/// has open cannot be swapped underneath it: repositories, providers and open
/// query streams all hold the live connection. So [restore] archives the
/// current data as a safety copy, writes the incoming files beside the live
/// ones, and leaves a marker that [applyPendingRestore] acts on during the
/// next start, before anything opens the database.
class BackupService {
  const BackupService({
    required AppDatabase database,
    required AppPaths paths,
    required Clock clock,
    required AuditService audit,
    required SettingsService settings,
  }) : _db = database,
       _paths = paths,
       _clock = clock,
       _audit = audit,
       _settings = settings;

  final AppDatabase _db;
  final AppPaths _paths;
  final Clock _clock;
  final AuditService _audit;
  final SettingsService _settings;

  static const String _databaseEntry = 'database/venvo_pos.sqlite';
  static const String _attachmentsPrefix = 'attachments/';
  static const String _pendingRestoreMarker = 'restore-pending.json';
  static const String _stagedDatabase = 'restore-staged.sqlite';
  static const String _stagedAttachments = 'restore-staged-attachments';

  static final DateFormat _stamp = DateFormat('yyyy-MM-dd-HHmmss');

  // --- Taking a backup -----------------------------------------------------

  /// Writes a new archive and returns it.
  Future<BackupArchive> createBackup(
    AuthenticatedUser actor, {
    String? note,
    bool automatic = false,
  }) async {
    actor.require(Permissions.backupRun, action: 'take a backup');
    return _write(
      note: note,
      automatic: automatic,
      username: actor.username,
      actorId: actor.id,
    );
  }

  /// The same thing without a permission check, for the safety copy taken
  /// immediately before a restore and for the automatic daily backup. Both
  /// happen on behalf of an action the user has already been checked for.
  Future<BackupArchive> _write({
    required String? note,
    required bool automatic,
    required String username,
    required int actorId,
  }) async {
    // Fold the write-ahead log back into the database file, or the newest
    // commits would not be in the copy.
    await _checkpoint();

    final source = _paths.databaseFile;
    requireRule(
      source.existsSync(),
      'The database file is missing, so there is nothing to back up.',
      rule: 'backup.database_must_exist',
    );

    final now = _clock.nowUtc();
    if (!_paths.backupsDir.existsSync()) {
      await _paths.backupsDir.create(recursive: true);
    }

    final target = _nextFreeName(now, automatic: automatic);
    final fileName = target.uri.pathSegments.last;

    final attachments = _attachmentFiles();
    final attachmentBytes = attachments.fold<int>(
      0,
      (total, file) => total + file.lengthSync(),
    );

    final manifest = BackupManifest(
      appVersion: AppConstants.appVersion,
      schemaVersion: _db.schemaVersion,
      createdAt: now,
      databaseBytes: source.lengthSync(),
      attachmentCount: attachments.length,
      attachmentBytes: attachmentBytes,
      automatic: automatic,
      note: _clean(note),
      createdByUsername: username,
    );

    final encoder = ZipFileEncoder();
    try {
      encoder.create(target.path);
      await encoder.addFile(source, _databaseEntry);
      for (final file in attachments) {
        final relative = p.relative(
          file.path,
          from: _paths.attachmentsDir.path,
        );
        await encoder.addFile(file, '$_attachmentsPrefix${_posix(relative)}');
      }
      encoder.addArchiveFile(
        ArchiveFile.string(
          BackupManifest.fileName,
          const JsonEncoder.withIndent('  ').convert(manifest.toJson()),
        ),
      );
    } finally {
      await encoder.close();
    }

    await _audit.record(
      action: AuditAction.backup,
      summary:
          'Backup $fileName: database ${_mb(manifest.databaseBytes)}, '
          '${manifest.attachmentCount} attachment(s)'
          '${automatic ? ' (automatic)' : ''}'
          '${manifest.note == null ? '' : '. ${manifest.note}'}',
      userId: actorId,
      username: username,
      entityKind: EntityKind.backup,
      after: {
        'fileName': fileName,
        'schemaVersion': manifest.schemaVersion,
        'databaseBytes': manifest.databaseBytes,
        'attachmentCount': manifest.attachmentCount,
        'automatic': automatic,
      },
    );

    return BackupArchive(
      file: target,
      sizeBytes: target.lengthSync(),
      manifest: manifest,
    );
  }

  /// Takes the daily automatic backup when it is switched on and one has not
  /// been taken today. Returns null when nothing was due.
  ///
  /// Called at start-up rather than on a timer: a desktop application that is
  /// closed overnight would never fire a midnight timer, and "a backup every
  /// day the program was used" is what the business actually wants.
  Future<BackupArchive?> runAutomaticBackupIfDue(
    AuthenticatedUser actor,
  ) async {
    if (!await _settings.getBool(SettingKeys.autoBackupEnabled)) return null;

    final last = await _settings.getDateTime(SettingKeys.lastAutoBackupAt);
    final today = _clock.startOfLocalDay(_clock.nowUtc());
    if (last != null && !last.isBefore(today)) return null;

    final archive = await _write(
      note: 'Automatic daily backup',
      automatic: true,
      username: actor.username,
      actorId: actor.id,
    );
    await _settings.setDateTime(
      SettingKeys.lastAutoBackupAt,
      _clock.nowUtc(),
      updatedByUserId: actor.id,
    );
    await pruneOldBackups(actor);
    return archive;
  }

  /// Archives on disk, newest first.
  Future<List<BackupArchive>> listBackups() async {
    if (!_paths.backupsDir.existsSync()) return const [];

    final archives = <BackupArchive>[];
    for (final entity in _paths.backupsDir.listSync()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.zip')) {
        continue;
      }
      final manifest = _readManifest(entity);
      if (manifest == null) continue;
      archives.add(
        BackupArchive(
          file: entity,
          sizeBytes: entity.lengthSync(),
          manifest: manifest,
        ),
      );
    }

    archives.sort(
      (a, b) => b.manifest.createdAt.compareTo(a.manifest.createdAt),
    );
    return archives;
  }

  /// Deletes the oldest **automatic** backups beyond the retention limit.
  ///
  /// A backup somebody took by hand is never pruned: they took it for a
  /// reason, and guessing that the reason has passed is not this code's
  /// business.
  Future<int> pruneOldBackups(AuthenticatedUser actor, {int? keep}) async {
    final limit =
        keep ?? await _settings.getInt(SettingKeys.autoBackupRetentionCount);
    if (limit <= 0) return 0;

    final automatic = (await listBackups())
        .where((archive) => archive.isAutomatic)
        .toList();
    if (automatic.length <= limit) return 0;

    var deleted = 0;
    for (final archive in automatic.skip(limit)) {
      try {
        await archive.file.delete();
        deleted++;
      } on FileSystemException {
        // A file somebody has open in Explorer is left where it is rather
        // than failing the backup that triggered the prune.
        continue;
      }
    }

    if (deleted > 0) {
      await _audit.record(
        action: AuditAction.backup,
        summary:
            'Pruned $deleted automatic backup(s), keeping the newest $limit.',
        userId: actor.id,
        username: actor.username,
        entityKind: EntityKind.backup,
      );
    }
    return deleted;
  }

  // --- Validating ----------------------------------------------------------

  /// Opens an archive and checks it is worth restoring.
  Future<BackupValidation> validate(File archive) async {
    if (!archive.existsSync()) {
      return const BackupValidation.broken(['That file is no longer there.']);
    }

    Archive contents;
    try {
      contents = ZipDecoder().decodeBytes(await archive.readAsBytes());
    } catch (error) {
      return BackupValidation.broken([
        'The file is not a readable ZIP archive. ($error)',
      ]);
    }

    final manifestEntry = contents.files
        .where((file) => file.name == BackupManifest.fileName)
        .firstOrNull;
    if (manifestEntry == null) {
      return const BackupValidation.broken([
        'The archive has no manifest, so it was not produced by this application.',
      ]);
    }

    BackupManifest manifest;
    try {
      manifest = BackupManifest.fromJson(
        jsonDecode(utf8.decode(manifestEntry.content as List<int>))
            as Map<String, Object?>,
      );
    } catch (error) {
      return BackupValidation.broken([
        'The manifest could not be read. ($error)',
      ]);
    }

    final databaseEntry = contents.files
        .where((file) => file.name == _databaseEntry)
        .firstOrNull;
    if (databaseEntry == null) {
      return const BackupValidation.broken([
        'The archive has a manifest but no database file.',
      ]);
    }

    final problems = <String>[];
    if (manifest.schemaVersion > _db.schemaVersion) {
      // The same refusal the database itself makes on open: reading a newer
      // file with older column expectations corrupts data silently.
      problems.add(
        'This archive was written by a newer version of '
        '${AppConstants.appName} (database schema v${manifest.schemaVersion}; '
        'this build supports v${_db.schemaVersion}). Install the newer '
        'version to restore it.',
      );
    }

    // Unpack the database to a scratch file and let SQLite check it over.
    final scratch = File(
      p.join(
        Directory.systemTemp.createTempSync('venvo_validate_').path,
        'candidate.sqlite',
      ),
    );
    int? users;
    int? invoices;
    int? stockEntries;
    try {
      await scratch.writeAsBytes(
        databaseEntry.content as List<int>,
        flush: true,
      );

      final candidate = AppDatabase(DatabaseConnections.readOnlyFile(scratch));
      try {
        final integrity = await candidate
            .customSelect('PRAGMA integrity_check')
            .get();
        final verdict = integrity.isEmpty
            ? 'no result'
            : integrity.first.data.values.first.toString();
        if (verdict != 'ok') {
          problems.add('SQLite reports the database is damaged: $verdict.');
        }

        users = await _countIn(candidate, 'users');
        invoices = await _countIn(candidate, 'invoices');
        stockEntries = await _countIn(candidate, 'stock_ledger_entries');

        if (users == 0) {
          problems.add(
            'The archived database has no user accounts, so nobody could '
            'sign in to it.',
          );
        }
      } finally {
        await candidate.close();
      }
    } catch (error) {
      problems.add('The archived database could not be opened. ($error)');
    } finally {
      try {
        await scratch.parent.delete(recursive: true);
      } on FileSystemException {
        // A scratch directory left behind is not worth failing over.
      }
    }

    return BackupValidation(
      isUsable: problems.isEmpty,
      problems: problems,
      manifest: manifest,
      userCount: users,
      invoiceCount: invoices,
      stockEntryCount: stockEntries,
    );
  }

  // --- Restoring -----------------------------------------------------------

  /// Stages a restore, to be applied on the next start.
  ///
  /// Refuses an archive that does not validate, and takes a safety copy of the
  /// live data first so the restore can itself be undone.
  Future<RestoreOutcome> restore(
    AuthenticatedUser actor, {
    required File archive,
  }) async {
    actor.require(Permissions.backupRestore, action: 'restore a backup');

    final validation = await validate(archive);
    requireRule(
      validation.isUsable,
      'That archive cannot be restored. ${validation.problems.join(' ')}',
      rule: 'backup.restore_validated_only',
    );
    final manifest = validation.manifest!;

    // Whatever is live now is archived before anything is staged, so the
    // restore is reversible.
    final safety = await _write(
      note:
          'Taken automatically before restoring '
          '${archive.uri.pathSegments.last}',
      automatic: false,
      username: actor.username,
      actorId: actor.id,
    );

    final contents = ZipDecoder().decodeBytes(await archive.readAsBytes());

    final stagedDb = File(p.join(_paths.root.path, _stagedDatabase));
    final stagedAttachments = Directory(
      p.join(_paths.root.path, _stagedAttachments),
    );
    if (stagedAttachments.existsSync()) {
      await stagedAttachments.delete(recursive: true);
    }
    await stagedAttachments.create(recursive: true);

    for (final entry in contents.files) {
      if (!entry.isFile) continue;
      if (entry.name == _databaseEntry) {
        await stagedDb.writeAsBytes(entry.content as List<int>, flush: true);
      } else if (entry.name.startsWith(_attachmentsPrefix)) {
        final relative = entry.name.substring(_attachmentsPrefix.length);
        // Refuse a path that would escape the attachments folder: an archive
        // is a file from outside the application and is not trusted to be
        // well formed.
        if (_escapesFolder(relative)) continue;
        final file = File(p.join(stagedAttachments.path, relative));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content as List<int>, flush: true);
      }
    }

    await File(p.join(_paths.root.path, _pendingRestoreMarker)).writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'stagedAt': _clock.nowUtc().toIso8601String(),
        'archive': archive.uri.pathSegments.last,
        'safetyArchive': safety.fileName,
        'requestedByUsername': actor.username,
        'schemaVersion': manifest.schemaVersion,
      }),
      flush: true,
    );

    await _audit.record(
      action: AuditAction.restore,
      summary:
          'Restore staged from ${archive.uri.pathSegments.last} '
          '(written ${manifest.createdAt.toLocal()}). The current data was '
          'archived as ${safety.fileName} first. It is applied when '
          '${AppConstants.appName} next starts.',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.backup,
      after: {
        'archive': archive.uri.pathSegments.last,
        'safetyArchive': safety.fileName,
        'schemaVersion': manifest.schemaVersion,
      },
    );

    return RestoreOutcome(
      stagedFrom: archive,
      safetyArchive: safety.file,
      manifest: manifest,
    );
  }

  /// Whether a restore is waiting to be applied.
  Future<bool> hasPendingRestore() async {
    return File(p.join(_paths.root.path, _pendingRestoreMarker)).existsSync();
  }

  /// Cancels a staged restore, leaving the live data alone.
  Future<void> cancelPendingRestore(AuthenticatedUser actor) async {
    actor.require(Permissions.backupRestore, action: 'cancel a staged restore');

    final marker = File(p.join(_paths.root.path, _pendingRestoreMarker));
    requireRule(
      marker.existsSync(),
      'There is no staged restore to cancel.',
      rule: 'backup.no_pending_restore',
    );

    await marker.delete();
    final stagedDb = File(p.join(_paths.root.path, _stagedDatabase));
    if (stagedDb.existsSync()) await stagedDb.delete();
    final stagedAttachments = Directory(
      p.join(_paths.root.path, _stagedAttachments),
    );
    if (stagedAttachments.existsSync()) {
      await stagedAttachments.delete(recursive: true);
    }

    await _audit.record(
      action: AuditAction.restore,
      summary: 'Cancelled the staged restore; the live data is unchanged.',
      userId: actor.id,
      username: actor.username,
      entityKind: EntityKind.backup,
    );
  }

  /// Applies a staged restore. Called at start-up, **before** the database is
  /// opened, which is the only moment the files can safely be swapped.
  ///
  /// Static because it runs before there is an [AppDatabase] to construct this
  /// service with.
  static Future<RestoreApplied?> applyPendingRestore(AppPaths paths) async {
    final marker = File(p.join(paths.root.path, _pendingRestoreMarker));
    if (!marker.existsSync()) return null;

    final stagedDb = File(p.join(paths.root.path, _stagedDatabase));
    if (!stagedDb.existsSync()) {
      // Nothing to apply; clear the marker rather than failing every start
      // from here on.
      await marker.delete();
      return null;
    }

    Map<String, Object?> details;
    try {
      details = jsonDecode(await marker.readAsString()) as Map<String, Object?>;
    } catch (_) {
      details = const {};
    }

    // Move the live database aside rather than deleting it, so a failure
    // part-way leaves something to go back to.
    final live = paths.databaseFile;
    final supplanted = File('${live.path}.replaced');
    if (live.existsSync()) {
      if (supplanted.existsSync()) await supplanted.delete();
      await live.rename(supplanted.path);
    }
    // The write-ahead log and shared-memory files belong to the old database.
    // Leaving them beside a different file is what corrupts it.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('${live.path}$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }

    await stagedDb.rename(live.path);

    var attachmentsReplaced = false;
    final stagedAttachments = Directory(
      p.join(paths.root.path, _stagedAttachments),
    );
    if (stagedAttachments.existsSync()) {
      final liveAttachments = paths.attachmentsDir;
      final supplantedAttachments = Directory(
        '${liveAttachments.path}.replaced',
      );
      if (supplantedAttachments.existsSync()) {
        await supplantedAttachments.delete(recursive: true);
      }
      if (liveAttachments.existsSync()) {
        await liveAttachments.rename(supplantedAttachments.path);
      }
      await stagedAttachments.rename(liveAttachments.path);
      attachmentsReplaced = true;
    }

    await marker.delete();

    return RestoreApplied(
      restoredFrom: details['archive'] as String? ?? 'an archive',
      appliedAt: DateTime.now().toUtc(),
      attachmentsReplaced: attachmentsReplaced,
    );
  }

  // --- Internals ----------------------------------------------------------

  /// Folds the write-ahead log back into the database file.
  Future<void> _checkpoint() async {
    try {
      await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');
    } on Object catch (error) {
      // An in-memory database has no log to checkpoint, and a reader holding
      // the file can delay a truncate. Neither is worth refusing a backup
      // over, but a real failure should not pass unnoticed either.
      if (_paths.databaseFile.existsSync()) {
        throw StorageFailure(
          'The database could not be checkpointed before the backup, so the '
          'archive might not contain the newest changes.',
          details: '$error',
        );
      }
    }
  }

  /// A file name no archive is already using.
  ///
  /// The stamp is only accurate to the second, and two backups within the same
  /// second would otherwise land on the same name — and writing an archive
  /// truncates whatever is there. That matters most in the one place it is
  /// most likely: the safety copy taken immediately before a restore would
  /// overwrite the known-good archive being restored from, destroying it.
  File _nextFreeName(DateTime now, {required bool automatic}) {
    final base =
        'venvo-backup-${_stamp.format(now.toLocal())}'
        '${automatic ? '-auto' : ''}';

    final first = File(p.join(_paths.backupsDir.path, '$base.zip'));
    if (!first.existsSync()) return first;

    for (var suffix = 2; suffix < 1000; suffix++) {
      final candidate = File(
        p.join(_paths.backupsDir.path, '$base-$suffix.zip'),
      );
      if (!candidate.existsSync()) return candidate;
    }

    throw StorageFailure(
      'There are already a thousand backups from this second, which cannot '
      'be right.',
      details: base,
    );
  }

  List<File> _attachmentFiles() {
    if (!_paths.attachmentsDir.existsSync()) return const [];
    return _paths.attachmentsDir
        .listSync(recursive: true)
        .whereType<File>()
        .toList();
  }

  BackupManifest? _readManifest(File archive) {
    try {
      final contents = ZipDecoder().decodeBytes(archive.readAsBytesSync());
      final entry = contents.files
          .where((file) => file.name == BackupManifest.fileName)
          .firstOrNull;
      if (entry == null) return null;
      return BackupManifest.fromJson(
        jsonDecode(utf8.decode(entry.content as List<int>))
            as Map<String, Object?>,
      );
    } catch (_) {
      // A file in the backups folder that is not one of ours is skipped
      // rather than breaking the list.
      return null;
    }
  }

  static Future<int> _countIn(AppDatabase database, String table) async {
    final row = await database
        .customSelect('SELECT COUNT(*) AS c FROM $table')
        .getSingle();
    return row.read<int>('c');
  }

  /// True when a relative path from an archive would land outside the folder
  /// it is meant to go into.
  static bool _escapesFolder(String relative) {
    if (relative.isEmpty) return true;
    if (p.isAbsolute(relative) || relative.startsWith('/')) return true;
    if (relative.contains(':')) return true;
    return p.split(relative.replaceAll('\\', '/')).contains('..');
  }

  static String _posix(String path) => path.replaceAll(r'\', '/');

  static String _mb(int bytes) => formatBytes(bytes);

  static String? _clean(String? value) {
    final text = (value ?? '').trim();
    return text.isEmpty ? null : text;
  }
}
