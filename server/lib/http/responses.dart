import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:venvo_core/core/errors/failure_codec.dart';
import 'package:venvo_core/core/errors/failures.dart';

/// JSON encoding and the one place an error becomes a status code.
class Api {
  const Api._();

  static const Map<String, String> _jsonHeaders = {
    'content-type': 'application/json; charset=utf-8',
    // The API is for the desktop and Android clients, not a browser. Saying so
    // stops a proxy or a webview from trying to sniff a different type.
    'x-content-type-options': 'nosniff',
  };

  static Response ok(Object? body) => _json(200, body);

  static Response created(Object? body) => _json(201, body);

  static Response noContent() => Response(204);

  /// The HTTP status for a business failure.
  ///
  /// Exhaustive over the sealed [AppFailure] hierarchy, so adding a failure
  /// type without deciding its status is a compile error. The mapping is
  /// deliberate:
  ///
  /// * 422 for validation — the request was understood and refused on content.
  /// * **409 for a business rule** — not 400. The request was well formed and
  ///   would have been legal at another moment; it conflicts with the current
  ///   state of the business (stock would go negative, the invoice is already
  ///   cancelled). A client must not treat it as a bug in its own request.
  /// * 403 for permission, 401 for authentication — the usual distinction
  ///   between "we do not know who you are" and "we do, and no".
  /// * 503 for storage — the database or disk is unhappy. It invites a retry,
  ///   which a 500 does not.
  static int statusFor(AppFailure failure) => switch (failure) {
    ValidationFailure() => 422,
    BusinessRuleFailure() => 409,
    PermissionFailure() => 403,
    NotFoundFailure() => 404,
    StorageFailure() => 503,
    AuthFailure() => 401,
  };

  /// Reports a failure the business logic raised on purpose.
  static Response failure(AppFailure failure) =>
      _json(statusFor(failure), {'error': FailureCodec.toJson(failure)});

  /// Reports something nobody planned for.
  ///
  /// The client is told that the request failed, and given [reference] so the
  /// line in the server log can be found. It is **not** given the exception
  /// text: that can carry file paths, SQL and row contents, and the client is
  /// across a network. The full detail goes to the log instead — the failure is
  /// never silently dropped, it is just reported in the right direction.
  static Response internal(String reference) => _json(500, {
    'error': {
      'kind': FailureCodec.kindInternal,
      'message':
          'The server could not complete this request. Nothing was saved. '
          'Quote reference $reference when reporting it.',
      'reference': reference,
    },
  });

  static Response _json(int status, Object? body) => Response(
    status,
    body: body == null ? null : jsonEncode(body),
    headers: _jsonHeaders,
  );
}
