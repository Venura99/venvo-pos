import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

/// How the application opens SQLite.
///
/// The production connection runs the database on a background isolate so that
/// a long report query can never stutter the UI, and switches SQLite to
/// write-ahead logging, which is the right journal mode for a single-process
/// desktop application.
///
/// `PRAGMA foreign_keys` is deliberately *not* set here: it is a per-connection
/// setting and belongs in the database's `beforeOpen` callback, which drift
/// guarantees runs on every connection including the background isolate's.
class DatabaseConnections {
  const DatabaseConnections._();

  /// Opens the on-disk database used by the running application.
  static QueryExecutor file(File file, {bool logStatements = false}) {
    return NativeDatabase.createInBackground(
      file,
      logStatements: logStatements,
      setup: _applyPragmas,
    );
  }

  /// Opens a private in-memory database. Used by tests and by backup
  /// validation, which opens an archived file to integrity-check it before
  /// trusting it.
  static QueryExecutor memory({bool logStatements = false}) {
    return NativeDatabase.memory(
      logStatements: logStatements,
      setup: _applyPragmas,
    );
  }

  /// Opens an existing file read-only, for validating a backup archive without
  /// any risk of writing to it.
  static QueryExecutor readOnlyFile(File file) {
    return NativeDatabase.opened(
      sqlite3.open(file.path, mode: OpenMode.readOnly),
    );
  }

  static void _applyPragmas(Database db) {
    // Write-ahead logging: readers never block the writer.
    db.execute('PRAGMA journal_mode = WAL;');
    // Durable enough for a desktop app while still fast.
    db.execute('PRAGMA synchronous = NORMAL;');
    // Wait rather than fail if another connection holds the write lock.
    db.execute('PRAGMA busy_timeout = 5000;');
  }
}
