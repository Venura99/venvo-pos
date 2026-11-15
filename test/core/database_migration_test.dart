import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/database/database_connection.dart';
import 'package:venvo_core/core/database/database_seeder.dart';
import 'package:venvo_core/core/services/clock.dart';

import '../helpers/test_harness.dart';

/// Exercises the real on-disk path: creating the file, closing it, reopening
/// it and confirming the migration machinery leaves an up-to-date database
/// alone.
void main() {
  late Directory tempDir;
  late File databaseFile;
  final clock = FixedClock(DateTime.utc(2026, 11, 1, 9));

  setUpAll(configureSqliteForTests);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('venvo_pos_migration_');
    databaseFile = File(p.join(tempDir.path, AppConstants.databaseFileName));
  });

  tearDown(() async {
    // The background isolate that owns the file can outlive a failed open by
    // a moment, and Windows keeps the handle until it exits. A leftover temp
    // folder is not worth failing a test over.
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } on FileSystemException {
      // Ignored: the operating system will reclaim it.
    }
  });

  AppDatabase openDatabase() =>
      AppDatabase(DatabaseConnections.file(databaseFile));

  test('creates the database file and records the schema version', () async {
    final db = openDatabase();
    await DatabaseSeeder(db, clock).run();

    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, 4);
    expect(databaseFile.existsSync(), isTrue);

    await db.close();
  });

  test('reopening an up-to-date database runs no migration', () async {
    final first = openDatabase();
    await DatabaseSeeder(first, clock).run();
    await first
        .into(first.categories)
        .insert(
          CategoriesCompanion.insert(
            name: 'Cables',
            createdAt: clock.nowUtc(),
            updatedAt: clock.nowUtc(),
          ),
        );
    await first.close();

    // A second open at the same schema version must not throw: the upgrade
    // path is only entered when the stored version is behind, and the guard
    // in _upgradeStep would throw loudly if it were entered by mistake.
    final second = openDatabase();
    final categories = await second.select(second.categories).get();
    expect(categories.map((c) => c.name), ['Cables']);
    await second.verifyIntegrity();
    await second.close();
  });

  test('data survives a close and reopen', () async {
    final first = openDatabase();
    await DatabaseSeeder(first, clock).run();
    await first.close();

    final second = openDatabase();
    final locations = await second.select(second.inventoryLocations).get();
    // The seed ran once; reopening must not duplicate it.
    expect(
      locations.where((l) => l.code == AppConstants.mainWarehouseCode).length,
      1,
    );

    // And the seed is still idempotent against an existing file.
    await DatabaseSeeder(second, clock).run();
    final afterReseed = await second.select(second.inventoryLocations).get();
    expect(afterReseed.length, locations.length);
    await second.close();
  });

  test('refuses to open a database from a newer schema version', () async {
    // Guards against opening a file written by a later release of the
    // application, which would otherwise be read with the wrong column
    // expectations.
    final first = openDatabase();
    await DatabaseSeeder(first, clock).run();
    await first.customStatement('PRAGMA user_version = 99');
    await first.close();

    final second = openDatabase();
    await expectLater(
      second.select(second.categories).get(),
      throwsA(anything),
      reason:
          'opening a future schema version must fail loudly, not silently '
          'read the file with the wrong column expectations',
    );
    try {
      await second.close();
    } on Object {
      // The connection already failed; closing it is best effort.
    }
  });

  test('upgrades a version 1 database by adding the indexes', () async {
    // Version 2 added three composite indexes after the query-plan checks
    // found that the movement history and the invoice register were sorting
    // their results instead of walking an index. A database written before
    // that has to pick them up, which is the first real exercise of the
    // migration machinery.
    final first = openDatabase();
    await DatabaseSeeder(first, clock).run();

    // Make it look like a version 1 file: the indexes gone, the version
    // stamp back to 1.
    for (final name in const [
      'idx_ledger_product_occurred',
      'idx_invoices_shop_date',
      'idx_invoices_agent_date',
    ]) {
      await first.customStatement('DROP INDEX IF EXISTS $name');
    }
    // A genuine version 1 file also predates the version 3 session table, so
    // remove it too. Leaving it behind would not simulate an old database; it
    // would simulate an impossible one, and the 2 -> 3 step would then be
    // asked to create a table that already exists.
    await first.customStatement('DROP TABLE IF EXISTS cheque_reminders');
    await first.customStatement('DROP TABLE IF EXISTS user_sessions');
    await first.customStatement('PRAGMA user_version = 1');
    await first.close();

    final second = openDatabase();
    // Touching the database is what triggers the migration.
    await second.select(second.categories).get();

    // Every step runs in order, so a version 1 file lands on the current
    // schema version rather than stopping at 2.
    final version = await second
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.first, 4);

    final indexes = await second
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name LIKE 'idx_%'",
        )
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')),
      containsAll(<String>[
        'idx_ledger_product_occurred',
        'idx_invoices_shop_date',
        'idx_invoices_agent_date',
      ]),
    );

    // And the seeded data is still there: a migration that adds an index
    // must not disturb anything.
    final categories = await second.select(second.expenseCategories).get();
    expect(categories, isNotEmpty);

    await second.close();
  });

  test('upgrades a version 2 database by adding the session table', () async {
    // Version 3 added user_sessions, which is what the cloud build
    // authenticates against. Every database written during the eight offline
    // phases is a version 2 file, so this is the step those installations
    // take, and it must not disturb a row of their business data.
    final first = openDatabase();
    await DatabaseSeeder(first, clock).run();

    // A version 2 file also predates the version 4 reminder log.
    await first.customStatement('DROP TABLE IF EXISTS cheque_reminders');
    await first.customStatement('DROP TABLE IF EXISTS user_sessions');
    await first.customStatement('PRAGMA user_version = 2');
    await first.close();

    final second = openDatabase();
    await second.select(second.categories).get();

    final version = await second
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.first, 4);

    // Present and usable, not merely declared.
    expect(await second.select(second.userSessions).get(), isEmpty);

    // And its indexes exist. `createTable` does not create them, so this is
    // the assertion that catches a migration which adds the table alone and
    // leaves every single token lookup scanning the whole session table.
    final indexes = await second
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'user_sessions'",
        )
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')),
      containsAll(<String>[
        'idx_sessions_token',
        'idx_sessions_user',
        'idx_sessions_expires',
      ]),
    );

    // The token index must be UNIQUE: it is what makes it impossible for two
    // sessions to share a token hash.
    final tokenIndex = await second
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_sessions_token'",
        )
        .getSingle();
    expect(tokenIndex.read<String>('sql'), contains('UNIQUE'));

    // The seeded data is untouched.
    expect(await second.select(second.expenseCategories).get(), isNotEmpty);

    await second.close();
  });

  test('upgrades a version 3 database by adding the reminder log', () async {
    // Version 4 added cheque_reminders. Every database the cloud build ran on
    // before cheque reminders existed is a version 3 file.
    final first = openDatabase();
    await DatabaseSeeder(first, clock).run();
    await first.customStatement('DROP TABLE IF EXISTS cheque_reminders');
    await first.customStatement('PRAGMA user_version = 3');
    await first.close();

    final second = openDatabase();
    await second.select(second.categories).get();

    final version = await second
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.first, 4);
    expect(await second.select(second.chequeReminders).get(), isEmpty);

    final indexes = await second
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'cheque_reminders'",
        )
        .get();
    expect(
      indexes.map((row) => row.read<String>('name')),
      contains('idx_cheque_reminders_cheque'),
    );
    expect(await second.select(second.expenseCategories).get(), isNotEmpty);
    await second.close();
  });

  test('write-ahead logging is enabled on the real file', () async {
    final db = openDatabase();
    await DatabaseSeeder(db, clock).run();
    final mode = await db.customSelect('PRAGMA journal_mode').getSingle();
    expect((mode.data.values.first as String).toLowerCase(), 'wal');
    await db.close();
  });
}
