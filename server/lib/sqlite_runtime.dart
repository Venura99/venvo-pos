import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';

/// Points the `sqlite3` package at a native library.
///
/// On Linux and macOS — which is where this server is meant to run — the
/// package finds the system `libsqlite3` on its own and this does nothing.
///
/// On Windows there is no `libsqlite3.so` to find. The desktop client gets its
/// copy from `sqlite3_flutter_libs`, which is a Flutter plugin and so is not
/// available to a pure-Dart server. Rather than ship a DLL beside the server
/// for a platform it will not be deployed on, it uses `winsqlite3.dll` — the
/// SQLite that Windows 10 and 11 include. That makes the server runnable for
/// development on the machine the client is built on, which is the only reason
/// it is wanted here. It is the same library the existing test suite has used
/// throughout.
void configureSqliteRuntime() {
  if (!Platform.isWindows) return;
  open.overrideFor(
    OperatingSystem.windows,
    () => DynamicLibrary.open('winsqlite3.dll'),
  );
}
