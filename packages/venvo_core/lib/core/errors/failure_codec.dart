import 'failures.dart';

/// Carries an [AppFailure] across the network without losing its type.
///
/// This matters more than it looks. Every screen in the client already
/// distinguishes a [BusinessRuleFailure] ("this would make stock negative")
/// from a [ValidationFailure] ("the quantity is required") from a
/// [PermissionFailure] ("you may not do this"), and shows each differently. If
/// the API collapsed them into a bare status code and a string, every one of
/// those screens would have to be rewritten and the distinctions would be lost.
///
/// So the failure is encoded with a discriminator and rebuilt on the far side
/// as the same subclass. The strings are a **wire contract**: changing one
/// breaks every deployed client, so they are frozen independently of the Dart
/// class names.
///
/// Both the server and the client use this one codec, which is why it lives
/// here rather than in either of them.
class FailureCodec {
  const FailureCodec._();

  // Frozen wire identifiers. Never rename one; add a new kind instead.
  static const String kindValidation = 'validation';
  static const String kindBusinessRule = 'business_rule';
  static const String kindPermission = 'permission';
  static const String kindNotFound = 'not_found';
  static const String kindStorage = 'storage';
  static const String kindAuth = 'auth';

  /// Sent when the server hit something it did not expect — a bug, a disk
  /// error, a dependency failing. It has no [AppFailure] subclass of its own
  /// because nothing *throws* it; only the top-level handler emits it.
  static const String kindInternal = 'internal';

  /// The kind string for [failure].
  ///
  /// The switch is exhaustive over a sealed hierarchy, so adding a new
  /// [AppFailure] subclass without deciding how it crosses the wire is a
  /// compile error rather than a runtime surprise.
  static String kindOf(AppFailure failure) => switch (failure) {
    ValidationFailure() => kindValidation,
    BusinessRuleFailure() => kindBusinessRule,
    PermissionFailure() => kindPermission,
    NotFoundFailure() => kindNotFound,
    StorageFailure() => kindStorage,
    AuthFailure() => kindAuth,
  };

  static Map<String, Object?> toJson(AppFailure failure) {
    final json = <String, Object?>{
      'kind': kindOf(failure),
      'message': failure.message,
    };
    if (failure.details != null) json['details'] = failure.details;
    switch (failure) {
      case ValidationFailure(:final field):
        if (field != null) json['field'] = field;
      case BusinessRuleFailure(:final rule):
        if (rule != null) json['rule'] = rule;
      case PermissionFailure(:final permission):
        if (permission != null) json['permission'] = permission;
      case NotFoundFailure():
      case StorageFailure():
      case AuthFailure():
        break;
    }
    return json;
  }

  /// Rebuilds the failure a server reported.
  ///
  /// An unrecognised `kind` becomes a [StorageFailure], never a
  /// [BusinessRuleFailure]. The distinction is not pedantic: a business rule
  /// failure tells the user *they* did something the business forbids, so
  /// blaming one for a server bug or a newer server's unknown error code would
  /// send the cashier hunting for a mistake they did not make. What it must not
  /// do is swallow the error — the server's own message is carried through, and
  /// the call still fails.
  static AppFailure fromJson(Map<String, Object?> json) {
    final message =
        json['message'] as String? ?? 'The server reported an error.';
    final details = json['details'] as String?;
    return switch (json['kind']) {
      kindValidation => ValidationFailure(
        message,
        details: details,
        field: json['field'] as String?,
      ),
      kindBusinessRule => BusinessRuleFailure(
        message,
        details: details,
        rule: json['rule'] as String?,
      ),
      kindPermission => PermissionFailure(
        message,
        details: details,
        permission: json['permission'] as String?,
      ),
      kindNotFound => NotFoundFailure(message, details: details),
      kindStorage || kindInternal => StorageFailure(message, details: details),
      kindAuth => AuthFailure(message, details: details),
      _ => StorageFailure(message, details: details),
    };
  }
}
