import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:venvo_core/core/database/app_database.dart';
import 'package:venvo_core/core/enums/app_enums.dart';
import 'package:venvo_core/core/services/clock.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import '../config.dart';

/// A session that has just been created. This is the only moment the plain
/// token exists anywhere — it is returned to the client and then forgotten,
/// because only its hash is stored.
class IssuedSession {
  const IssuedSession({
    required this.sessionId,
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  final String sessionId;
  final String token;
  final DateTime expiresAt;
  final AuthenticatedUser user;
}

/// A session that has been presented and found good.
class ActiveSession {
  const ActiveSession({required this.sessionId, required this.user});

  final String sessionId;
  final AuthenticatedUser user;
}

/// Issues, validates and revokes bearer tokens.
class SessionStore {
  SessionStore({
    required AppDatabase database,
    required AuthRepository auth,
    required Clock clock,
    required ServerConfig config,
  }) : _db = database,
       _auth = auth,
       _clock = clock,
       _config = config;

  final AppDatabase _db;
  final AuthRepository _auth;
  final Clock _clock;
  final ServerConfig _config;

  static const Uuid _uuid = Uuid();

  /// How stale `lastSeenAt` is allowed to get before it is written again.
  ///
  /// Writing it on every request would mean a database write per API call.
  /// Billing is the hot path and the thing the brief forbids slowing down, so
  /// the timestamp is only refreshed once a minute. The idle timeout is
  /// measured in hours, so a minute of imprecision costs nothing.
  static const Duration _lastSeenGranularity = Duration(minutes: 1);

  /// Creates a session for a user whose password has **already** been
  /// verified. This method does not authenticate; [AuthRepository.signIn]
  /// does, including the failed-attempt lockout.
  Future<IssuedSession> issue({
    required AuthenticatedUser user,
    String? deviceLabel,
    String? deviceKind,
  }) async {
    final now = _clock.nowUtc();
    final token = _newToken();
    final expiresAt = now.add(_config.sessionTtl);
    final id = _uuid.v4();

    await _db
        .into(_db.userSessions)
        .insert(
          UserSessionsCompanion.insert(
            id: id,
            userId: user.id,
            tokenHash: _hash(token),
            deviceLabel: Value(_trimToNull(deviceLabel, 120)),
            deviceKind: Value(_trimToNull(deviceKind, 32)),
            createdAt: now,
            lastSeenAt: now,
            expiresAt: expiresAt,
          ),
        );

    return IssuedSession(
      sessionId: id,
      token: token,
      expiresAt: expiresAt,
      user: user,
    );
  }

  /// Resolves a bearer token to a signed-in user, or null if the token is not
  /// usable for any reason.
  ///
  /// Deliberately returns null rather than throwing, and does not distinguish
  /// "no such token" from "revoked" from "expired" to the caller: the client
  /// gets one 401 and the reason stays on the server, so a stolen token tells
  /// its holder nothing about why it stopped working.
  ///
  /// Permissions are re-resolved from the database on **every** request rather
  /// than cached in the session row. That costs a few indexed reads, and buys
  /// the property that taking a permission away from a role takes effect
  /// immediately rather than whenever a till happens to sign in again.
  Future<ActiveSession?> lookup(String token) async {
    if (token.isEmpty) return null;

    final row = await (_db.select(
      _db.userSessions,
    )..where((s) => s.tokenHash.equals(_hash(token)))).getSingleOrNull();
    if (row == null) return null;
    if (row.revokedAt != null) return null;

    final now = _clock.nowUtc();
    if (!row.expiresAt.isAfter(now)) return null;

    if (!row.lastSeenAt.add(_config.sessionIdleTimeout).isAfter(now)) {
      await _revoke(row.id, reason: 'Idle longer than permitted.', at: now);
      return null;
    }

    // A disabled account must lose access at once, not when its session
    // happens to expire. Checked here as well as at sign-in, because
    // disabling a user is exactly the moment someone is trying to stop them
    // doing something.
    final account = await (_db.select(
      _db.users,
    )..where((u) => u.id.equals(row.userId))).getSingleOrNull();
    if (account == null || account.status != EntityStatus.active) {
      await _revoke(row.id, reason: 'Account disabled.', at: now);
      return null;
    }

    if (now.difference(row.lastSeenAt) >= _lastSeenGranularity) {
      await (_db.update(_db.userSessions)..where((s) => s.id.equals(row.id)))
          .write(UserSessionsCompanion(lastSeenAt: Value(now)));
    }

    return ActiveSession(
      sessionId: row.id,
      user: await _auth.refresh(row.userId),
    );
  }

  /// Ends one session — a sign-out, or an administrator dropping a device.
  Future<void> revoke(String sessionId, {required String reason}) =>
      _revoke(sessionId, reason: reason, at: _clock.nowUtc());

  /// Ends every session a user holds.
  ///
  /// Called when their password changes and when their account is disabled. A
  /// password change that left old sessions working would make "someone knows
  /// my password" unfixable by the person it happened to.
  Future<int> revokeAllForUser(
    int userId, {
    required String reason,
    String? exceptSessionId,
  }) async {
    final now = _clock.nowUtc();
    final statement = _db.update(_db.userSessions)
      ..where((s) {
        final mine = s.userId.equals(userId) & s.revokedAt.isNull();
        return exceptSessionId == null
            ? mine
            : mine & s.id.equals(exceptSessionId).not();
      });
    return statement.write(
      UserSessionsCompanion(
        revokedAt: Value(now),
        revokedReason: Value(_trimToNull(reason, 120)),
      ),
    );
  }

  /// The devices a user is signed in on, newest first. Powers the device list
  /// and lets an administrator see where an account is in use.
  Future<List<UserSession>> activeSessionsFor(int userId) async {
    final now = _clock.nowUtc();
    final query = _db.select(_db.userSessions)
      ..where(
        (s) =>
            s.userId.equals(userId) &
            s.revokedAt.isNull() &
            s.expiresAt.isBiggerThanValue(now),
      )
      ..orderBy([(s) => OrderingTerm.desc(s.lastSeenAt)]);
    return query.get();
  }

  /// Deletes sessions that expired long enough ago to be of no further
  /// interest. Run at startup and on a timer, so the table does not grow for
  /// ever on a server that is never restarted.
  Future<int> purgeExpired({Duration keepFor = const Duration(days: 30)}) {
    final cutoff = _clock.nowUtc().subtract(keepFor);
    return (_db.delete(
      _db.userSessions,
    )..where((s) => s.expiresAt.isSmallerThanValue(cutoff))).go();
  }

  Future<void> _revoke(
    String sessionId, {
    required String reason,
    required DateTime at,
  }) async {
    await (_db.update(
      _db.userSessions,
    )..where((s) => s.id.equals(sessionId) & s.revokedAt.isNull())).write(
      UserSessionsCompanion(
        revokedAt: Value(at),
        revokedReason: Value(_trimToNull(reason, 120)),
      ),
    );
  }

  /// 256 bits from the platform's cryptographic generator, base64url encoded.
  ///
  /// `Random.secure()` and not `Random()`: a predictable token is a usable
  /// token for whoever predicts it.
  static String _newToken() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Tokens are looked up *by* their hash, so the index does the comparison
  /// and there is no byte-by-byte check to time.
  static String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  static String? _trimToNull(String? value, int maxLength) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= maxLength
        ? trimmed
        : trimmed.substring(0, maxLength);
  }
}
