import 'dart:typed_data';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_decode.dart';
import '../../../core/api/revision_bus.dart';
import '../../../core/errors/failures.dart';
import '../../../core/utils/money.dart';
import '../../attachments/domain/attachment_models.dart';

/// One attempt to send a reminder about a cheque.
class ChequeReminderAttempt {
  const ChequeReminderAttempt({
    required this.recipient,
    required this.attemptedAt,
    required this.delivered,
    this.error,
  });

  factory ChequeReminderAttempt.fromJson(Map<String, dynamic> json) =>
      ChequeReminderAttempt(
        recipient: json['recipient'] as String,
        attemptedAt: DateTime.parse(json['attemptedAt'] as String),
        delivered: json['delivered'] as bool,
        error: json['error'] as String?,
      );

  final String recipient;
  final DateTime attemptedAt;
  final bool delivered;
  final String? error;
}

/// A cheque coming due, as the reminders see it.
class DueChequeView {
  const DueChequeView({
    required this.chequeId,
    required this.chequeNumber,
    required this.bankName,
    required this.chequeDate,
    required this.amount,
    required this.partyName,
    required this.receiptNumber,
  });

  factory DueChequeView.fromJson(Map<String, dynamic> json) => DueChequeView(
    chequeId: json['chequeId'] as int,
    chequeNumber: json['chequeNumber'] as String,
    bankName: json['bankName'] as String,
    chequeDate: DateTime.parse(json['chequeDate'] as String),
    amount: Money(json['amount'] as int),
    partyName: json['partyName'] as String,
    receiptNumber: json['receiptNumber'] as String,
  );

  final int chequeId;
  final String chequeNumber;
  final String bankName;
  final DateTime chequeDate;
  final Money amount;
  final String partyName;
  final String receiptNumber;
}

/// Cheque photos and WhatsApp reminders, over HTTP.
class ChequeExtrasApi {
  const ChequeExtrasApi(this._client);

  final ApiClient _client;

  /// Uploads a photo or scan of a cheque. [mimeType] is only a hint: the
  /// server decides what the file is from its content.
  Future<AttachmentInfo> uploadChequeImage({
    required int chequeId,
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    final json = await _client.postBytes(
      '/api/v1/cheques/$chequeId/image',
      bytes,
      contentType: mimeType,
      query: {'name': fileName},
      bumps: {ApiTopic.payments},
    );
    return AttachmentInfo.fromJson(_object(json, 'attachment'));
  }

  Future<List<AttachmentInfo>> chequeAttachments(int chequeId) async {
    final json = await _client.get('/api/v1/cheques/$chequeId/attachments');
    return decodeList(json, 'attachments', AttachmentInfo.fromJson);
  }

  Future<Uint8List> attachmentBytes(int attachmentId) async {
    final file = await _client.getBytes(
      '/api/v1/attachments/$attachmentId/content',
    );
    return Uint8List.fromList(file.bytes);
  }

  Future<List<ChequeReminderAttempt>> reminderHistory(int chequeId) async {
    final json = await _client.get('/api/v1/cheques/$chequeId/reminders');
    return decodeList(json, 'reminders', ChequeReminderAttempt.fromJson);
  }

  Future<List<DueChequeView>> dueCheques() async {
    final json = await _client.get('/api/v1/cheques/due');
    return decodeList(json, 'cheques', DueChequeView.fromJson);
  }

  /// Runs the reminders now. Returns the server's account of the run.
  Future<Map<String, Object?>> runReminders() async {
    final json = await _client.post('/api/v1/cheques/reminders/run');
    return _object(json, 'result');
  }

  /// Sends a sample reminder to every configured number. Returns one entry
  /// per number: whether it was delivered and, if not, why.
  Future<List<Map<String, Object?>>> sendTestReminder() async {
    final json = await _client.post('/api/v1/settings/whatsapp/test');
    final results = json['results'];
    if (results is! List) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: 'Expected a list under "results".',
      );
    }
    return results.cast<Map<String, Object?>>();
  }
}

Map<String, dynamic> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, dynamic>) return value;
  throw StorageFailure(
    'The server sent a reply this version cannot read.',
    details: 'Expected an object under "$key", got ${value.runtimeType}.',
  );
}
