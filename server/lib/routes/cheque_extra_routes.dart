import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/constants/permissions.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/core/utils/money.dart';
import 'package:venvo_core/features/attachments/data/attachment_service.dart';
import 'package:venvo_core/features/payments/data/cheque_reminders.dart';

import '../auth/auth_middleware.dart';
import '../http/path_id.dart';
import '../http/responses.dart';

/// Cheque photos and cheque reminders.
Router chequeExtraRoutes({
  required AttachmentService attachments,
  required ChequeReminderService reminders,
  required ReminderSender sender,
  required void Function(String) log,
}) {
  final router = Router();

  /// Uploads a photo or scan of a cheque.
  ///
  /// The body is the file itself, not JSON — a phone photo base64-encoded
  /// into JSON would be a third larger for nothing. `?name=` carries the
  /// original file name, used only for display.
  router.post('/cheques/<id>/image', (Request request, String id) async {
    final bytes = await _readCapped(request, AttachmentService.maxBytes);
    final info = await attachments.attachChequeImage(
      request.session.user,
      chequeId: pathId(id),
      bytes: bytes,
      originalName: request.url.queryParameters['name'],
    );
    return Api.created({'attachment': info.toJson()});
  });

  router.get('/cheques/<id>/attachments', (Request request, String id) async {
    requirePermission(request, Permissions.paymentView, action: 'view cheques');
    final list = await attachments.listFor(EntityKind.cheque, pathId(id));
    return Api.ok({'attachments': list.map((a) => a.toJson()).toList()});
  });

  /// The file itself. Checked against the permission for the record it
  /// belongs to, inside the service.
  router.get('/attachments/<id>/content', (Request request, String id) async {
    final file = await attachments.read(request.session.user, pathId(id));
    return Response.ok(
      file.bytes,
      headers: {
        'content-type': file.info.mimeType,
        'content-length': '${file.bytes.length}',
        'content-disposition': 'inline; filename="${file.info.fileName}"',
        'cache-control': 'private, max-age=3600',
        'x-content-type-options': 'nosniff',
      },
    );
  });

  /// Every reminder attempt about one cheque, so the office can see whether
  /// the admin was told — and if not, why.
  router.get('/cheques/<id>/reminders', (Request request, String id) async {
    requirePermission(request, Permissions.paymentView, action: 'view cheques');
    final rows = await reminders.historyFor(pathId(id));
    return Api.ok({
      'reminders': [
        for (final row in rows)
          {
            'recipient': row.recipient,
            'attemptedAt': row.attemptedAt.toIso8601String(),
            'delivered': row.delivered,
            if (row.error != null) 'error': row.error,
          },
      ],
    });
  });

  /// Cheques that are coming due, as the reminder run sees them.
  router.get('/cheques/due', (Request request) async {
    requirePermission(request, Permissions.paymentView, action: 'view cheques');
    final due = await reminders.dueCheques();
    return Api.ok({
      'cheques': [
        for (final cheque in due)
          {
            'chequeId': cheque.chequeId,
            'chequeNumber': cheque.chequeNumber,
            'bankName': cheque.bankName,
            'chequeDate': cheque.chequeDate.toIso8601String(),
            'amount': cheque.amount.toJson(),
            'partyName': cheque.partyName,
            'receiptNumber': cheque.receiptNumber,
          },
      ],
    });
  });

  /// Runs the reminders now instead of waiting for the hourly run.
  router.post('/cheques/reminders/run', (Request request) async {
    requirePermission(
      request,
      Permissions.chequeManage,
      action: 'send cheque reminders',
    );
    final result = await reminders.run(sender);
    log('$result (run by ${request.session.user.username})');
    return Api.ok({'result': result.toJson()});
  });

  /// Sends one sample reminder to every configured number, so the admin can
  /// check the whole chain — number, credentials, template — before relying
  /// on it. Nothing is recorded against any real cheque.
  router.post('/settings/whatsapp/test', (Request request) async {
    requirePermission(
      request,
      Permissions.settingsManage,
      action: 'test WhatsApp reminders',
    );
    final numbers = await reminders.recipients();
    if (numbers.isEmpty) {
      throw const ValidationFailure(
        'Add a WhatsApp number in Settings first.',
        field: 'whatsapp.admin_numbers',
      );
    }
    if (!sender.isConfigured) {
      throw const BusinessRuleFailure(
        'WhatsApp is not configured on the server yet. Whoever runs the '
        'server needs to set WHATSAPP_TOKEN and WHATSAPP_PHONE_NUMBER_ID.',
        rule: 'whatsapp.not_configured',
      );
    }

    final sample = DueCheque(
      chequeId: 0,
      chequeNumber: '000000',
      bankName: 'Test Bank',
      chequeDate: DateTime.now().toUtc(),
      amount: const Money(100000),
      partyName: 'Test message from Venvo POS',
      receiptNumber: 'TEST',
    );
    final results = <Map<String, Object?>>[];
    for (final number in numbers) {
      try {
        await sender.send(to: number, cheque: sample);
        results.add({'to': number, 'delivered': true});
      } catch (error) {
        results.add({'to': number, 'delivered': false, 'error': '$error'});
      }
    }
    return Api.ok({'results': results});
  });

  return router;
}

/// Reads a request body, refusing it as soon as it passes [limit] bytes
/// rather than holding an arbitrarily large upload in memory first.
Future<Uint8List> _readCapped(Request request, int limit) async {
  final declared = request.contentLength;
  if (declared != null && declared > limit) {
    throw ValidationFailure(
      'The file is too large. The limit is ${limit ~/ (1024 * 1024)} MB.',
      field: 'file',
    );
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > limit) {
      throw ValidationFailure(
        'The file is too large. The limit is ${limit ~/ (1024 * 1024)} MB.',
        field: 'file',
      );
    }
  }
  return builder.takeBytes();
}
