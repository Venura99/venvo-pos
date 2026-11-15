import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/database/database_connection.dart';
import 'package:venvo_core/core/database/database_seeder.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/services/app_paths.dart';
import 'package:venvo_core/core/services/audit_service.dart';
import 'package:venvo_core/core/services/clock.dart';
import 'package:venvo_core/core/services/password_hasher.dart';
import 'package:venvo_core/core/services/settings_service.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';
import 'package:venvo_core/features/backup/data/backup_service.dart';
import 'package:venvo_core/features/backup/domain/backup_models.dart';

import '../helpers/test_harness.dart';

/// Backups and restores, over a real on-disk database.
///
/// In-memory would prove nothing here: the whole point is the file. These
/// tests open an actual SQLite file in a temporary folder, write to it,
/// archive it, and read the archive back.
void main() {
  late Directory root;
  late AppPaths paths;
  late AppDatabase db;
  late BackupService service;
  late AuthenticatedUser admin;
  late SettingsService settings;
  final clock = FixedClock(DateTime.utc(2026, 11, 20, 9, 30));

  setUpAll(configureSqliteForTests);

  setUp(() async {
    root = await Directory.systemTemp.createTemp('venvo_backup_');
    paths = await AppPaths.at(root);
    db = AppDatabase(DatabaseConnections.file(paths.databaseFile));

    await DatabaseSeeder(db, clock).run();
    settings = SettingsService(db, clock);
    await settings.load();

    final audit = AuditService(db, clock);
    admin =
        await AuthRepository(
          database: db,
          clock: clock,
          audit: audit,
          hasher: const PasswordHasher(iterations: 1000),
        ).createFirstAdministrator(
          fullName: 'Nimal Perera',
          username: 'nimal',
          password: 'Warehouse42',
        );

    service = BackupService(
      database: db,
      paths: paths,
      clock: clock,
      audit: audit,
      settings: settings,
    );
  });

  tearDown(() async {
    await db.close();
    try {
      if (root.existsSync()) await root.delete(recursive: true);
    } on FileSystemException {
      // Windows can hold the file handle a moment after the isolate exits.
    }
  });

  /// Writes a file into the attachments tree, as the application would.
  Future<File> writeAttachment(String relative, String contents) async {
    final file = paths.attachmentFile(relative);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents, flush: true);
    return file;
  }

  Archive openArchive(File file) =>
      ZipDecoder().decodeBytes(file.readAsBytesSync());

  group('taking a backup', () {
    test('writes an archive holding the database and a manifest', () async {
      final archive = await service.createBackup(admin, note: 'Month end');

      expect(archive.file.existsSync(), isTrue);
      expect(archive.fileName, startsWith('venvo-backup-'));
      expect(archive.fileName, endsWith('.zip'));
      expect(archive.sizeBytes, greaterThan(0));

      expect(archive.manifest.note, 'Month end');
      expect(archive.manifest.createdByUsername, 'nimal');
      expect(archive.manifest.schemaVersion, db.schemaVersion);
      expect(archive.manifest.appVersion, AppConstants.appVersion);
      expect(archive.manifest.automatic, isFalse);
      expect(archive.manifest.databaseBytes, greaterThan(0));

      final contents = openArchive(archive.file);
      expect(
        contents.files.map((file) => file.name),
        containsAll(<String>[
          'database/venvo_pos.sqlite',
          BackupManifest.fileName,
        ]),
      );
    });

    test('includes every attachment, keeping its relative path', () async {
      await writeAttachment('2026/11/receipt-one.pdf', 'first');
      await writeAttachment('2026/12/receipt-two.pdf', 'second');

      final archive = await service.createBackup(admin);

      expect(archive.manifest.attachmentCount, 2);
      expect(archive.manifest.attachmentBytes, 11);

      final names = openArchive(archive.file).files.map((f) => f.name);
      expect(names, contains('attachments/2026/11/receipt-one.pdf'));
      expect(names, contains('attachments/2026/12/receipt-two.pdf'));
    });

    test(
      'contains the newest writes, not just what was checkpointed',
      () async {
        // The point of the checkpoint. In WAL mode a fresh commit lives in the
        // side log, and copying the main database file alone would leave it
        // out - an archive that looks fine and quietly misses the last few
        // transactions.
        await settings.setString(
          SettingKeys.businessName,
          'Venvo Global (Pvt) Ltd',
          updatedByUserId: admin.id,
        );

        final archive = await service.createBackup(admin);
        final validation = await service.validate(archive.file);

        expect(validation.isUsable, isTrue);

        // Read the business name back out of the archived database itself.
        final scratch = Directory.systemTemp.createTempSync('venvo_read_');
        addTearDown(() {
          try {
            scratch.deleteSync(recursive: true);
          } on FileSystemException {
            // Ignored.
          }
        });
        final extracted = File(p.join(scratch.path, 'db.sqlite'));
        final entry = openArchive(
          archive.file,
        ).files.firstWhere((file) => file.name == 'database/venvo_pos.sqlite');
        await extracted.writeAsBytes(entry.content as List<int>, flush: true);

        final copy = AppDatabase(DatabaseConnections.readOnlyFile(extracted));
        final row = await copy
            .customSelect(
              'SELECT value FROM settings WHERE key = ?',
              variables: const [Variable<String>(SettingKeys.businessName)],
            )
            .getSingle();
        expect(row.read<String>('value'), 'Venvo Global (Pvt) Ltd');
        await copy.close();
      },
    );

    test('records the backup in the audit log', () async {
      final archive = await service.createBackup(admin, note: 'Before count');

      final entries = await db.select(db.auditLogs).get();
      final entry = entries.firstWhere(
        (row) => row.action == AuditAction.backup,
      );
      expect(entry.summary, contains(archive.fileName));
      expect(entry.summary, contains('Before count'));
      expect(entry.entityKind, EntityKind.backup);
    });

    test('needs the backup permission', () async {
      const viewer = AuthenticatedUser(
        id: 999,
        username: 'ravi',
        fullName: 'Ravi',
        roleCodes: {'VIEWER'},
        permissions: <String>{},
        mustChangePassword: false,
      );

      await expectLater(
        service.createBackup(viewer),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('lists archives newest first', () async {
      await service.createBackup(admin, note: 'First');
      clock.advance(const Duration(minutes: 5));
      await service.createBackup(admin, note: 'Second');

      final archives = await service.listBackups();
      expect(archives, hasLength(2));
      expect(archives.first.manifest.note, 'Second');
      expect(archives.last.manifest.note, 'First');
    });

    test(
      'two backups in the same second do not overwrite each other',
      () async {
        // The stamp in the file name is only accurate to the second, and
        // writing an archive truncates whatever is already at that path. The
        // case that matters is the safety copy taken immediately before a
        // restore: it would otherwise destroy the known-good archive being
        // restored from.
        final first = await service.createBackup(admin, note: 'First');
        final second = await service.createBackup(admin, note: 'Second');

        expect(first.fileName, isNot(second.fileName));
        expect(first.file.existsSync(), isTrue);
        expect(second.file.existsSync(), isTrue);

        final archives = await service.listBackups();
        expect(archives, hasLength(2));
        expect(
          archives.map((archive) => archive.manifest.note),
          containsAll(<String>['First', 'Second']),
        );
      },
    );

    test('a restore does not consume the archive it restores from', () async {
      await settings.setString(
        SettingKeys.businessName,
        'The original name',
        updatedByUserId: admin.id,
      );
      final known = await service.createBackup(admin, note: 'Known good');

      // The safety copy is taken in the same instant on a fixed clock, which
      // is exactly when a name collision would eat the archive.
      await service.restore(admin, archive: known.file);

      expect(known.file.existsSync(), isTrue);
      final still = await service.validate(known.file);
      expect(still.isUsable, isTrue);
      expect(still.manifest!.note, 'Known good');
    });

    test('ignores a stray file in the backups folder', () async {
      await service.createBackup(admin);
      await File(
        p.join(paths.backupsDir.path, 'notes.txt'),
      ).writeAsString('not an archive');
      await File(
        p.join(paths.backupsDir.path, 'broken.zip'),
      ).writeAsString('not really a zip');

      // Listing still works and shows only what this application wrote.
      final archives = await service.listBackups();
      expect(archives, hasLength(1));
    });
  });

  group('the automatic daily backup', () {
    test('does nothing while it is switched off', () async {
      await settings.setBool(SettingKeys.autoBackupEnabled, false);

      expect(await service.runAutomaticBackupIfDue(admin), isNull);
      expect(await service.listBackups(), isEmpty);
    });

    test('takes one a day, and only one', () async {
      await settings.setBool(SettingKeys.autoBackupEnabled, true);

      final first = await service.runAutomaticBackupIfDue(admin);
      expect(first, isNotNull);
      expect(first!.isAutomatic, isTrue);
      expect(first.fileName, contains('-auto'));

      // Later the same day: nothing more to do.
      clock.advance(const Duration(hours: 6));
      expect(await service.runAutomaticBackupIfDue(admin), isNull);
      expect(await service.listBackups(), hasLength(1));

      // The next day: due again.
      clock.advance(const Duration(days: 1));
      expect(await service.runAutomaticBackupIfDue(admin), isNotNull);
      expect(await service.listBackups(), hasLength(2));
    });

    test('prunes old automatic backups but never one taken by hand', () async {
      await settings.setBool(SettingKeys.autoBackupEnabled, true);
      await settings.setInt(SettingKeys.autoBackupRetentionCount, 2);

      await service.createBackup(admin, note: 'Kept on purpose');

      for (var day = 0; day < 4; day++) {
        clock.advance(const Duration(days: 1));
        await service.runAutomaticBackupIfDue(admin);
      }

      final archives = await service.listBackups();
      final automatic = archives.where((a) => a.isAutomatic).toList();
      final byHand = archives.where((a) => !a.isAutomatic).toList();

      // Two automatic ones kept, and the hand-taken one untouched: somebody
      // took that for a reason, and guessing the reason has passed is not
      // this code's business.
      expect(automatic, hasLength(2));
      expect(byHand, hasLength(1));
      expect(byHand.single.manifest.note, 'Kept on purpose');
    });
  });

  group('validating an archive', () {
    test(
      'accepts one this application wrote, and reads its contents',
      () async {
        await writeAttachment('2026/11/a.pdf', 'x');
        final archive = await service.createBackup(admin);

        final validation = await service.validate(archive.file);

        expect(validation.isUsable, isTrue);
        expect(validation.problems, isEmpty);
        expect(validation.manifest!.attachmentCount, 1);
        // Read out of the archived database, not from the manifest.
        expect(validation.userCount, 1);
        expect(validation.invoiceCount, 0);
        expect(validation.stockEntryCount, 0);
      },
    );

    test('refuses a file that is not a ZIP', () async {
      final junk = File(p.join(root.path, 'junk.zip'));
      await junk.writeAsString('this is not a zip archive');

      final validation = await service.validate(junk);
      expect(validation.isUsable, isFalse);
      expect(validation.problems.first, contains('not a readable ZIP'));
    });

    test('refuses a file that is no longer there', () async {
      final validation = await service.validate(
        File(p.join(root.path, 'gone.zip')),
      );
      expect(validation.isUsable, isFalse);
      expect(validation.problems.first, contains('no longer there'));
    });

    test('refuses a ZIP with no manifest', () async {
      final target = File(p.join(root.path, 'stranger.zip'));
      final encoder = ZipFileEncoder()..create(target.path);
      encoder.addArchiveFile(ArchiveFile.string('readme.txt', 'hello'));
      await encoder.close();

      final validation = await service.validate(target);
      expect(validation.isUsable, isFalse);
      expect(validation.problems.first, contains('no manifest'));
    });

    test('refuses an archive from a newer release', () async {
      final archive = await service.createBackup(admin);
      final rewritten = await _rewriteManifest(
        archive.file,
        root,
        (json) => {...json, 'schemaVersion': db.schemaVersion + 5},
      );

      final validation = await service.validate(rewritten);

      expect(validation.isUsable, isFalse);
      expect(
        validation.problems.single,
        contains('newer version of ${AppConstants.appName}'),
      );
    });

    test('refuses an archive whose database is damaged', () async {
      final archive = await service.createBackup(admin);
      final broken = await _replaceDatabaseEntry(
        archive.file,
        root,
        utf8.encode('SQLite format 3\u0000 but then nonsense'),
      );

      final validation = await service.validate(broken);
      expect(validation.isUsable, isFalse);
      expect(validation.problems, isNotEmpty);
    });
  });

  group('restoring', () {
    test('stages the archive and takes a safety copy first', () async {
      await writeAttachment('2026/11/original.pdf', 'original');
      final archive = await service.createBackup(admin, note: 'Known good');

      // The data moves on after the backup.
      await settings.setString(
        SettingKeys.businessName,
        'Changed afterwards',
        updatedByUserId: admin.id,
      );

      final outcome = await service.restore(admin, archive: archive.file);

      expect(outcome.manifest.note, 'Known good');
      expect(outcome.safetyArchive.existsSync(), isTrue);
      expect(await service.hasPendingRestore(), isTrue);

      // Nothing has been applied yet: the live data is untouched.
      expect(
        await settings.getString(SettingKeys.businessName),
        'Changed afterwards',
      );

      // The safety archive holds the data as it is now, so the restore can
      // itself be undone.
      final safety = await service.validate(outcome.safetyArchive);
      expect(safety.isUsable, isTrue);
      expect(safety.manifest!.note, contains('before restoring'));
    });

    test('refuses an archive that does not validate', () async {
      final junk = File(p.join(root.path, 'junk.zip'));
      await junk.writeAsString('nope');

      await expectLater(
        service.restore(admin, archive: junk),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'backup.restore_validated_only',
          ),
        ),
      );
      expect(await service.hasPendingRestore(), isFalse);
    });

    test('needs the restore permission, which is not the backup one', () async {
      final archive = await service.createBackup(admin);
      const keeper = AuthenticatedUser(
        id: 998,
        username: 'sunil',
        fullName: 'Sunil',
        roleCodes: {'STORE_KEEPER'},
        // Can take a backup; cannot restore one over the business's data.
        permissions: {'backup.run'},
        mustChangePassword: false,
      );

      await expectLater(
        service.restore(keeper, archive: archive.file),
        throwsA(isA<PermissionFailure>()),
      );
    });

    test('can be cancelled, leaving the live data alone', () async {
      final archive = await service.createBackup(admin);
      await service.restore(admin, archive: archive.file);
      expect(await service.hasPendingRestore(), isTrue);

      await service.cancelPendingRestore(admin);

      expect(await service.hasPendingRestore(), isFalse);
      expect(
        File(p.join(root.path, 'restore-staged.sqlite')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(root.path, 'restore-staged-attachments')).existsSync(),
        isFalse,
      );
    });

    test('refuses to cancel when nothing is staged', () async {
      await expectLater(
        service.cancelPendingRestore(admin),
        throwsA(
          isA<BusinessRuleFailure>().having(
            (failure) => failure.rule,
            'rule',
            'backup.no_pending_restore',
          ),
        ),
      );
    });

    test('is applied on the next start, and the data comes back', () async {
      // A known state, archived.
      await settings.setString(
        SettingKeys.businessName,
        'The original name',
        updatedByUserId: admin.id,
      );
      await writeAttachment('2026/11/kept.pdf', 'kept');
      final archive = await service.createBackup(admin, note: 'Known good');

      // Then somebody changes things and deletes the attachment.
      await settings.setString(
        SettingKeys.businessName,
        'A mistake',
        updatedByUserId: admin.id,
      );
      await paths.attachmentFile('2026/11/kept.pdf').delete();
      await writeAttachment('2026/11/unwanted.pdf', 'unwanted');

      await service.restore(admin, archive: archive.file);

      // The database has to be closed before the file can be swapped, which
      // is exactly why a restore waits for a restart.
      await db.close();
      final applied = await BackupService.applyPendingRestore(paths);

      expect(applied, isNotNull);
      expect(applied!.restoredFrom, archive.fileName);
      expect(applied.attachmentsReplaced, isTrue);

      // Reopen, as the next start would.
      db = AppDatabase(DatabaseConnections.file(paths.databaseFile));
      final reopened = SettingsService(db, clock);
      await reopened.load();

      expect(
        await reopened.getString(SettingKeys.businessName),
        'The original name',
      );
      // The attachments came back with it, and what was added since is gone.
      expect(paths.attachmentFile('2026/11/kept.pdf').existsSync(), isTrue);
      expect(
        paths.attachmentFile('2026/11/unwanted.pdf').existsSync(),
        isFalse,
      );
      // And the marker is cleared, so the next start does not do it again.
      expect(
        File(p.join(root.path, 'restore-pending.json')).existsSync(),
        isFalse,
      );
    });

    test('leaves the replaced data on disk rather than deleting it', () async {
      final archive = await service.createBackup(admin);
      await service.restore(admin, archive: archive.file);
      await db.close();

      await BackupService.applyPendingRestore(paths);

      // The database that was live is moved aside, not removed: a restore
      // that turns out to be wrong leaves something to go back to even
      // before the safety archive is opened.
      expect(File('${paths.databaseFile.path}.replaced').existsSync(), isTrue);

      db = AppDatabase(DatabaseConnections.file(paths.databaseFile));
    });

    test('clears the write-ahead log of the database it replaced', () async {
      final archive = await service.createBackup(admin);
      await service.restore(admin, archive: archive.file);
      await db.close();

      await BackupService.applyPendingRestore(paths);

      // A log file belonging to the old database left beside a different one
      // is how a restored file gets corrupted.
      expect(File('${paths.databaseFile.path}-wal').existsSync(), isFalse);
      expect(File('${paths.databaseFile.path}-shm').existsSync(), isFalse);

      db = AppDatabase(DatabaseConnections.file(paths.databaseFile));
    });

    test('does nothing at start-up when no restore is staged', () async {
      expect(await BackupService.applyPendingRestore(paths), isNull);
    });

    test(
      'ignores an attachment path that tries to escape the folder',
      () async {
        // An archive is a file from outside the application and is not trusted
        // to be well formed.
        final archive = await service.createBackup(admin);
        final tampered = await _addEntry(
          archive.file,
          root,
          'attachments/../../escaped.txt',
          utf8.encode('should not be written'),
        );

        await service.restore(admin, archive: tampered);
        await db.close();
        await BackupService.applyPendingRestore(paths);

        expect(
          File(p.join(root.parent.path, 'escaped.txt')).existsSync(),
          isFalse,
        );
        expect(File(p.join(root.path, 'escaped.txt')).existsSync(), isFalse);

        db = AppDatabase(DatabaseConnections.file(paths.databaseFile));
      },
    );

    test('records the staging in the audit log', () async {
      final archive = await service.createBackup(admin, note: 'Known good');
      await service.restore(admin, archive: archive.file);

      final entries = await db.select(db.auditLogs).get();
      final entry = entries.firstWhere(
        (row) => row.action == AuditAction.restore,
      );
      expect(entry.summary, contains(archive.fileName));
      expect(entry.summary, contains('archived as'));
      expect(entry.summary, contains('next starts'));
    });
  });
}

/// Rewrites an archive's manifest, for testing what validation refuses.
Future<File> _rewriteManifest(
  File source,
  Directory root,
  Map<String, Object?> Function(Map<String, Object?> json) change,
) async {
  final contents = ZipDecoder().decodeBytes(source.readAsBytesSync());
  final target = File(p.join(root.path, 'rewritten.zip'));
  final encoder = ZipFileEncoder()..create(target.path);

  for (final entry in contents.files) {
    if (!entry.isFile) continue;
    if (entry.name == BackupManifest.fileName) {
      final json =
          jsonDecode(utf8.decode(entry.content as List<int>))
              as Map<String, Object?>;
      encoder.addArchiveFile(
        ArchiveFile.string(entry.name, jsonEncode(change(json))),
      );
    } else {
      encoder.addArchiveFile(
        _bytesEntry(entry.name, entry.content as List<int>),
      );
    }
  }
  await encoder.close();
  return target;
}

/// Swaps an archive's database for the given bytes.
Future<File> _replaceDatabaseEntry(
  File source,
  Directory root,
  List<int> bytes,
) async {
  final contents = ZipDecoder().decodeBytes(source.readAsBytesSync());
  final target = File(p.join(root.path, 'damaged.zip'));
  final encoder = ZipFileEncoder()..create(target.path);

  for (final entry in contents.files) {
    if (!entry.isFile) continue;
    encoder.addArchiveFile(
      _bytesEntry(
        entry.name,
        entry.name == 'database/venvo_pos.sqlite'
            ? bytes
            : entry.content as List<int>,
      ),
    );
  }
  await encoder.close();
  return target;
}

/// Adds an entry to an archive, for testing a tampered one.
Future<File> _addEntry(
  File source,
  Directory root,
  String name,
  List<int> bytes,
) async {
  final contents = ZipDecoder().decodeBytes(source.readAsBytesSync());
  final target = File(p.join(root.path, 'tampered.zip'));
  final encoder = ZipFileEncoder()..create(target.path);

  for (final entry in contents.files) {
    if (!entry.isFile) continue;
    encoder.addArchiveFile(_bytesEntry(entry.name, entry.content as List<int>));
  }
  encoder.addArchiveFile(_bytesEntry(name, bytes));
  await encoder.close();
  return target;
}

/// An archive entry holding raw bytes.
ArchiveFile _bytesEntry(String name, List<int> bytes) =>
    ArchiveFile(name, bytes.length, bytes);
