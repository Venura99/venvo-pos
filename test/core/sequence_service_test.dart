import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/services/sequence_service.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestHarness harness;
  late SequenceService sequences;

  setUp(() async {
    harness = await TestHarness.create(at: DateTime.utc(2026, 11, 1, 9));
    sequences = harness.bootstrap.sequences;
  });

  tearDown(() => harness.dispose());

  group('document numbering', () {
    test('allocates the first number with prefix, year and padding', () async {
      final number = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.agentTransfer),
      );
      expect(number, 'TRF-2026-00001');
    });

    test('never repeats a number', () async {
      final issued = <String>[];
      for (var i = 0; i < 25; i++) {
        issued.add(
          await harness.db.transaction(
            () => sequences.nextNumber(SequenceKeys.shopInvoice),
          ),
        );
      }
      expect(issued.toSet().length, 25);
      expect(issued.first, 'SINV-2026-00001');
      expect(issued.last, 'SINV-2026-00025');
    });

    test('keeps separate counters per document type', () async {
      final transfer = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.agentTransfer),
      );
      final invoice = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.shopInvoice),
      );
      final payment = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.paymentReceipt),
      );

      expect(transfer, 'TRF-2026-00001');
      expect(invoice, 'SINV-2026-00001');
      expect(payment, 'PAY-2026-00001');
    });

    test('restarts the counter in a new year', () async {
      final first = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.agentTransfer),
      );
      expect(first, 'TRF-2026-00001');

      harness.clock.set(DateTime.utc(2027, 1, 2, 9));
      final next = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.agentTransfer),
      );
      expect(next, 'TRF-2027-00001');

      // The previous year's counter is untouched, so re-dating a document
      // cannot collide with an existing number.
      harness.clock.set(DateTime.utc(2026, 12, 31, 9));
      final backInOldYear = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.agentTransfer),
      );
      expect(backInOldYear, 'TRF-2026-00002');
    });

    test('supports a counter that never resets', () async {
      final number = await harness.db.transaction(
        () =>
            sequences.nextNumber(SequenceKeys.creditNote, resetsYearly: false),
      );
      expect(number, 'CN-00001');
    });

    test('a rolled-back transaction does not consume a number', () async {
      // This is the guarantee that matters: a document that fails half way
      // through must not burn its number, and must not leave the counter
      // ahead of reality.
      expect(await sequences.peek(SequenceKeys.agentTransfer), 1);

      await expectLater(
        harness.db.transaction(() async {
          await sequences.nextNumber(SequenceKeys.agentTransfer);
          throw StateError('posting failed after the number was allocated');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await sequences.peek(SequenceKeys.agentTransfer), 1);

      final afterFailure = await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.agentTransfer),
      );
      expect(afterFailure, 'TRF-2026-00001');
    });

    test('peek reports the next number without consuming it', () async {
      expect(await sequences.peek(SequenceKeys.purchase), 1);
      expect(await sequences.peek(SequenceKeys.purchase), 1);
      await harness.db.transaction(
        () => sequences.nextNumber(SequenceKeys.purchase),
      );
      expect(await sequences.peek(SequenceKeys.purchase), 2);
    });

    test('numbers keep sorting correctly past the padding width', () async {
      // Padding is for readability; it must not break ordering once the
      // counter outgrows it.
      for (var i = 0; i < 3; i++) {
        await harness.db.transaction(
          () => sequences.nextNumber(SequenceKeys.retailSale),
        );
      }
      final numbers = await harness.db
          .customSelect(
            'SELECT next_number FROM document_sequences '
            "WHERE sequence_key = 'RS'",
          )
          .getSingle();
      expect(numbers.data['next_number'], 4);
    });
  });

  group('transaction atomicity', () {
    test('a failure part way through rolls back every write', () async {
      // The same mechanism that protects document numbers protects both sides
      // of a stock transfer: nothing is left half-applied.
      Future<int> settingsCount() async {
        final row = await harness.db
            .customSelect('SELECT COUNT(*) AS c FROM settings')
            .getSingle();
        return row.data['c'] as int;
      }

      final before = await settingsCount();

      await expectLater(
        harness.db.transaction(() async {
          await harness.bootstrap.settings.setString('test.a', '1');
          await harness.bootstrap.settings.setString('test.b', '2');
          throw StateError('failed after two writes');
        }),
        throwsA(isA<StateError>()),
      );

      expect(await settingsCount(), before);
    });

    test('a nested failure rolls the whole outer transaction back', () async {
      Future<int> categoryCount() async {
        final row = await harness.db
            .customSelect('SELECT COUNT(*) AS c FROM categories')
            .getSingle();
        return row.data['c'] as int;
      }

      expect(await categoryCount(), 0);

      await expectLater(
        harness.db.transaction(() async {
          await _insertCategory(harness, 'Outer');
          await harness.db.transaction(() async {
            await _insertCategory(harness, 'Inner');
            throw StateError('inner failure');
          });
        }),
        throwsA(isA<StateError>()),
      );

      // Neither the inner nor the outer insert survives: a transfer that fails
      // on its second leg leaves no trace of its first.
      expect(await categoryCount(), 0);
    });
  });
}

Future<int> _insertCategory(TestHarness harness, String name) {
  final now = harness.clock.nowUtc().toIso8601String();
  return harness.db.customInsert(
    'INSERT INTO categories (name, sort_order, status, created_at, updated_at) '
    'VALUES (?, 0, ?, ?, ?)',
    variables: [
      Variable<String>(name),
      Variable<String>(EntityStatus.active.name),
      Variable<String>(now),
      Variable<String>(now),
    ],
  );
}
