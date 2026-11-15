import 'package:drift/drift.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/app_database.dart';
import '../../../core/enums/app_enums.dart';
import '../../../core/services/clock.dart';
import '../../../core/services/settings_service.dart';
import '../../../core/utils/money.dart';

/// A cheque that is coming due and has not been banked and cleared yet.
class DueCheque {
  const DueCheque({
    required this.chequeId,
    required this.chequeNumber,
    required this.bankName,
    required this.chequeDate,
    required this.amount,
    required this.partyName,
    required this.receiptNumber,
  });

  final int chequeId;
  final String chequeNumber;
  final String bankName;
  final DateTime chequeDate;
  final Money amount;
  final String partyName;
  final String receiptNumber;
}

/// Sends one reminder. Implemented by the server against the WhatsApp API;
/// a test supplies its own.
///
/// Throws to report a failure, with a message worth keeping: it is stored
/// against the attempt so somebody can see why a reminder did not arrive.
abstract class ReminderSender {
  /// True when the sender has what it needs to send anything at all.
  bool get isConfigured;

  Future<void> send({required String to, required DueCheque cheque});
}

/// What one run of the reminders did. Logged by the server, and returned by
/// the endpoint that runs them on demand, so a run is never a black box.
class ReminderRunResult {
  const ReminderRunResult({
    required this.due,
    required this.sent,
    required this.failed,
    required this.skipped,
    this.notConfiguredReason,
  });

  final int due;
  final int sent;
  final int failed;
  final int skipped;

  /// Set when nothing could be sent at all: no numbers in settings, or the
  /// WhatsApp credentials missing on the server.
  final String? notConfiguredReason;

  Map<String, Object?> toJson() => {
    'due': due,
    'sent': sent,
    'failed': failed,
    'skipped': skipped,
    if (notConfiguredReason != null) 'notConfigured': notConfiguredReason,
  };

  @override
  String toString() =>
      'cheque reminders: $due due, $sent sent, $failed failed, '
      '$skipped already sent or given up'
      '${notConfiguredReason == null ? '' : ' — NOT SENT: $notConfiguredReason'}';
}

/// Finds cheques coming due and sends a WhatsApp reminder about each one to
/// the numbers in settings — once per cheque per number.
///
/// A cheque counts while it is still `pending` or `deposited`: once it has
/// cleared, bounced, been returned or cancelled there is nothing left to be
/// reminded of. A cheque whose date has already passed while still pending is
/// included rather than skipped — a late reminder is worth more than none if
/// the server was down on the day.
class ChequeReminderService {
  ChequeReminderService({
    required AppDatabase database,
    required SettingsService settings,
    required Clock clock,
  }) : _db = database,
       _settings = settings,
       _clock = clock;

  final AppDatabase _db;
  final SettingsService _settings;
  final Clock _clock;

  /// After this many failed attempts to one number, the cheque is left alone
  /// for that number rather than retried every hour for ever.
  static const int maxAttempts = 5;

  /// The numbers reminders go to, cleaned to digits only.
  Future<List<String>> recipients() async {
    final raw = await _settings.getString(SettingKeys.whatsappAdminNumbers);
    return parseNumbers(raw);
  }

  Future<int> daysBefore() =>
      _settings.getInt(SettingKeys.chequeReminderDaysBefore, fallback: 1);

  /// Cheques due on or before the end of the day [daysBefore] days from now.
  Future<List<DueCheque>> dueCheques({int? withinDays}) async {
    final days = withinDays ?? await daysBefore();
    final cutoff = _clock.endOfLocalDay(
      _clock.nowUtc().add(Duration(days: days)),
    );

    final rows = await _db
        .customSelect(
          '''
      SELECT c.id, c.cheque_number, c.bank_name, c.cheque_date,
             p.amount_cents, p.receipt_number,
             COALESCE(s.name, a.name, p.payer_name, 'Unknown') AS party
      FROM cheques c
      JOIN payments p ON p.id = c.payment_id
      LEFT JOIN shops s ON s.id = p.shop_id
      LEFT JOIN agents a ON a.id = p.agent_id
      WHERE c.status IN (?, ?)
        AND p.status != ?
        AND c.cheque_date <= ?
      ORDER BY c.cheque_date, c.id
      ''',
          variables: [
            Variable.withString(ChequeStatus.pending.name),
            Variable.withString(ChequeStatus.deposited.name),
            Variable.withString(PaymentStatus.cancelled.name),
            Variable.withDateTime(cutoff),
          ],
          readsFrom: {_db.cheques, _db.payments, _db.shops, _db.agents},
        )
        .get();

    return [
      for (final row in rows)
        DueCheque(
          chequeId: row.read<int>('id'),
          chequeNumber: row.read<String>('cheque_number'),
          bankName: row.read<String>('bank_name'),
          chequeDate: row.read<DateTime>('cheque_date'),
          amount: Money(row.read<int>('amount_cents')),
          partyName: row.read<String>('party'),
          receiptNumber: row.read<String>('receipt_number'),
        ),
    ];
  }

  /// Sends every reminder that is due and not yet delivered.
  Future<ReminderRunResult> run(ReminderSender sender) async {
    final numbers = await recipients();
    final due = await dueCheques();

    String? notConfigured;
    if (numbers.isEmpty) {
      notConfigured = 'no WhatsApp number is set in Settings';
    } else if (!sender.isConfigured) {
      notConfigured = 'WhatsApp is not configured on the server';
    }
    if (notConfigured != null) {
      return ReminderRunResult(
        due: due.length,
        sent: 0,
        failed: 0,
        skipped: 0,
        notConfiguredReason: due.isEmpty ? null : notConfigured,
      );
    }

    var sent = 0;
    var failed = 0;
    var skipped = 0;
    for (final cheque in due) {
      for (final number in numbers) {
        final history = await _attempts(cheque.chequeId, number);
        if (history.any((a) => a.delivered) || history.length >= maxAttempts) {
          skipped++;
          continue;
        }
        try {
          await sender.send(to: number, cheque: cheque);
          await _record(cheque.chequeId, number, delivered: true);
          sent++;
        } catch (error) {
          await _record(
            cheque.chequeId,
            number,
            delivered: false,
            error: '$error',
          );
          failed++;
        }
      }
    }
    return ReminderRunResult(
      due: due.length,
      sent: sent,
      failed: failed,
      skipped: skipped,
    );
  }

  /// Every attempt about one cheque, newest first — for the cheque's detail.
  Future<List<ChequeReminder>> historyFor(int chequeId) =>
      (_db.select(_db.chequeReminders)
            ..where((r) => r.chequeId.equals(chequeId))
            ..orderBy([(r) => OrderingTerm.desc(r.attemptedAt)]))
          .get();

  Future<List<ChequeReminder>> _attempts(int chequeId, String number) =>
      (_db.select(_db.chequeReminders)..where(
            (r) => r.chequeId.equals(chequeId) & r.recipient.equals(number),
          ))
          .get();

  Future<void> _record(
    int chequeId,
    String number, {
    required bool delivered,
    String? error,
  }) => _db
      .into(_db.chequeReminders)
      .insert(
        ChequeRemindersCompanion.insert(
          chequeId: chequeId,
          recipient: number,
          attemptedAt: _clock.nowUtc(),
          delivered: delivered,
          error: Value(
            error == null
                ? null
                : (error.length <= 500 ? error : error.substring(0, 500)),
          ),
        ),
      );

  /// Splits a settings value into numbers, keeping digits only.
  ///
  /// A local Sri Lankan number entered as `0771234567` is turned into the
  /// international `94771234567` WhatsApp needs, since that is how numbers are
  /// usually written here; anything else is used as entered.
  static List<String> parseNumbers(String? raw) {
    final numbers = <String>[];
    // Split on commas, semicolons and line breaks only — never on spaces,
    // because "077 123 4567" is how a number is usually typed, and splitting
    // it would throw the whole number away.
    for (final part in (raw ?? '').split(RegExp(r'[,;\n]+'))) {
      var digits = part.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) continue;
      if (digits.length == 10 && digits.startsWith('0')) {
        digits = '94${digits.substring(1)}';
      }
      if (digits.length >= 8 && !numbers.contains(digits)) numbers.add(digits);
    }
    return numbers;
  }
}
