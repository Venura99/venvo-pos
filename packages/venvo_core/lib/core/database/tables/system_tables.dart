import 'package:drift/drift.dart';

import '../../enums/app_enums.dart';

/// Users, roles, permissions, audit trail, settings, document numbering,
/// attachments and backup history.

@DataClassName('User')
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 3, max: 48)();
  TextColumn get fullName => text().withLength(min: 1, max: 180)();

  /// Base64 of the PBKDF2-HMAC-SHA256 derived key. No password is ever stored
  /// or logged in clear text, and no credential is hardcoded in the source.
  TextColumn get passwordHash => text()();

  /// Base64 of the per-user random salt.
  TextColumn get passwordSalt => text()();

  /// Iteration count used when the hash was derived, so the cost can be
  /// raised later without invalidating existing users.
  IntColumn get passwordIterations => integer()();

  /// Forces a password change on next sign-in. Set on the bootstrap admin.
  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(false))();
  TextColumn get status => textEnum<EntityStatus>().withDefault(
    Constant(EntityStatus.active.name),
  )();
  IntColumn get failedLoginCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  DateTimeColumn get lastLoginAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {username},
  ];
}

@DataClassName('Role')
class Roles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().withLength(min: 1, max: 32)();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable().withLength(max: 500)();

  /// System roles are seeded and cannot be deleted or renamed by users.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {code},
  ];
}

@DataClassName('PermissionDef')
class PermissionDefs extends Table {
  @override
  String get tableName => 'permissions';

  IntColumn get id => integer().autoIncrement()();

  /// Dotted identifier, e.g. `stock.negative_override`.
  TextColumn get key => text().withLength(min: 1, max: 64)();
  TextColumn get module => text().withLength(min: 1, max: 48)();
  TextColumn get description => text().nullable().withLength(max: 300)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {key},
  ];
}

@DataClassName('RolePermission')
class RolePermissions extends Table {
  IntColumn get roleId =>
      integer().references(Roles, #id, onDelete: KeyAction.cascade)();
  IntColumn get permissionId =>
      integer().references(PermissionDefs, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {roleId, permissionId};
}

@DataClassName('UserRole')
class UserRoles extends Table {
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  IntColumn get roleId =>
      integer().references(Roles, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column<Object>> get primaryKey => {userId, roleId};
}

/// Append-only record of every significant action. Rows are never updated or
/// deleted.
@DataClassName('AuditLog')
@TableIndex(name: 'idx_audit_at', columns: {#occurredAt})
@TableIndex(name: 'idx_audit_entity', columns: {#entityKind, #entityId})
@TableIndex(name: 'idx_audit_user', columns: {#userId})
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get occurredAt => dateTime()();

  /// Null for actions taken before sign-in, such as a failed login attempt
  /// against an unknown username.
  IntColumn get userId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get username => text().nullable().withLength(max: 48)();
  TextColumn get action => textEnum<AuditAction>()();
  TextColumn get entityKind => textEnum<EntityKind>().nullable()();
  IntColumn get entityId => integer().nullable()();

  /// Short human-readable sentence shown in the audit viewer.
  TextColumn get summary => text().withLength(max: 500)();

  /// JSON snapshots, present only for update actions.
  TextColumn get beforeJson => text().nullable()();
  TextColumn get afterJson => text().nullable()();

  /// Machine the action was performed on, for future multi-client use.
  TextColumn get hostName => text().nullable().withLength(max: 120)();
}

@DataClassName('Setting')
class Settings extends Table {
  TextColumn get key => text().withLength(min: 1, max: 80)();
  TextColumn get value => text().nullable()();

  /// One of `string`, `int`, `bool`, `double`, `datetime`, `json`.
  TextColumn get valueType => text().withDefault(const Constant('string'))();
  TextColumn get description => text().nullable().withLength(max: 300)();
  DateTimeColumn get updatedAt => dateTime()();
  IntColumn get updatedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Per-prefix document counters. [nextNumber] is read and incremented inside
/// the same transaction that inserts the document, which is what makes
/// document numbers unique without relying on row counts.
@DataClassName('DocumentSequence')
class DocumentSequences extends Table {
  /// One of the values in `SequenceKeys`, also used as the number prefix.
  TextColumn get sequenceKey => text().withLength(min: 1, max: 24)();

  /// Period the counter resets on, e.g. `2026` or `ALL` when it never resets.
  TextColumn get periodKey => text().withLength(min: 1, max: 16)();
  TextColumn get prefix => text().withLength(min: 1, max: 16)();
  IntColumn get nextNumber => integer().withDefault(const Constant(1))();
  IntColumn get padding => integer().withDefault(const Constant(5))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {sequenceKey, periodKey};
}

/// Metadata for files stored on disk under the application data directory.
/// The binary content itself is never written into the database, so the
/// SQLite file stays small and fast to back up.
@DataClassName('Attachment')
@TableIndex(name: 'idx_attachments_entity', columns: {#entityKind, #entityId})
class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityKind => textEnum<EntityKind>()();
  IntColumn get entityId => integer()();
  TextColumn get kind => textEnum<AttachmentKind>()();
  TextColumn get fileName => text().withLength(min: 1, max: 255)();

  /// Path relative to the attachments root, so moving or restoring the data
  /// directory does not break references.
  TextColumn get relativePath => text().withLength(min: 1, max: 500)();
  TextColumn get mimeType => text().withLength(max: 120)();
  IntColumn get byteSize => integer()();

  /// SHA-256 of the stored file, used to detect corruption after a restore.
  TextColumn get checksum => text().nullable().withLength(max: 64)();
  TextColumn get notes => text().nullable().withLength(max: 500)();
  IntColumn get uploadedByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get uploadedAt => dateTime()();
}

@DataClassName('BackupRecord')
class BackupRecords extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fileName => text().withLength(min: 1, max: 255)();
  TextColumn get relativePath => text().withLength(min: 1, max: 500)();
  IntColumn get byteSize => integer()();
  IntColumn get schemaVersion => integer()();
  BoolColumn get isAutomatic => boolean().withDefault(const Constant(false))();
  TextColumn get checksum => text().nullable().withLength(max: 64)();

  /// Set once the archive has been opened and its database integrity-checked.
  BoolColumn get validated => boolean().withDefault(const Constant(false))();
  TextColumn get notes => text().nullable().withLength(max: 500)();
  IntColumn get createdByUserId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  DateTimeColumn get createdAt => dateTime()();
}

/// A signed-in device.
///
/// The cloud build authenticates with an **opaque bearer token** rather than a
/// JWT, and this table is the reason that is the better trade here:
///
/// * **Revocation is immediate.** An employee leaves, or a tablet is lost, and
///   the session is revoked in one row. A JWT stays valid until it expires, so
///   revoking one needs a deny-list — which is this table again, with extra
///   steps.
/// * **There is no signing secret.** Nothing to configure, rotate, leak into a
///   client build, or commit by accident.
/// * **The cost is one indexed lookup per request**, against local SQLite.
///
/// The token itself is never stored. Only its SHA-256 is, so a copy of the
/// database does not hand over working sessions — the same reasoning that puts
/// a PBKDF2 hash rather than a password in [Users].
@DataClassName('UserSession')
@TableIndex(name: 'idx_sessions_token', columns: {#tokenHash}, unique: true)
@TableIndex(name: 'idx_sessions_user', columns: {#userId})
@TableIndex(name: 'idx_sessions_expires', columns: {#expiresAt})
class UserSessions extends Table {
  /// The session's own identifier (UUID). Distinct from the token: this is
  /// safe to log and to show in a "signed-in devices" list.
  TextColumn get id => text().withLength(min: 1, max: 64)();

  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();

  /// Lower-case hex SHA-256 of the bearer token.
  TextColumn get tokenHash => text().withLength(min: 64, max: 64)();

  /// What the user sees in the device list, e.g. "Counter 2" or "Nimal's
  /// phone". Supplied by the client at sign-in; never trusted for anything
  /// but display.
  TextColumn get deviceLabel => text().nullable().withLength(max: 120)();

  /// `windows`, `android`, or whatever a later client reports. Recorded for
  /// the device list and for support, not used in any decision.
  TextColumn get deviceKind => text().nullable().withLength(max: 32)();

  DateTimeColumn get createdAt => dateTime()();

  /// Updated on use, which is what the idle timeout is measured from.
  DateTimeColumn get lastSeenAt => dateTime()();

  /// Hard expiry, independent of activity.
  DateTimeColumn get expiresAt => dateTime()();

  /// Set when the session is ended deliberately — sign-out, an administrator
  /// revoking a device, or a password change. A revoked row is kept rather
  /// than deleted so the audit trail still explains why access stopped.
  DateTimeColumn get revokedAt => dateTime().nullable()();
  TextColumn get revokedReason => text().nullable().withLength(max: 120)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
