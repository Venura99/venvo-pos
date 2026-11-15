import '../errors/failures.dart';

/// Decodes a list of models out of a response body.
///
/// A reply that is not shaped the way this client expects is a
/// [StorageFailure], not a crash: the usual cause is a client talking to a
/// server of a different version, and the user needs to be told that something
/// is wrong rather than shown a cast error.
List<T> decodeList<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, dynamic> json) fromJson,
) {
  final raw = json[key];
  if (raw is! List) {
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected a list under "$key", got ${raw.runtimeType}.',
    );
  }
  return [
    for (final entry in raw)
      if (entry is Map<String, dynamic>)
        fromJson(entry)
      else
        throw StorageFailure(
          'The server sent a reply this version cannot read.',
          details: 'An entry under "$key" was ${entry.runtimeType}.',
        ),
  ];
}

/// Decodes a list of plain strings, e.g. the distinct brands or designations
/// that feed a filter dropdown.
List<String> decodeStrings(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! List) {
    throw StorageFailure(
      'The server sent a reply this version cannot read.',
      details: 'Expected a list under "$key", got ${raw.runtimeType}.',
    );
  }
  return raw.cast<String>();
}

/// Reads the `id` a create endpoint returns.
int decodeId(Map<String, Object?> json) {
  final value = json['id'];
  if (value is int) return value;
  throw StorageFailure(
    'The server did not say which record it created.',
    details: 'Expected an integer "id", got ${value.runtimeType}.',
  );
}
