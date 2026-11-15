import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/services/app_paths.dart';
import 'package:venvo_core/core/services/audit_service.dart';
import 'package:venvo_core/core/services/settings_service.dart';
import 'package:venvo_core/features/attachments/data/attachment_service.dart';

import '../auth/auth_middleware.dart';
import '../http/responses.dart';

/// The largest logo accepted. A logo is printed small on every document; a
/// bigger file only makes every PDF heavier.
const int maxLogoBytes = 2 * 1024 * 1024;

/// The company logo, stored as one file in the attachments folder so that it
/// is part of every backup.
class LogoStore {
  LogoStore(this._paths);

  final AppPaths _paths;

  Directory get _dir =>
      Directory(p.join(_paths.attachmentsDir.path, 'branding'));

  /// The stored logo, or null if none has been uploaded.
  File? current() {
    for (final ext in const ['png', 'jpg']) {
      final file = File(p.join(_dir.path, 'logo.$ext'));
      if (file.existsSync()) return file;
    }
    return null;
  }

  /// Replaces the logo. Returns its MIME type.
  ///
  /// Only PNG and JPEG: those are what the PDF documents can embed, and the
  /// type is decided by the file's contents, not by what the client claims.
  Future<String> save(Uint8List bytes) async {
    if (bytes.isEmpty) {
      throw const ValidationFailure('The file is empty.', field: 'file');
    }
    final type = AttachmentService.sniffType(bytes);
    if (type == null ||
        (type.mimeType != 'image/png' && type.mimeType != 'image/jpeg')) {
      throw const ValidationFailure(
        'The logo must be a PNG or JPEG image.',
        field: 'file',
      );
    }
    await _dir.create(recursive: true);
    // Written beside the old one first and then swapped in, so a failed
    // write never leaves the business without its previous logo.
    final target = File(p.join(_dir.path, 'logo.${type.extension}'));
    final temp = File('${target.path}.uploading');
    await temp.writeAsBytes(bytes, flush: true);
    final old = current();
    if (old != null && old.path != target.path) await old.delete();
    await temp.rename(target.path);
    return type.mimeType;
  }

  Future<bool> remove() async {
    final file = current();
    if (file == null) return false;
    await file.delete();
    return true;
  }

  static String mimeOf(File file) =>
      file.path.endsWith('.png') ? 'image/png' : 'image/jpeg';
}

/// The logo image itself. Public: the sign-in screen shows it before anyone
/// has signed in, and a logo is printed on every document the business sends
/// out, so it is not a secret.
Router brandingPublicRoutes({required LogoStore? logos}) {
  final router = Router();
  router.get('/branding/logo', (Request request) async {
    final file = logos?.current();
    // 204 rather than 404: a 404 here would fall through the cascade to the
    // signed-in pipeline and come back as "sign in to continue".
    if (file == null) return Response(204);
    final bytes = await file.readAsBytes();
    return Response.ok(
      bytes,
      headers: {
        'content-type': LogoStore.mimeOf(file),
        'content-length': '${bytes.length}',
        // Clients ask with ?v=<version>, so a changed logo is a new URL.
        'cache-control': 'public, max-age=300',
        'x-content-type-options': 'nosniff',
      },
    );
  });
  return router;
}

/// Uploading and removing the logo: the same permission as the rest of the
/// business details.
Router brandingAdminRoutes({
  required LogoStore logos,
  required SettingsService settings,
  required AuditService audit,
}) {
  final router = Router();

  router.put('/branding/logo', (Request request) async {
    final user = request.session.user;
    user.require(Permissions.settingsManage, action: 'change the logo');
    final bytes = await _readCapped(request, maxLogoBytes);
    final mime = await logos.save(bytes);
    final version = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    await settings.setString(
      SettingKeys.businessLogoVersion,
      version,
      updatedByUserId: user.id,
    );
    await settings.load();
    await audit.record(
      action: AuditAction.update,
      summary: 'Uploaded a new company logo ($mime, ${bytes.length} bytes).',
      userId: user.id,
      username: user.username,
      entityKind: EntityKind.setting,
    );
    return Api.ok({'logoVersion': version});
  });

  router.delete('/branding/logo', (Request request) async {
    final user = request.session.user;
    user.require(Permissions.settingsManage, action: 'remove the logo');
    final removed = await logos.remove();
    await settings.setString(
      SettingKeys.businessLogoVersion,
      '',
      updatedByUserId: user.id,
    );
    await settings.load();
    if (removed) {
      await audit.record(
        action: AuditAction.update,
        summary: 'Removed the company logo.',
        userId: user.id,
        username: user.username,
        entityKind: EntityKind.setting,
      );
    }
    return Api.ok({'removed': removed});
  });

  return router;
}

Future<Uint8List> _readCapped(Request request, int limit) async {
  final tooLarge = ValidationFailure(
    'The logo is too large. The limit is ${limit ~/ (1024 * 1024)} MB.',
    field: 'file',
  );
  final declared = request.contentLength;
  if (declared != null && declared > limit) throw tooLarge;
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > limit) throw tooLarge;
  }
  return builder.takeBytes();
}
