import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/features/backup/data/backup_service.dart';
import 'package:venvo_core/features/backup/domain/backup_models.dart';

import '../auth/auth_middleware.dart';
import '../http/json_body.dart';
import '../http/responses.dart';

/// Backups of the server's database.
///
/// What is here: listing the archives on the server, taking one now, and
/// pruning old automatic ones. What is deliberately **not** here: restoring.
///
/// On the desktop build a restore replaced the database under the one person
/// using it. On a server it would replace the database under every signed-in
/// device at once, and it needs the server stopped while the file is swapped.
/// That is an operation for whoever runs the server, done at the server, with
/// everyone told first — not a button a till can reach over the network.
Router backupRoutes({required BackupService backups}) {
  final router = Router();

  router.get('/backups', (Request request) async {
    requirePermission(request, Permissions.backupRun, action: 'view backups');
    final archives = await backups.listBackups();
    return Api.ok({'backups': archives.map(_archive).toList()});
  });

  router.post('/backups', (Request request) async {
    // An empty body is fine here: the note is the only field and is optional.
    final body = await JsonBody.readOptional(request);
    final archive = await backups.createBackup(
      request.session.user,
      note: body.optionalString('note', maxLength: 300),
    );
    return Api.created({'backup': _archive(archive)});
  });

  /// Removes automatic archives beyond the retention count. Archives taken by
  /// hand are never removed by this.
  router.post('/backups/prune', (Request request) async {
    final removed = await backups.pruneOldBackups(request.session.user);
    return Api.ok({'removed': removed});
  });

  return router;
}

/// An archive as a client may see it: its name, size and manifest. The path
/// on the server's disk is not sent — a client has no use for it and it says
/// more about the server than a client needs to know.
Map<String, Object?> _archive(BackupArchive archive) => {
  'fileName': p.basename(archive.file.path),
  'sizeBytes': archive.sizeBytes,
  'manifest': archive.manifest.toJson(),
};
