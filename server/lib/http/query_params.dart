import 'package:shelf/shelf.dart';
import 'package:venvo_core/core/errors/failures.dart';

/// Typed access to a request's query string.
///
/// List endpoints are `GET`, because reading a list is idempotent and should
/// stay safe to retry. That means filters arrive as text, and every accessor
/// here converts it and throws a [ValidationFailure] naming the parameter
/// rather than quietly falling back to a default. A filter silently ignored is
/// worse than one rejected: the caller gets a list that looks right and is
/// not.
class QueryParams {
  const QueryParams(this._params, [this._all = const {}]);

  factory QueryParams.of(Request request) =>
      QueryParams(request.url.queryParameters, request.url.queryParametersAll);

  final Map<String, String> _params;

  /// Every value for each key, for parameters that may repeat —
  /// `?type=warehouseToAgent&type=agentToShop`.
  final Map<String, List<String>> _all;

  bool has(String key) {
    final value = _params[key];
    return value != null && value.trim().isNotEmpty;
  }

  String string(String key, {String fallback = ''}) =>
      optionalString(key) ?? fallback;

  String? optionalString(String key) {
    final value = _params[key]?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  String requireString(String key) {
    final value = optionalString(key);
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    return value;
  }

  int requireInt(String key) {
    final value = optionalInt(key);
    if (value == null) {
      throw ValidationFailure('$key is required.', field: key);
    }
    return value;
  }

  int? optionalInt(String key) {
    final raw = optionalString(key);
    if (raw == null) return null;
    final value = int.tryParse(raw);
    if (value == null) {
      throw ValidationFailure(
        '$key must be a whole number, not "$raw".',
        field: key,
      );
    }
    return value;
  }

  bool boolean(String key, {bool fallback = false}) {
    final raw = optionalString(key)?.toLowerCase();
    if (raw == null) return fallback;
    return switch (raw) {
      '1' || 'true' || 'yes' => true,
      '0' || 'false' || 'no' => false,
      _ => throw ValidationFailure(
        '$key must be true or false, not "$raw".',
        field: key,
      ),
    };
  }

  /// Resolves an enum by its Dart name, listing the accepted values when it
  /// does not match — so a client that sends a stale value is told what the
  /// server will accept instead of silently getting the default sort order.
  T enumValue<T extends Enum>(
    String key,
    List<T> values, {
    required T fallback,
  }) {
    final raw = optionalString(key);
    if (raw == null) return fallback;
    for (final value in values) {
      if (value.name == raw) return value;
    }
    throw ValidationFailure(
      '$key must be one of ${values.map((v) => v.name).join(', ')}, '
      'not "$raw".',
      field: key,
    );
  }

  /// A set of enum values from a repeated parameter.
  ///
  /// An empty result means "no filter", which is what the domain filters
  /// expect. An unrecognised value is still rejected rather than dropped: a
  /// document-type filter the server silently ignored would show the user
  /// movements they asked to exclude.
  Set<T> enumSet<T extends Enum>(String key, List<T> values) {
    final raw = _all[key] ?? const <String>[];
    final result = <T>{};
    for (final entry in raw) {
      final trimmed = entry.trim();
      if (trimmed.isEmpty) continue;
      final match = values.where((v) => v.name == trimmed);
      if (match.isEmpty) {
        throw ValidationFailure(
          '$key must be one of ${values.map((v) => v.name).join(', ')}, '
          'not "$trimmed".',
          field: key,
        );
      }
      result.add(match.first);
    }
    return result;
  }

  DateTime? optionalUtcDate(String key) {
    final raw = optionalString(key);
    if (raw == null) return null;
    final value = DateTime.tryParse(raw);
    if (value == null) {
      throw ValidationFailure(
        '$key must be an ISO-8601 date, not "$raw".',
        field: key,
      );
    }
    return value.toUtc();
  }
}
