import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/errors/failures.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/backup_models.dart';

/// A backup archive held on the server, as a client sees it.
///
/// Not `BackupArchive`: that class carries a `File`, which is a path on the
/// machine holding it. A client is on a different machine — and in a browser
/// has no file system at all — so it gets the name, the size and the manifest.
class ServerBackup {
  const ServerBackup({
    required this.fileName,
    required this.sizeBytes,
    required this.manifest,
  });

  factory ServerBackup.fromJson(Map<String, dynamic> json) {
    final manifest = json['manifest'];
    if (manifest is! Map<String, Object?>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected an object under "manifest".',
      );
    }
    return ServerBackup(
      fileName: json['fileName'] as String,
      sizeBytes: json['sizeBytes'] as int,
      manifest: BackupManifest.fromJson(manifest),
    );
  }

  final String fileName;
  final int sizeBytes;
  final BackupManifest manifest;
}

/// Backups of the server's database, over HTTP.
///
/// Listing, taking one now, and pruning. **Restoring is not here and will not
/// be**: on a server it replaces the database under every signed-in device at
/// once and needs the server stopped while the file is swapped. That belongs
/// to whoever runs the server, done at the server.
class BackupApi {
  const BackupApi(this._client);

  final ApiClient _client;

  Future<List<ServerBackup>> listBackups() async {
    final json = await _client.get('/api/v1/backups');
    return decodeList(json, 'backups', ServerBackup.fromJson);
  }

  Future<ServerBackup> createBackup(
    AuthenticatedUser actor, {
    String? note,
  }) async {
    final json = await _client.post(
      '/api/v1/backups',
      body: {if (note != null && note.trim().isNotEmpty) 'note': note.trim()},
    );
    final backup = json['backup'];
    if (backup is! Map<String, dynamic>) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected an object under "backup".',
      );
    }
    return ServerBackup.fromJson(backup);
  }

  /// Removes automatic archives beyond the retention count. Archives taken by
  /// hand are never removed.
  Future<int> pruneOldBackups(AuthenticatedUser actor) async {
    final json = await _client.post('/api/v1/backups/prune');
    final removed = json['removed'];
    return removed is int ? removed : 0;
  }
}
