import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/failure_codec.dart';
import '../errors/failures.dart';
import 'revision_bus.dart';

/// Where the bearer token is kept between calls, and between runs.
///
/// An interface because persistence is the client's business: the desktop app
/// writes a file under its data directory, a test keeps it in memory, and a
/// future mobile build may use the platform keystore.
abstract class ApiTokenStore {
  String? get token;

  Future<void> save(String token);

  Future<void> clear();
}

/// A token store that forgets everything when the process ends. Used by tests.
class InMemoryTokenStore implements ApiTokenStore {
  @override
  String? token;

  @override
  Future<void> save(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

/// Talks to the Venvo POS API.
///
/// Everything a module API needs: the bearer token, JSON encoding, turning an
/// error response back into the [AppFailure] the server threw, and the
/// re-emitting streams that let the existing screens keep working unchanged.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required ApiTokenStore tokens,
    RevisionBus? revisions,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _tokens = tokens,
       revisions = revisions ?? RevisionBus(),
       _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final ApiTokenStore _tokens;
  final RevisionBus revisions;
  final http.Client _http;
  final Duration timeout;

  bool get hasToken => _tokens.token != null;

  Future<void> saveToken(String token) => _tokens.save(token);

  Future<void> clearToken() => _tokens.clear();

  // ---- verbs -------------------------------------------------------------

  Future<Map<String, Object?>> get(
    String path, {
    Map<String, Object?>? query,
  }) => _send('GET', path, query: query);

  /// [bumps] names the topics this write changed. Every list watching one of
  /// them re-fetches, which is what makes a saved form show up in the table
  /// behind it. Forgetting it does not corrupt anything — it just leaves a
  /// stale list on screen until something else refreshes it.
  Future<Map<String, Object?>> post(
    String path, {
    Object? body,
    Set<ApiTopic> bumps = const {},
  }) => _send('POST', path, body: body, bumps: bumps);

  Future<Map<String, Object?>> put(
    String path, {
    Object? body,
    Set<ApiTopic> bumps = const {},
  }) => _send('PUT', path, body: body, bumps: bumps);

  Future<Map<String, Object?>> patch(
    String path, {
    Object? body,
    Set<ApiTopic> bumps = const {},
  }) => _send('PATCH', path, body: body, bumps: bumps);

  Future<Map<String, Object?>> delete(
    String path, {
    Object? body,
    Set<ApiTopic> bumps = const {},
  }) => _send('DELETE', path, body: body, bumps: bumps);

  /// Forces every stream watching [topics] to ask the server again. Behind a
  /// retry button, or after reconnecting.
  void refresh(Set<ApiTopic> topics) => revisions.bump(topics);

  // ---- watching ----------------------------------------------------------

  /// A stream that yields [fetch] now, and again whenever one of [topics]
  /// changes.
  ///
  /// This is the shape that keeps the 52 existing screens working: they watch
  /// a `StreamProvider` that used to be a Drift query stream, and this is the
  /// same contract over HTTP.
  ///
  /// A failed fetch is delivered as a stream **error**, not by closing the
  /// stream. That difference matters: an error that terminated the
  /// subscription would leave the screen stuck on a failure until the provider
  /// was rebuilt, whereas this way a dropped connection shows the error and
  /// the next refresh recovers on its own.
  ///
  /// A periodic background refresh (see [RevisionBus.refreshInBackground])
  /// that fails while data is already on screen does **not** replace it with
  /// an error: the screen keeps its last good data and the next refresh tries
  /// again. Any failure before data has been shown, or on a refresh caused by
  /// a change, is still delivered as an error.
  Stream<T> watch<T>(Set<ApiTopic> topics, Future<T> Function() fetch) {
    late StreamController<T> controller;
    StreamSubscription<ApiTopic>? subscription;
    StreamSubscription<void>? backgroundSubscription;
    var inFlight = false;
    var queued = false;
    var queuedInBackground = true;
    var hasValue = false;

    Future<void> load({bool background = false}) async {
      // One request at a time per stream. A mutation that bumps several
      // topics at once would otherwise start a fetch for each of them.
      if (inFlight) {
        queuedInBackground = queued
            ? queuedInBackground && background
            : background;
        queued = true;
        return;
      }
      inFlight = true;
      try {
        final value = await fetch();
        hasValue = true;
        if (!controller.isClosed) controller.add(value);
      } catch (error, stack) {
        final keepShownData = background && hasValue;
        if (!keepShownData && !controller.isClosed) {
          controller.addError(error, stack);
        }
      } finally {
        inFlight = false;
        if (queued) {
          queued = false;
          await load(background: queuedInBackground);
        }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = revisions.changesTo(topics).listen((_) => load());
        backgroundSubscription = revisions.backgroundRefreshes.listen(
          (_) => load(background: true),
        );
        load();
      },
      onCancel: () async {
        await subscription?.cancel();
        await backgroundSubscription?.cancel();
        subscription = null;
        backgroundSubscription = null;
      },
    );
    return controller.stream;
  }

  Future<void> close() async {
    _http.close();
    await revisions.dispose();
  }

  // ---- plumbing ----------------------------------------------------------

  /// Uploads raw bytes — a photo — rather than JSON. A phone photo encoded
  /// into JSON would be a third larger for nothing.
  Future<Map<String, Object?>> postBytes(
    String path,
    List<int> bytes, {
    required String contentType,
    Map<String, Object?>? query,
    Set<ApiTopic> bumps = const {},
    Duration uploadTimeout = const Duration(minutes: 2),
  }) async {
    final response = await _exchange(
      'POST',
      path,
      query: query,
      bytes: bytes,
      contentType: contentType,
      wait: uploadTimeout,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (bumps.isNotEmpty) revisions.bump(bumps);
      return _decodeBody(response);
    }
    throw _failureFrom(response, 'POST', path);
  }

  /// Downloads raw bytes — an attached photo — rather than JSON.
  Future<({List<int> bytes, String? contentType})> getBytes(String path) async {
    final response = await _exchange('GET', path);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return (
        bytes: response.bodyBytes,
        contentType: response.headers['content-type'],
      );
    }
    throw _failureFrom(response, 'GET', path);
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    Set<ApiTopic> bumps = const {},
  }) async {
    final response = await _exchange(method, path, body: body, query: query);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // The write succeeded, so tell the lists. Done before returning, so a
      // caller that immediately reads a list sees the new data.
      if (bumps.isNotEmpty) revisions.bump(bumps);
      return _decodeBody(response);
    }

    throw _failureFrom(response, method, path);
  }

  /// One round trip: authorisation, body, timeout, and connection failures
  /// turned into a [StorageFailure]. Status codes are the caller's business.
  Future<http.Response> _exchange(
    String method,
    String path, {
    Object? body,
    Map<String, Object?>? query,
    List<int>? bytes,
    String? contentType,
    Duration? wait,
  }) async {
    final request = http.Request(method, _resolve(path, query));
    final token = _tokens.token;
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (bytes != null) {
      request.headers['content-type'] =
          contentType ?? 'application/octet-stream';
      request.bodyBytes = bytes;
    } else if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final limit = wait ?? timeout;

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _http.send(request).timeout(limit),
      );
    } on TimeoutException {
      throw StorageFailure(
        'The server did not answer in time.',
        details: '$method $path timed out after ${limit.inSeconds}s.',
      );
    } on http.ClientException catch (error) {
      // The only connection failure caught, and deliberately so. This file
      // must compile for the browser, where `dart:io` and its
      // SocketException do not exist; `package:http` already wraps a refused
      // or dropped connection in a ClientException on every platform.
      throw StorageFailure(
        _unreachable,
        details: '$method $path: ${error.message}',
      );
    }
    return response;
  }

  static const String _unreachable =
      'Cannot reach the server. Check the connection and try again.';

  Uri _resolve(String path, Map<String, Object?>? query) {
    final resolved = baseUrl.resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
    if (query == null || query.isEmpty) return resolved;

    final parameters = <String, Object>{};
    query.forEach((key, value) {
      // Null values are omitted rather than sent as "null", which the server
      // would read as that literal text.
      if (value == null) return;
      if (value is DateTime) {
        // Always ISO-8601 UTC. `'$dateTime'` would render a local-time string
        // with a space in it, which is a different instant and a different
        // format from the one the server parses.
        parameters[key] = value.toUtc().toIso8601String();
      } else if (value is Iterable) {
        // Repeated parameters: ?type=a&type=b. An empty collection means "no
        // filter" and is left out entirely.
        final items = [for (final entry in value) '$entry'];
        if (items.isNotEmpty) parameters[key] = items;
      } else {
        parameters[key] = '$value';
      }
    });
    if (parameters.isEmpty) return resolved;
    return resolved.replace(
      queryParameters: {...resolved.queryParametersAll, ...parameters},
    );
  }

  Map<String, Object?> _decodeBody(http.Response response) {
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) return decoded;
      throw StorageFailure(
        'The server sent an unexpected reply.',
        details: 'Expected a JSON object, got ${decoded.runtimeType}.',
      );
    } on FormatException catch (error) {
      throw StorageFailure(
        'The server sent a reply this version cannot read.',
        details: error.message,
      );
    }
  }

  /// Rebuilds the failure the server reported, so the screen can react to it
  /// exactly as it did when the rule ran locally.
  AppFailure _failureFrom(http.Response response, String method, String path) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) {
        final error = decoded['error'];
        if (error is Map<String, Object?>) return FailureCodec.fromJson(error);
      }
    } on FormatException {
      // Fall through: a proxy or a gateway can answer with HTML, and that is
      // not something to show a cashier.
    }

    // No usable body. Say something true about the status rather than
    // inventing a business reason for it.
    final status = response.statusCode;
    if (status == 401) {
      return const AuthFailure('Your session has ended. Please sign in again.');
    }
    if (status == 403) {
      return const PermissionFailure('You do not have permission to do this.');
    }
    if (status == 404) {
      return NotFoundFailure(
        'That record no longer exists.',
        details: '$method $path returned 404.',
      );
    }
    return StorageFailure(
      'The server could not complete this request.',
      details: '$method $path returned $status.',
    );
  }
}
