import 'failures.dart';

/// Throws [ValidationFailure] when [condition] does not hold.
void require(bool condition, String message, {String? field}) {
  if (!condition) throw ValidationFailure(message, field: field);
}

/// Throws [BusinessRuleFailure] when [condition] does not hold.
void requireRule(bool condition, String message, {String? rule}) {
  if (!condition) throw BusinessRuleFailure(message, rule: rule);
}

/// Returns [value] or throws [NotFoundFailure].
T requireFound<T>(T? value, String message) {
  if (value == null) throw NotFoundFailure(message);
  return value;
}

/// Trims a required text field and validates that something is left.
String requireText(String? value, String fieldLabel, {int maxLength = 200}) {
  final text = (value ?? '').trim();
  require(text.isNotEmpty, '$fieldLabel is required', field: fieldLabel);
  require(
    text.length <= maxLength,
    '$fieldLabel must be at most $maxLength characters',
    field: fieldLabel,
  );
  return text;
}
