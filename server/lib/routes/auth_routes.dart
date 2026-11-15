import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/authentication/data/auth_repository.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import '../auth/auth_middleware.dart';
import '../auth/session_store.dart';
import '../http/json_body.dart';
import '../http/responses.dart';

/// Endpoints that must work before anyone is signed in.
Router publicRoutes({
  required AuthRepository auth,
  required SessionStore sessions,
  required int schemaVersion,
  void Function(AuthenticatedUser user)? onSignedIn,
}) {
  final router = Router();

  /// What a client needs before it can draw its first screen: whether this
  /// server has any users yet, and whether the client is new enough to talk to
  /// it. Deliberately says nothing about the business.
  router.get('/status', (Request request) async {
    return Api.ok({
      'needsFirstRunSetup': await auth.hasNoUsers(),
      'schemaVersion': schemaVersion,
      'apiVersion': apiVersion,
    });
  });

  /// Creates the first administrator on a brand new server.
  ///
  /// Public by necessity — there is nobody to authenticate as yet — and safe
  /// because [AuthRepository.createFirstAdministrator] refuses once any user
  /// exists. That check is inside the same transaction as the insert, so two
  /// clients racing on a fresh server cannot both succeed. No account is ever
  /// created with a default password.
  router.post('/auth/first-run', (Request request) async {
    final body = await JsonBody.read(request);
    final user = await auth.createFirstAdministrator(
      fullName: body.requireString('fullName', maxLength: 180),
      username: body.requireString('username', maxLength: 48),
      password: body.requireSecret('password'),
    );
    return Api.created(await _issue(sessions, user, body));
  });

  router.post('/auth/login', (Request request) async {
    final body = await JsonBody.read(request);
    // signIn counts failed attempts and locks the account for five minutes
    // after five of them. That protection was written for the offline build
    // and applies here unchanged, which is what makes a password worth
    // anything on a server reachable from the internet.
    final user = await auth.signIn(
      username: body.requireString('username', maxLength: 48),
      password: body.requireSecret('password'),
    );
    final session = await _issue(sessions, user, body);
    onSignedIn?.call(user);
    return Api.ok(session);
  });

  return router;
}

/// Endpoints that need a session but must stay reachable while the user still
/// owes a password change — otherwise an account forced to change its password
/// could never do so.
Router identityRoutes({
  required AuthRepository auth,
  required SessionStore sessions,
}) {
  final router = Router();

  router.get('/auth/me', (Request request) async {
    return Api.ok({'user': request.session.user.toJson()});
  });

  router.post('/auth/logout', (Request request) async {
    final session = request.session;
    await auth.signOut(session.user);
    await sessions.revoke(session.sessionId, reason: 'Signed out.');
    return Api.noContent();
  });

  router.post('/auth/password', (Request request) async {
    final session = request.session;
    final body = await JsonBody.read(request);
    await auth.changeOwnPassword(
      user: session.user,
      currentPassword: body.requireSecret('currentPassword'),
      newPassword: body.requireSecret('newPassword'),
    );

    // Every other device signed in as this account loses its session. Someone
    // changing their password because they fear it is known needs that to be
    // the thing that ends the other session, not a timeout hours later. The
    // device doing the changing keeps working.
    final revoked = await sessions.revokeAllForUser(
      session.user.id,
      reason: 'Password changed.',
      exceptSessionId: session.sessionId,
    );
    return Api.ok({'otherDevicesSignedOut': revoked});
  });

  /// The devices this account is signed in on.
  router.get('/auth/devices', (Request request) async {
    final session = request.session;
    final rows = await sessions.activeSessionsFor(session.user.id);
    return Api.ok({
      'devices': [
        for (final row in rows)
          {
            'id': row.id,
            'deviceLabel': row.deviceLabel,
            'deviceKind': row.deviceKind,
            'createdAt': row.createdAt.toIso8601String(),
            'lastSeenAt': row.lastSeenAt.toIso8601String(),
            'expiresAt': row.expiresAt.toIso8601String(),
            'isCurrent': row.id == session.sessionId,
          },
      ],
    });
  });

  /// Signs a device out remotely.
  ///
  /// Scoped to the caller's own sessions. Without that check any signed-in
  /// user could end anyone else's session by guessing an id; revoking another
  /// person's access is an administrative act and belongs behind
  /// `users.manage`.
  router.delete('/auth/devices/<id>', (Request request, String id) async {
    final session = request.session;
    final mine = await sessions.activeSessionsFor(session.user.id);
    if (!mine.any((row) => row.id == id)) {
      throw const NotFoundFailure(
        'That device is not signed in on this account.',
      );
    }
    await sessions.revoke(id, reason: 'Signed out remotely.');
    return Api.noContent();
  });

  return router;
}

/// The API version the client negotiates against. Bumped only for a change
/// that an older client cannot survive.
const int apiVersion = 1;

Future<Map<String, Object?>> _issue(
  SessionStore sessions,
  AuthenticatedUser user,
  JsonBody body,
) async {
  final issued = await sessions.issue(
    user: user,
    deviceLabel: body.optionalString('deviceLabel', maxLength: 120),
    deviceKind: body.optionalString('deviceKind', maxLength: 32),
  );
  return {
    'token': issued.token,
    'sessionId': issued.sessionId,
    'expiresAt': issued.expiresAt.toIso8601String(),
    'user': issued.user.toJson(),
  };
}
