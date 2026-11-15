import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/permissions.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/errors/failures.dart';
import '../../../core/errors/guards.dart';
import '../../../core/services/app_paths.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/services/clock.dart';
import '../../authentication/domain/authenticated_user.dart';
import '../domain/attachment_models.dart';

/// Files attached to business records — for now, the photo of a cheque.
///
/// The bytes live on disk under the attachments folder, partitioned by year
/// and month, and only a reference is kept in the database. That keeps the
/// database small and quick to back up, and the backup archive already
/// includes the attachments folder, so nothing extra is needed to keep them
/// safe.
///
/// Everything uploaded is checked by its **content**, not by the name or the
/// type the device claimed: a phone can send any name it likes, and the server
/// is the only thing standing between that and the disk.
class AttachmentService {
  AttachmentService({
    required AppDatabase database,
    required AppPaths paths,
    required Clock clock,
    required AuditService audit,
  }) : _db = database,
       _paths = paths,
       _clock = clock,
       _audit = audit;

  final AppDatabase _db;
  final AppPaths _paths;
  final Clock _clock;
  final AuditService _audit;

  static const Uuid _uuid = Uuid();

  /// A cheque photo from a phone camera is typically 1–4 MB. Twelve leaves
  /// room for a high-resolution shot without letting one upload fill a disk.
  static const int maxBytes = 12 * 1024 * 1024;

  /// Attaches a photo or scan of a cheque.
  ///
  /// Allowed to whoever may record a payment (an agent taking the cheque at a
  /// shop) or manage cheques (the office), because those are the two people
  /// who have the cheque in their hands.
  Future<AttachmentInfo> attachChequeImage(
    AuthenticatedUser actor, {
    required int chequeId,
    required Uint8List bytes,
    String? originalName,
  }) async {
    if (!actor.can(Permissions.paymentRecord) &&
        !actor.can(Permissions.chequeManage)) {
      throw const PermissionFailure(
        'You do not have permission to attach a cheque image.',
        permission: Permissions.paymentRecord,
      );
    }
    requireFound(
      await (_db.select(
        _db.cheques,
      )..where((c) => c.id.equals(chequeId))).getSingleOrNull(),
      'That cheque no longer exists.',
    );

    return _store(
      actor,
      entityKind: EntityKind.cheque,
      entityId: chequeId,
      kind: AttachmentKind.chequeImage,
      bytes: bytes,
      originalName: originalName,
    );
  }

  /// Attachments on one record, newest first.
  Future<List<AttachmentInfo>> listFor(EntityKind kind, int entityId) async {
    final rows =
        await (_db.select(_db.attachments)
              ..where(
                (a) =>
                    a.entityKind.equalsValue(kind) &
                    a.entityId.equals(entityId),
              )
              ..orderBy([(a) => OrderingTerm.desc(a.uploadedAt)]))
            .get();
    return rows.map(_info).toList();
  }

  /// Reads one attachment's bytes, after checking the caller may see the
  /// record it belongs to.
  Future<({AttachmentInfo info, Uint8List bytes})> read(
    AuthenticatedUser actor,
    int attachmentId,
  ) async {
    final row = requireFound(
      await (_db.select(
        _db.attachments,
      )..where((a) => a.id.equals(attachmentId))).getSingleOrNull(),
      'That attachment no longer exists.',
    );
    actor.require(_viewPermissionFor(row.entityKind), action: 'view it');

    final file = _paths.attachmentFile(row.relativePath);
    if (!file.existsSync()) {
      throw StorageFailure(
        'The file for this attachment is missing from the server.',
        details: 'Expected at ${row.relativePath}.',
      );
    }
    return (info: _info(row), bytes: await file.readAsBytes());
  }

  Future<AttachmentInfo> _store(
    AuthenticatedUser actor, {
    required EntityKind entityKind,
    required int entityId,
    required AttachmentKind kind,
    required Uint8List bytes,
    String? originalName,
  }) async {
    if (bytes.isEmpty) {
      throw const ValidationFailure('The file is empty.', field: 'file');
    }
    if (bytes.length > maxBytes) {
      throw ValidationFailure(
        'The file is too large (${bytes.length ~/ (1024 * 1024)} MB). The '
        'limit is ${maxBytes ~/ (1024 * 1024)} MB.',
        field: 'file',
      );
    }
    final type = sniffType(bytes);
    if (type == null) {
      throw const ValidationFailure(
        'Only a photo (JPEG, PNG or WebP) or a PDF can be attached.',
        field: 'file',
      );
    }

    final now = _clock.nowUtc();
    // The stored name is generated, never taken from the upload: a name from
    // a device could carry a path, and must never decide where a file lands.
    final storedName = '${_uuid.v4()}.${type.extension}';
    final relative = _paths.attachmentRelativePath(
      when: now,
      storedFileName: storedName,
    );
    await _paths.ensureAttachmentDirFor(relative);
    final file = _paths.attachmentFile(relative);

    try {
      await file.writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (error) {
      throw StorageFailure(
        'The file could not be saved on the server.',
        details: '${error.path}: ${error.message}',
      );
    }

    final displayName = _cleanName(originalName, type.extension);
    try {
      final id = await _db
          .into(_db.attachments)
          .insert(
            AttachmentsCompanion.insert(
              entityKind: entityKind,
              entityId: entityId,
              kind: kind,
              fileName: displayName,
              relativePath: relative,
              mimeType: type.mimeType,
              byteSize: bytes.length,
              checksum: Value(sha256.convert(bytes).toString()),
              uploadedByUserId: Value(actor.id),
              uploadedAt: now,
            ),
          );

      await _audit.record(
        action: AuditAction.create,
        summary:
            'Attached $displayName (${type.mimeType}) to '
            '${entityKind.name} $entityId.',
        userId: actor.id,
        username: actor.username,
        entityKind: entityKind,
        entityId: entityId,
      );

      final row = await (_db.select(
        _db.attachments,
      )..where((a) => a.id.equals(id))).getSingle();
      return _info(row);
    } catch (_) {
      // The row did not go in, so the file would be an orphan nobody can
      // reach. Removed rather than left to fill the disk.
      if (file.existsSync()) await file.delete();
      rethrow;
    }
  }

  static String _viewPermissionFor(EntityKind kind) => switch (kind) {
    EntityKind.cheque || EntityKind.payment => Permissions.paymentView,
    EntityKind.expense => Permissions.expenseView,
    EntityKind.returnDocument => Permissions.returnView,
    EntityKind.invoice => Permissions.invoiceView,
    _ => Permissions.auditView,
  };

  static String _cleanName(String? name, String extension) {
    final base = (name ?? '').split(RegExp(r'[\\/]')).last.trim();
    final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._ -]'), '_');
    if (safe.isEmpty) return 'cheque.$extension';
    return safe.length <= 120 ? safe : safe.substring(safe.length - 120);
  }

  static AttachmentInfo _info(Attachment row) => AttachmentInfo(
    id: row.id,
    fileName: row.fileName,
    mimeType: row.mimeType,
    byteSize: row.byteSize,
    uploadedAt: row.uploadedAt,
  );

  /// Identifies a file from its first bytes. Null if it is not one of the
  /// accepted kinds.
  static ({String mimeType, String extension})? sniffType(Uint8List b) {
    bool starts(List<int> sig, [int offset = 0]) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (starts([0xFF, 0xD8, 0xFF])) {
      return (mimeType: 'image/jpeg', extension: 'jpg');
    }
    if (starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return (mimeType: 'image/png', extension: 'png');
    }
    if (starts([0x52, 0x49, 0x46, 0x46]) &&
        starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return (mimeType: 'image/webp', extension: 'webp');
    }
    if (starts([0x25, 0x50, 0x44, 0x46])) {
      return (mimeType: 'application/pdf', extension: 'pdf');
    }
    return null;
  }
}
