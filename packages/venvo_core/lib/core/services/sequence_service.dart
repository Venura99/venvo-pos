import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'clock.dart';

/// Allocates unique, human-readable document numbers.
///
/// The counter row is read with `SELECT ... FOR UPDATE` semantics by virtue of
/// running inside the caller's transaction: because the increment and the
/// document insert share one transaction, two concurrent operations can never
/// be handed the same number, and a rolled-back document does not burn one.
///
/// Numbers look like `TRF-2026-00014`: prefix, period, zero-padded counter.
class SequenceService {
  const SequenceService(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  /// Reserves the next number for [sequenceKey].
  ///
  /// Must be called inside an open transaction - the same one that inserts the
  /// document. Calling it outside a transaction would allocate a number that
  /// could be lost if the caller then failed.
  Future<String> nextNumber(
    String sequenceKey, {
    bool resetsYearly = true,
    String? prefixOverride,
  }) async {
    final now = _clock.nowUtc();
    final periodKey = resetsYearly ? now.toLocal().year.toString() : 'ALL';
    final prefix = prefixOverride ?? sequenceKey;

    final existing =
        await (_db.select(_db.documentSequences)..where(
              (row) =>
                  row.sequenceKey.equals(sequenceKey) &
                  row.periodKey.equals(periodKey),
            ))
            .getSingleOrNull();

    if (existing == null) {
      await _db
          .into(_db.documentSequences)
          .insert(
            DocumentSequencesCompanion.insert(
              sequenceKey: sequenceKey,
              periodKey: periodKey,
              prefix: prefix,
              nextNumber: const Value(2),
              updatedAt: now,
            ),
          );
      return _format(prefix, periodKey, 1, 5);
    }

    final allocated = existing.nextNumber;
    await (_db.update(_db.documentSequences)..where(
          (row) =>
              row.sequenceKey.equals(sequenceKey) &
              row.periodKey.equals(periodKey),
        ))
        .write(
          DocumentSequencesCompanion(
            nextNumber: Value(allocated + 1),
            updatedAt: Value(now),
          ),
        );
    return _format(existing.prefix, periodKey, allocated, existing.padding);
  }

  static String _format(
    String prefix,
    String periodKey,
    int number,
    int padding,
  ) {
    final body = number.toString().padLeft(padding, '0');
    return periodKey == 'ALL' ? '$prefix-$body' : '$prefix-$periodKey-$body';
  }

  /// Current value of a counter without consuming it. For diagnostics only.
  Future<int> peek(String sequenceKey, {bool resetsYearly = true}) async {
    final periodKey = resetsYearly
        ? _clock.nowUtc().toLocal().year.toString()
        : 'ALL';
    final row =
        await (_db.select(_db.documentSequences)..where(
              (r) =>
                  r.sequenceKey.equals(sequenceKey) &
                  r.periodKey.equals(periodKey),
            ))
            .getSingleOrNull();
    return row?.nextNumber ?? 1;
  }
}
