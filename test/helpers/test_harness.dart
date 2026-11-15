import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:sqlite3/open.dart';
import 'package:venvo_core/core/bootstrap/app_bootstrap.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/database/database_connection.dart';
import 'package:venvo_core/core/services/clock.dart';

/// Shared setup for every database test.
///
/// Under `flutter test` the code runs on the Dart VM rather than inside the
/// Windows runner, so the SQLite library bundled by `sqlite3_flutter_libs` for
/// the application is not loaded. Windows ships its own copy as
/// `winsqlite3.dll`, which is what the tests open. The shipped application is
/// unaffected: it uses the bundled library.
void configureSqliteForTests() {
  // Each test builds its own database over its own executor, which is exactly
  // what drift's multiple-instance warning is meant to catch in application
  // code. It is correct here and only adds noise to the test output.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  if (!Platform.isWindows) return;
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
}

/// A database test fixture: an in-memory database with the system seed applied
/// and a clock the test controls.
class TestHarness {
  TestHarness._(this.bootstrap, this.clock, this._tempDir);

  /// Builds a fresh, isolated database. [at] fixes the clock so that
  /// date-filtered assertions are deterministic.
  static Future<TestHarness> create({
    DateTime? at,
    bool withDataDirectory = false,
  }) async {
    configureSqliteForTests();

    final clock = FixedClock(at ?? DateTime.utc(2026, 11, 1, 9, 30));
    final database = AppDatabase(DatabaseConnections.memory());

    Directory? tempDir;
    if (withDataDirectory) {
      tempDir = await Directory.systemTemp.createTemp('venvo_pos_test_');
    }

    final bootstrap = await AppBootstrap.forTesting(
      clock: clock,
      database: database,
      dataRoot: tempDir,
    );

    return TestHarness._(bootstrap, clock, tempDir);
  }

  final AppBootstrap bootstrap;
  final FixedClock clock;
  final Directory? _tempDir;

  AppDatabase get db => bootstrap.database;

  Future<void> dispose() async {
    await bootstrap.dispose();
    if (_tempDir != null && _tempDir.existsSync()) {
      await _tempDir.delete(recursive: true);
    }
  }
}
