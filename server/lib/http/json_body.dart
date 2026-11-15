import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:shelf/shelf.dart';
import 'package:venvo_core/core/errors/failures.dart';

/// A decoded JSON request body with validating accessors.
///
/// Every accessor throws a [ValidationFailure] naming the field, which the
/// error middleware turns into a 422 the client can attach to the right input.
/// The point is that a missing or mistyped field can never arrive at a
/// business service as a null or a silently coerced value.
class JsonBody {
  const JsonBody(this._data);

  final Map<String, Object?> _data;

  static Future<JsonBody> read(Request request) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) {
      throw const ValidationFailure(
        'The request had no body.',
        details: 'A JSON object was expected.',
      );
    }
    return _parse(raw);
  }

  /// For endpoints where every field is optional: an empty body is read as an
  /// empty object rather than refused.
  static Future<JsonBody> readOptional(Request request) async {
    final raw = await request.readAsString();
    return raw.trim().isEmpty ? const JsonBody({}) : _parse(raw);
  }

  static JsonBody _parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      throw ValidationFailure(
        'The request body was not valid JSON.',
        details: error.message,
      );
    }

    if (decoded is! Map<String, Object?>) {
      throw const ValidationFailure('The request body was not a JSON object.');
    }
    return JsonBody(decoded);
  }

  bool has(String key) => _data[key] != null;

  /// Decodes the body into a domain model with its generated `fromJson`.
  ///
  /// The models are generated with `checked: true`, so a field of the wrong
  /// type or a missing required one throws [CheckedFromJsonException] naming
  /// the field. Translating that here is what keeps a malformed request a 422
  /// the client can act on, instead of an uncaught cast error that would
  /// surface as a 500 and look like a server fault.
  ///
  /// Usage: `body.decode(ProductDraft.fromJson)`.
  T decode<T>(T Function(Map<String, dynamic> json) fromJson) {
    try {
      return fromJson(_data);
    } on CheckedFromJsonException catch (error) {
      throw ValidationFailure(
        error.message ?? '${error.key} is not valid.',
        details: 'Field "${error.key}" of ${error.className}.',
        field: error.key,
      );
    } on TypeError catch (error) {
      // A cast that `checked` did not cover. Still the request's fault, so
      // still a 422 — but without pretending to know which field it was.
      throw ValidationFailure(
        'The request body did not have the expected shape.',
        details: '$error',
      );
    }
  }

  String requireString(String key, {int? maxLength}) {
    final value = _data[key];
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (value is! String) {
      throw ValidationFailure('$key must be text.', field: key);
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (maxLength != null && trimmed.length > maxLength) {
      throw ValidationFailure(
        '$key must be $maxLength characters or fewer.',
        field: key,
      );
    }
    return trimmed;
  }

  /// A password, taken verbatim.
  ///
  /// Deliberately not trimmed and not length-checked here: trimming would
  /// silently change what the user typed, and the rules about what makes an
  /// acceptable password belong to `AuthRepository`, which already has them
  /// and already tests them.
  String requireSecret(String key) {
    final value = _data[key];
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (value is! String || value.isEmpty) {
      throw ValidationFailure('$key is required.', field: key);
    }
    return value;
  }

  String? optionalString(String key, {int? maxLength}) {
    final value = _data[key];
    if (value == null) return null;
    if (value is! String) {
      throw ValidationFailure('$key must be text.', field: key);
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    if (maxLength != null && trimmed.length > maxLength) {
      return trimmed.substring(0, maxLength);
    }
    return trimmed;
  }

  int requireInt(String key) {
    final value = _data[key];
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (value is int) return value;
    // JSON numbers arrive as double when written with a decimal point. An
    // identifier or a quantity with a fractional part is a mistake worth
    // reporting, not rounding away.
    if (value is double && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw ValidationFailure('$key must be a whole number.', field: key);
  }

  int? optionalInt(String key) => _data[key] == null ? null : requireInt(key);

  /// A flag that must be present. For a switch such as "active", an absent
  /// value has no safe default: guessing either way changes something.
  bool requireBool(String key) {
    final value = _data[key];
    if (value is bool) return value;
    throw ValidationFailure(
      value == null ? '$key is required.' : '$key must be true or false.',
      field: key,
    );
  }

  /// A flag, with [fallback] when it is absent.
  ///
  /// A present value of the wrong type is rejected rather than coerced: a
  /// string `"false"` quietly read as true is the kind of thing that turns
  /// "include zero stock" into the opposite of what was asked for.
  bool boolean(String key, {bool fallback = false}) {
    final value = _data[key];
    if (value == null) return fallback;
    if (value is bool) return value;
    throw ValidationFailure('$key must be true or false.', field: key);
  }

  /// A list of record ids, every entry checked.
  ///
  /// One bad entry rejects the whole request rather than being skipped: a bulk
  /// operation that quietly acted on four of the five things it was given, and
  /// reported success, is how records get missed.
  List<int> requireIntList(String key) {
    final raw = requireList(key);
    final values = <int>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is int) {
        values.add(entry);
      } else if (entry is double && entry == entry.roundToDouble()) {
        values.add(entry.toInt());
      } else {
        throw ValidationFailure(
          '$key[$index] is not a whole number.',
          field: key,
        );
      }
    }
    return values;
  }

  /// A map keyed by record id, whose values may be null.
  ///
  /// JSON object keys are always text, so they are parsed back to the integers
  /// the domain uses. A null value is meaningful and preserved: on a stock
  /// count sheet it means "this line has not been counted yet", which is a
  /// different fact from a counted zero.
  Map<int, int?> requireNullableIntMap(String key) {
    final raw = _data[key];
    if (raw == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (raw is! Map) {
      throw ValidationFailure('$key must be an object.', field: key);
    }
    final values = <int, int?>{};
    raw.forEach((rawKey, rawValue) {
      final id = int.tryParse('$rawKey');
      if (id == null) {
        throw ValidationFailure(
          '$key has the key "$rawKey", which is not a record id.',
          field: key,
        );
      }
      if (rawValue == null) {
        values[id] = null;
      } else if (rawValue is int) {
        values[id] = rawValue;
      } else if (rawValue is double && rawValue == rawValue.roundToDouble()) {
        values[id] = rawValue.toInt();
      } else {
        throw ValidationFailure(
          '$key["$rawKey"] must be a whole number or null.',
          field: key,
        );
      }
    });
    return values;
  }

  /// An ISO-8601 instant, normalised to UTC.
  ///
  /// Every stored timestamp in this system is UTC; the client converts for
  /// display. Accepting a local-time string and storing it unconverted is how
  /// a document ends up dated the previous day.
  DateTime? optionalUtcDate(String key) {
    final value = _data[key];
    if (value == null) return null;
    if (value is! String) {
      throw ValidationFailure('$key must be an ISO-8601 date.', field: key);
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw ValidationFailure(
        '$key is "$value", which is not an ISO-8601 date.',
        field: key,
      );
    }
    return parsed.toUtc();
  }

  /// An enum, by its Dart name.
  ///
  /// An unrecognised value is rejected with the accepted list rather than
  /// falling back to a default — a discount type quietly read as "none" would
  /// bill the customer the wrong amount.
  T enumValue<T extends Enum>(String key, List<T> values) {
    final raw = requireString(key);
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw ValidationFailure(
      '$key must be one of ${values.map((v) => v.name).join(', ')}, '
      'not "$raw".',
      field: key,
    );
  }

  /// Decodes a list of models under [key] with their generated `fromJson`.
  ///
  /// An entry of the wrong shape rejects the whole request. For a list of
  /// payment allocations that is the only safe behaviour: applying three of
  /// the four the caller sent, and reporting success, would leave an invoice
  /// looking settled when it is not.
  List<T> decodeEach<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final raw = requireList(key);
    final values = <T>[];
    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map<String, dynamic>) {
        throw ValidationFailure('$key[$index] is not an object.', field: key);
      }
      try {
        values.add(fromJson(entry));
      } on CheckedFromJsonException catch (error) {
        throw ValidationFailure(
          error.message ?? '$key[$index] is not valid.',
          details: 'Field "${error.key}" of ${error.className}.',
          field: key,
        );
      }
    }
    return values;
  }

  /// Decodes an optional nested object with its generated `fromJson`.
  ///
  /// Absent is null. Present but malformed is a 422 naming the field, for the
  /// same reason as [decode]: a bad request must not surface as a 500.
  T? decodeOptional<T>(
    String key,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    final value = _data[key];
    if (value == null) return null;
    if (value is! Map<String, dynamic>) {
      throw ValidationFailure('$key must be an object.', field: key);
    }
    try {
      return fromJson(value);
    } on CheckedFromJsonException catch (error) {
      throw ValidationFailure(
        error.message ?? '$key is not valid.',
        details: 'Field "${error.key}" of ${error.className}.',
        field: key,
      );
    }
  }

  /// A nested JSON object, whose values are left as they came so the caller
  /// can check each one's type against what that particular key expects.
  Map<String, Object?> requireMap(String key) {
    final value = _data[key];
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (value is! Map<String, Object?>) {
      throw ValidationFailure('$key must be an object.', field: key);
    }
    return value;
  }

  List<Object?> requireList(String key) {
    final value = _data[key];
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    if (value is! List) {
      throw ValidationFailure('$key must be a list.', field: key);
    }
    return value;
  }
}
