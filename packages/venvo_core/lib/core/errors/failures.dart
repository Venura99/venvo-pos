/// Base class for every expected, user-presentable error in the application.
///
/// Business rules throw these instead of returning sentinel values so that a
/// violation can never be silently ignored half-way through a database
/// transaction.
sealed class AppFailure implements Exception {
  const AppFailure(this.message, {this.details});

  final String message;
  final String? details;

  @override
  String toString() => details == null
      ? '$runtimeType: $message'
      : '$runtimeType: $message ($details)';
}

/// Input did not satisfy a validation rule.
class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.details, this.field});

  final String? field;
}

/// A business invariant would have been violated, e.g. negative stock.
class BusinessRuleFailure extends AppFailure {
  const BusinessRuleFailure(super.message, {super.details, this.rule});

  /// Stable identifier of the rule, useful in tests and audit logs.
  final String? rule;
}

/// The signed-in user lacks the permission required for the operation.
class PermissionFailure extends AppFailure {
  const PermissionFailure(super.message, {super.details, this.permission});

  final String? permission;
}

/// A requested record does not exist (or is soft-deleted).
class NotFoundFailure extends AppFailure {
  const NotFoundFailure(super.message, {super.details});
}

/// Storage-level problem: database, filesystem or backup archive.
class StorageFailure extends AppFailure {
  const StorageFailure(super.message, {super.details});
}

/// Authentication could not be completed.
class AuthFailure extends AppFailure {
  const AuthFailure(super.message, {super.details});
}
