import 'package:flutter_test/flutter_test.dart';
import 'package:venvo_core/core/utils/money.dart';

void main() {
  group('Money', () {
    test('stores and formats exact minor units', () {
      expect(Money.fromMajor(20000).cents, 2000000);
      expect(Money.fromMajor(20000).formatted(), 'Rs. 20,000.00');
      expect(const Money(1850).formatted(), 'Rs. 18.50');
      expect(const Money(-1850).formatted(), 'Rs. -18.50');
      expect(const Money(2000000).plain, '20,000.00');
    });

    test('addition and subtraction are exact', () {
      final total = Money.fromMajor(20000) - Money.fromMajor(10000);
      expect(total, Money.fromMajor(10000));
      expect(total - Money.fromMajor(5000), Money.fromMajor(5000));
    });

    test('quantity multiplication is exact', () {
      // 50 units at Rs. 3,000.00 is Rs. 150,000.00 - the brief's transfer
      // example.
      expect(Money.fromMajor(3000) * 50, Money.fromMajor(150000));
    });

    group('percentage discounts', () {
      test('a 10% discount on Rs. 20,000 is exactly Rs. 2,000', () {
        final gross = Money.fromMajor(20000);
        final discount = gross.percentage(1000);
        expect(discount, Money.fromMajor(2000));
        expect(gross - discount, Money.fromMajor(18000));
      });

      test('fractional percentages stay exact', () {
        // 12.5% of Rs. 1,000.00 is Rs. 125.00
        expect(Money.fromMajor(1000).percentage(1250), Money.fromMajor(125));
      });

      test('rounds half away from zero rather than truncating', () {
        // 10% of Rs. 0.05 is 0.5 cents, which must round to 1 cent, not 0.
        expect(const Money(5).percentage(1000), const Money(1));
        // And symmetrically for a negative amount.
        expect(const Money(-5).percentage(1000), const Money(-1));
      });

      test('zero and full discounts behave', () {
        final gross = Money.fromMajor(20000);
        expect(gross.percentage(0), Money.zero);
        expect(gross.percentage(10000), gross);
      });
    });

    group('bpsOf', () {
      test('reports the effective rate of a discount', () {
        expect(Money.fromMajor(2000).bpsOf(Money.fromMajor(20000)), 1000);
        expect(Money.fromMajor(125).bpsOf(Money.fromMajor(1000)), 1250);
      });

      test('is zero against a zero total rather than dividing by zero', () {
        expect(Money.fromMajor(100).bpsOf(Money.zero), 0);
      });
    });

    group('allocateEvenly', () {
      test('splits without losing or inventing a cent', () {
        final shares = const Money(1000).allocateEvenly(3);
        expect(shares.length, 3);
        expect(shares.sum, const Money(1000));
        expect(shares.map((m) => m.cents).toList(), [334, 333, 333]);
      });

      test('handles exact divisions', () {
        final shares = const Money(900).allocateEvenly(3);
        expect(shares.map((m) => m.cents).toList(), [300, 300, 300]);
      });

      test('handles negative amounts', () {
        final shares = const Money(-1000).allocateEvenly(3);
        expect(shares.sum, const Money(-1000));
      });

      test('rejects a non-positive part count', () {
        expect(() => const Money(100).allocateEvenly(0), throwsArgumentError);
      });
    });

    group('tryParse', () {
      test('accepts the shapes a user types', () {
        expect(Money.tryParse('20000'), Money.fromMajor(20000));
        expect(Money.tryParse('20,000.50'), const Money(2000050));
        expect(Money.tryParse(' 20 000 '), Money.fromMajor(20000));
        expect(Money.tryParse('0.5'), const Money(50));
        expect(Money.tryParse('.75'), const Money(75));
        expect(Money.tryParse('-12.34'), const Money(-1234));
      });

      test('truncates beyond two decimal places rather than rounding up', () {
        // Entering a third decimal is a data-entry slip; the stored value must
        // never silently exceed what was typed.
        expect(Money.tryParse('10.999'), const Money(1099));
      });

      test('rejects what is not an amount', () {
        expect(Money.tryParse(''), isNull);
        expect(Money.tryParse('abc'), isNull);
        expect(Money.tryParse('.'), isNull);
        expect(Money.tryParse('1.2.3'), isNull);
      });
    });

    test('comparison operators order amounts', () {
      expect(Money.fromMajor(100) > Money.fromMajor(50), isTrue);
      expect(Money.fromMajor(50) <= Money.fromMajor(50), isTrue);
      final amounts = [
        Money.fromMajor(300),
        Money.fromMajor(100),
        Money.fromMajor(200),
      ]..sort();
      expect(amounts.first, Money.fromMajor(100));
      expect(amounts.last, Money.fromMajor(300));
    });

    test('sum over an iterable is exact', () {
      expect(
        [Money.fromMajor(100), Money.fromMajor(250), const Money(50)].sum,
        const Money(35050),
      );
    });
  });

  group('formatBps', () {
    test('renders whole and fractional percentages readably', () {
      expect(formatBps(1000), '10%');
      expect(formatBps(1250), '12.5%');
      expect(formatBps(0), '0%');
      expect(formatBps(10000), '100%');
    });
  });
}
