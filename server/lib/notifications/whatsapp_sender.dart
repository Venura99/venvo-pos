import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:venvo_core/features/payments/data/cheque_reminders.dart';

/// Sends cheque reminders through the WhatsApp Business Cloud API (Meta).
///
/// WhatsApp only lets a business start a conversation with an **approved
/// message template** — free text is refused unless the recipient wrote to the
/// business in the last 24 hours. So the reminder is a template, created once
/// in Meta's WhatsApp Manager, with five body variables filled in here:
///
///     Cheque reminder: {{1}} cheque no. {{2}} ({{3}}) for {{4}} is dated
///     {{5}}. Please arrange to bank it.
///
/// The credentials come from the server's environment, never from the
/// settings table: they would let anyone holding them send messages as the
/// business, and the settings are readable by every signed-in device.
class WhatsAppCloudSender implements ReminderSender {
  WhatsAppCloudSender({
    required this.accessToken,
    required this.phoneNumberId,
    required this.templateName,
    required this.templateLanguage,
    http.Client? client,
    this.apiVersion = 'v21.0',
  }) : _http = client ?? http.Client();

  /// Built from the environment. Missing credentials give a sender that
  /// reports itself unconfigured, rather than one that fails on every send.
  factory WhatsAppCloudSender.fromEnvironment(
    Map<String, String> env, {
    http.Client? client,
  }) => WhatsAppCloudSender(
    accessToken: env['WHATSAPP_TOKEN']?.trim() ?? '',
    phoneNumberId: env['WHATSAPP_PHONE_NUMBER_ID']?.trim() ?? '',
    templateName: _orDefault(env['WHATSAPP_TEMPLATE'], 'cheque_reminder'),
    templateLanguage: _orDefault(env['WHATSAPP_TEMPLATE_LANGUAGE'], 'en'),
    client: client,
  );

  final String accessToken;
  final String phoneNumberId;
  final String templateName;
  final String templateLanguage;
  final String apiVersion;
  final http.Client _http;

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final NumberFormat _amount = NumberFormat('#,##0.00');

  @override
  bool get isConfigured => accessToken.isNotEmpty && phoneNumberId.isNotEmpty;

  @override
  Future<void> send({required String to, required DueCheque cheque}) async {
    if (!isConfigured) {
      throw StateError('WhatsApp is not configured on the server.');
    }
    final response = await _http
        .post(
          Uri.https(
            'graph.facebook.com',
            '/$apiVersion/$phoneNumberId/messages',
          ),
          headers: {
            'authorization': 'Bearer $accessToken',
            'content-type': 'application/json',
          },
          body: jsonEncode(messageBody(to: to, cheque: cheque)),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Meta explains a refusal in the body (an unapproved template, a number
      // not on WhatsApp, an expired token). That explanation is what gets
      // stored, so somebody can act on it.
      throw StateError(
        'WhatsApp refused the message (${response.statusCode}): '
        '${_errorMessage(response.body)}',
      );
    }
  }

  /// The request body. Public so a test can check exactly what is sent.
  Map<String, Object?> messageBody({
    required String to,
    required DueCheque cheque,
  }) => {
    'messaging_product': 'whatsapp',
    'to': to,
    'type': 'template',
    'template': {
      'name': templateName,
      'language': {'code': templateLanguage},
      'components': [
        {
          'type': 'body',
          'parameters': [
            for (final value in [
              cheque.partyName,
              cheque.chequeNumber,
              cheque.bankName,
              'Rs. ${_amount.format(cheque.amount.cents / 100)}',
              _date.format(cheque.chequeDate.toLocal()),
            ])
              {'type': 'text', 'text': value},
          ],
        },
      ],
    },
  };

  static String _errorMessage(String body) {
    try {
      final json = jsonDecode(body);
      if (json is Map && json['error'] is Map) {
        final error = json['error'] as Map;
        return '${error['message'] ?? body}';
      }
    } on FormatException {
      // Not JSON; fall through to the raw text.
    }
    return body.length <= 300 ? body : body.substring(0, 300);
  }

  static String _orDefault(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }
}
