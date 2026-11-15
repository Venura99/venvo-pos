import '../../../core/constants/permissions.dart';
import '../../../core/errors/failures.dart';

/// The signed-in user together with the permissions resolved from their roles.
///
/// Permissions are resolved once at sign-in and carried in memory, so a check
/// on a hot path (every discount keystroke, every stock line) costs a set
/// lookup rather than a query.
class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.roleCodes,
    required this.permissions,
    required this.mustChangePassword,
  });

  /// Rebuilds the user a server reported.
  ///
  /// `mustChangePassword` is read strictly and throws if the server omitted
  /// it. Defaulting it to false would be the one unsafe direction: a client
  /// talking to a server that stopped sending the flag would quietly let
  /// someone past a password change the administrator required.
  factory AuthenticatedUser.fromJson(Map<String, Object?> json) =>
      AuthenticatedUser(
        id: (json['id'] as num).toInt(),
        username: json['username'] as String,
        fullName: json['fullName'] as String,
        roleCodes: (json['roleCodes'] as List<Object?>).cast<String>().toSet(),
        permissions: (json['permissions'] as List<Object?>)
            .cast<String>()
            .toSet(),
        mustChangePassword: json['mustChangePassword'] as bool,
      );

  final int id;
  final String username;
  final String fullName;
  final Set<String> roleCodes;
  final Set<String> permissions;

  /// Set on the bootstrap administrator and after an administrator resets
  /// someone's password. The shell refuses to show anything else until it is
  /// cleared.
  final bool mustChangePassword;

  /// Wire format, shared by the server and both clients.
  ///
  /// The two sets are sorted so that the same user always produces the same
  /// bytes, which makes a captured payload diffable and a cached response
  /// comparable.
  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'fullName': fullName,
    'roleCodes': roleCodes.toList()..sort(),
    'permissions': permissions.toList()..sort(),
    'mustChangePassword': mustChangePassword,
  };

  bool get isAdministrator => roleCodes.contains(RoleCodes.administrator);

  bool can(String permission) => permissions.contains(permission);

  bool canAll(Iterable<String> required) => required.every(can);

  bool canAny(Iterable<String> required) => required.any(can);

  /// Throws [PermissionFailure] unless the user holds [permission].
  ///
  /// Business services call this rather than checking in the UI, so a missing
  /// permission cannot be bypassed by reaching an operation another way.
  void require(String permission, {String? action}) {
    if (can(permission)) return;
    throw PermissionFailure(
      action == null
          ? 'You do not have permission to do this.'
          : 'You do not have permission to $action.',
      permission: permission,
      details: 'Required permission: $permission',
    );
  }

  AuthenticatedUser copyWith({bool? mustChangePassword}) => AuthenticatedUser(
    id: id,
    username: username,
    fullName: fullName,
    roleCodes: roleCodes,
    permissions: permissions,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
  );

  /// Display initials for the shell's account button.
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return username.isEmpty ? '?' : username[0].toUpperCase();
    }
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
