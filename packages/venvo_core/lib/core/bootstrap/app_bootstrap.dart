import 'dart:io';

import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/database/database_connection.dart';
import 'package:venvo_core/core/database/database_seeder.dart';
import 'package:venvo_core/core/services/app_paths.dart';
import 'package:venvo_core/core/services/audit_service.dart';
import 'package:venvo_core/core/services/clock.dart';
import 'package:venvo_core/core/services/sequence_service.dart';
import 'package:venvo_core/core/services/settings_service.dart';
import 'package:venvo_core/features/backup/data/backup_service.dart';
import 'package:venvo_core/features/backup/domain/backup_models.dart';

/// Everything the application needs that must be built before the first frame:
/// the data directories, the database connection, the system seed and the
/// shared services.
///
/// Composed once in `main` and injected through Riverpod, which keeps the
/// widget tree free of singletons and lets tests build the same object graph
/// against an in-memory database.
class AppBootstrap {
  AppBootstrap._({
    required this.paths,
    required this.database,
    required this.clock,
    required this.settings,
    required this.audit,
    required this.sequences,
    required this.seeder,
    required this.needsFirstRunSetup,
    this.restoreApplied,
  });

  final AppPaths? paths;
  final AppDatabase database;
  final Clock clock;
  final SettingsService settings;
  final AuditService audit;
  final SequenceService sequences;
  final DatabaseSeeder seeder;

  /// True when the database holds no user yet, so the first-run screen must
  /// create the administrator account before anything else can happen.
  final bool needsFirstRunSetup;

  /// Set when a restore staged by the previous session was applied during
  /// this start-up, so the application can say so rather than leaving the
  /// user to wonder whether it worked.
  final RestoreApplied? restoreApplied;

  /// Opens the on-disk database under [paths] and composes the services.
  ///
  /// Shared by the desktop client, the Android client and the API server. The
  /// client resolves [paths] from its per-user application data folder; the
  /// server is told its data root by configuration. Everything from here on is
  /// identical, which is what stops a rule holding in one place and not the
  /// other.
  static Future<AppBootstrap> open({
    required AppPaths paths,
    Clock clock = const SystemClock(),
    bool logStatements = false,
  }) async {
    // A restore staged by the last session is applied here, before anything
    // opens the database. It is the only safe moment: once a connection is
    // open, every repository and query stream is holding it and the file
    // underneath cannot be swapped.
    final restored = await BackupService.applyPendingRestore(paths);

    final database = AppDatabase(
      DatabaseConnections.file(
        paths.databaseFile,
        logStatements: logStatements,
      ),
    );
    return _compose(
      database: database,
      clock: clock,
      paths: paths,
      restored: restored,
    );
  }

  /// Builds the same graph against a private in-memory database. Used by every
  /// database test so that no test can touch real business data.
  static Future<AppBootstrap> forTesting({
    Clock clock = const SystemClock(),
    AppDatabase? database,
    Directory? dataRoot,
  }) async {
    final db = database ?? AppDatabase(DatabaseConnections.memory());
    final paths = dataRoot == null ? null : await AppPaths.at(dataRoot);
    return _compose(database: db, clock: clock, paths: paths);
  }

  static Future<AppBootstrap> _compose({
    required AppDatabase database,
    required Clock clock,
    required AppPaths? paths,
    RestoreApplied? restored,
  }) async {
    final seeder = DatabaseSeeder(database, clock);
    await seeder.run();

    final settings = SettingsService(database, clock);
    await settings.load();

    return AppBootstrap._(
      paths: paths,
      database: database,
      clock: clock,
      settings: settings,
      audit: AuditService(database, clock),
      sequences: SequenceService(database, clock),
      seeder: seeder,
      needsFirstRunSetup: await seeder.needsFirstRunSetup(),
      restoreApplied: restored,
    );
  }

  /// The data directory. Throws when the graph was built for a test without
  /// one, which is a programming error rather than a user-facing failure.
  AppPaths get requirePaths {
    final value = paths;
    if (value == null) {
      throw StateError(
        'This AppBootstrap was created without a data directory. '
        'Pass dataRoot to AppBootstrap.forTesting when the code under test '
        'reads or writes files.',
      );
    }
    return value;
  }

  Future<void> dispose() => database.close();
}
