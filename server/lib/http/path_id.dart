import 'package:venvo_core/core/errors/failures.dart';

/// Parses a record id out of a URL path segment.
///
/// A non-numeric or non-positive id is the caller's mistake, so it becomes a
/// 422 rather than reaching a repository and coming back as "not found" —
/// which would be a different and misleading answer.
int pathId(String raw, {String field = 'id'}) {
  final value = int.tryParse(raw);
  if (value == null || value <= 0) {
    throw ValidationFailure('"$raw" is not a valid $field.', field: field);
  }
  return value;
}

/// Checks that the id in the body agrees with the one in the path.
///
/// Both carry it: the path because that is where a REST client expects it, the
/// body because the draft models already have the field and are reused from
/// the client's own forms. If they disagree, one of them is wrong and guessing
/// which would mean editing a record the caller did not name.
int requireMatchingId(int fromPath, int? fromBody) {
  if (fromBody != null && fromBody != fromPath) {
    throw ValidationFailure(
      'The id in the body ($fromBody) does not match the id in the '
      'address ($fromPath).',
      field: 'id',
    );
  }
  return fromPath;
}
