import 'package:intl/intl.dart';

/// Exact monetary value stored as a whole number of minor currency units
/// (cents). Floating point is never used for money anywhere in this
/// application: every amount travels as [Money] and is persisted as an
/// SQLite INTEGER.
///
/// Percentages are expressed in **basis points** (1 bps = 0.01%) so that a
/// discount such as 10% is an exact integer (1000 bps) and never a `double`.
class Money implements Comparable<Money> {
  const Money(this.cents);

  /// Wire format: the integer minor units, exactly as stored.
  ///
  /// `json_serializable` finds these two members by convention, so no field
  /// anywhere needs a converter annotation and no amount is ever rounded on
  /// its way across the network. Sending a decimal instead would reintroduce
  /// the floating-point error that storing cents as an integer exists to
  /// avoid.
  factory Money.fromJson(int cents) => Money(cents);

  int toJson() => cents;

  /// Builds a [Money] from major units, e.g. `Money.fromMajor(20000)` is
  /// Rs. 20,000.00.
  factory Money.fromMajor(int majorUnits) => Money(majorUnits * minorPerMajor);

  /// Parses user input such as `"20000"`, `"20,000.50"` or `"20 000.5"`.
  /// Returns `null` when the text is not a valid amount.
  static Money? tryParse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[,\s_]'), '').trim();
    if (cleaned.isEmpty) return null;
    final negative = cleaned.startsWith('-');
    final body = negative ? cleaned.substring(1) : cleaned;
    if (!RegExp(r'^\d*(\.\d*)?$').hasMatch(body) || body == '.') return null;

    final parts = body.split('.');
    final major = parts[0].isEmpty ? 0 : int.parse(parts[0]);
    var minor = 0;
    if (parts.length == 2 && parts[1].isNotEmpty) {
      final fraction = parts[1].length > 2
          ? parts[1].substring(0, 2)
          : parts[1].padRight(2, '0');
      minor = int.parse(fraction);
    }
    final value = major * minorPerMajor + minor;
    return Money(negative ? -value : value);
  }

  static const int minorPerMajor = 100;
  static const int bpsScale = 10000;
  static const Money zero = Money(0);

  final int cents;

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);

  /// Multiplies by a whole count, typically a quantity. Exact by construction.
  Money operator *(int count) => Money(cents * count);

  Money get abs => Money(cents.abs());

  /// Applies a percentage expressed in basis points, rounding half away from
  /// zero. `Money.fromMajor(20000).percentage(1000)` is exactly Rs. 2,000.00.
  Money percentage(int bps) => Money(_divideRounded(cents * bps, bpsScale));

  /// Splits this amount into [parts] shares whose sum is exactly this amount;
  /// the remainder cents are spread over the leading shares.
  List<Money> allocateEvenly(int parts) {
    if (parts <= 0) throw ArgumentError.value(parts, 'parts', 'must be > 0');
    final base = cents ~/ parts;
    var remainder = cents - base * parts;
    final step = remainder.isNegative ? -1 : 1;
    return List<Money>.generate(parts, (_) {
      var share = base;
      if (remainder != 0) {
        share += step;
        remainder -= step;
      }
      return Money(share);
    });
  }

  /// Integer division rounding half away from zero.
  ///
  /// Exposed because inventory valuation needs the same rounding rule when it
  /// recomputes a weighted average cost, and having two rounding rules in one
  /// application is how cents go missing.
  static int divideRounded(int numerator, int denominator) =>
      _divideRounded(numerator, denominator);

  static int _divideRounded(int numerator, int denominator) {
    final negative = (numerator < 0) != (denominator < 0);
    final n = numerator.abs();
    final d = denominator.abs();
    final magnitude = (2 * n + d) ~/ (2 * d);
    return negative ? -magnitude : magnitude;
  }

  /// The share of [total] that this amount represents, in basis points.
  int bpsOf(Money total) =>
      total.isZero ? 0 : _divideRounded(cents * bpsScale, total.cents);

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  bool operator <(Money other) => cents < other.cents;
  bool operator <=(Money other) => cents <= other.cents;
  bool operator >(Money other) => cents > other.cents;
  bool operator >=(Money other) => cents >= other.cents;

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => formatted();

  /// `Rs. 18,000.00`
  String formatted({String symbol = 'Rs. ', bool withSymbol = true}) {
    final formatter = NumberFormat('#,##0.00', 'en_US');
    final text = formatter.format(cents / minorPerMajor);
    return withSymbol ? '$symbol$text' : text;
  }

  /// `18,000.00` — for table cells and exports.
  String get plain => formatted(withSymbol: false);
}

extension MoneyIterable on Iterable<Money> {
  Money get sum => fold(Money.zero, (a, b) => a + b);
}

/// Formats a basis-point percentage for display: `1000` -> `10%`,
/// `1250` -> `12.5%`.
String formatBps(int bps) {
  final percent = bps / 100;
  final text = percent == percent.roundToDouble()
      ? percent.toStringAsFixed(0)
      : percent.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return '$text%';
}
