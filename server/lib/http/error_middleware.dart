import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:venvo_core/core/errors/failures.dart';

import 'responses.dart';

/// Turns thrown failures into responses, and makes sure nothing is lost.
///
/// This is the single place an exception becomes a status code, which is what
/// lets every route and every service below it simply `throw` the way the
/// existing 673 tests already expect. The alternative — each route catching and
/// translating — is how a handler ends up returning 200 on a path somebody
/// forgot.
///
/// Two kinds of thing arrive here:
///
/// * An [AppFailure], thrown on purpose by a business rule. The client is told
///   exactly what it was, with its type preserved, so the screen can react the
///   way it already does locally.
/// * Anything else — a bug, a disk error, a null that should not have been.
///   The client gets a 500 with a reference and no internals; the server log
///   gets the error and the stack trace. It is never swallowed and it is never
///   reported as success.
Middleware handleFailures({required void Function(String message) log}) {
  return (Handler inner) {
    return (Request request) async {
      try {
        return await inner(request);
      } on AppFailure catch (failure) {
        // Expected and already user-presentable. Logged at a lower volume:
        // these are a normal part of running a business, not incidents.
        if (failure is StorageFailure) {
          log(
            'storage failure on ${request.method} '
            '${request.requestedUri.path}: ${failure.message}'
            '${failure.details == null ? '' : ' (${failure.details})'}',
          );
        }
        return Api.failure(failure);
      } catch (error, stack) {
        final reference = _reference();
        log(
          '[$reference] UNHANDLED on ${request.method} '
          '${request.requestedUri.path}\n$error\n$stack',
        );
        return Api.internal(reference);
      }
    };
  };
}

final Random _random = Random();

/// A short, human-quotable reference. Not a security token — it only has to be
/// findable in a log file and easy to read down a telephone.
String _reference() {
  const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  return List.generate(
    6,
    (_) => alphabet[_random.nextInt(alphabet.length)],
  ).join();
}
