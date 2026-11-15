import 'package:shelf/shelf.dart';
import 'package:venvo_core/core/errors/failures.dart';

import 'session_store.dart';

/// Key the resolved session is stored under in the shelf request context.
const String sessionContextKey = 'venvo.session';

extension RequestSession on Request {
  /// The signed-in user for this request.
  ///
  /// Throws [StateError] — not an [AppFailure] — if the route was not placed
  /// behind [requireSession]. That is a wiring mistake in the server, not
  /// something a client did, and it should fail loudly in development rather
  /// than turn into a 401 that looks like an authentication problem.
  ActiveSession get session {
    final value = context[sessionContextKey];
    if (value is ActiveSession) return value;
    throw StateError(
      'No session on this request. The route is not behind requireSession(), '
      'which means it is serving business data unauthenticated. Mount it on '
      'the protected router.',
    );
  }
}

/// Rejects any request without a usable bearer token.
///
/// Applied to the whole protected router rather than route by route, so that
/// adding an endpoint cannot accidentally ship it unauthenticated: the default
/// for anything mounted there is "signed in", and making something public
/// takes a deliberate move to the public router.
Middleware requireSession(SessionStore sessions) {
  return (Handler inner) {
    return (Request request) async {
      final token = _bearerToken(request);
      if (token == null) {
        throw const AuthFailure(
          'Sign in to continue.',
          details: 'No bearer token was presented.',
        );
      }

      final session = await sessions.lookup(token);
      if (session == null) {
        // One message for every reason a token can fail — unknown, revoked,
        // expired, idle, account disabled. Telling the holder of a stolen
        // token which one it was would help them.
        throw const AuthFailure(
          'Your session has ended. Please sign in again.',
        );
      }

      return inner(request.change(context: {sessionContextKey: session}));
    };
  };
}

/// Blocks the rest of the API while a user still owes a password change.
///
/// The desktop shell already refuses to show anything else, but a client is
/// not a security boundary: anyone can send an HTTP request. The sign-out,
/// identity and change-password endpoints live outside this gate, which is
/// exactly the set needed to get out of the state.
Middleware refuseUntilPasswordChanged() {
  return (Handler inner) {
    return (Request request) async {
      if (request.session.user.mustChangePassword) {
        throw const AuthFailure(
          'You must choose a new password before using the system.',
          details: 'A password change is outstanding for this account.',
        );
      }
      return inner(request);
    };
  };
}

/// Throws [PermissionFailure] unless the signed-in user holds [permission].
///
/// Most endpoints do not need this: the business services take the actor and
/// check permissions themselves, which is the enforcement that cannot be
/// bypassed by reaching an operation another way. It is used for the read-only
/// query endpoints, where there is no service call to do the checking.
void requirePermission(Request request, String permission, {String? action}) =>
    request.session.user.require(permission, action: action);

String? _bearerToken(Request request) {
  final header = request.headers['authorization'];
  if (header == null) return null;
  final parts = header.split(' ');
  // The scheme is case-insensitive per RFC 7235; some HTTP clients send
  // "bearer".
  if (parts.length < 2 || parts.first.toLowerCase() != 'bearer') return null;
  final token = parts.sublist(1).join(' ').trim();
  return token.isEmpty ? null : token;
}
