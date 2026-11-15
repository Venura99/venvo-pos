import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_static/shelf_static.dart';

/// Puts the built web app in front of the API, on one address.
///
/// Requests are split by path, not cascaded: `/api/...` and `/health` go to
/// the API, everything else to the web app. Cascading would be wrong here —
/// the API answers an unknown path without a token with a 401, not a 404, so
/// the web app behind it would never be reached.
///
/// The page and the API sharing one origin is what lets a browser user just
/// open the server's address: the app finds its server from the address it
/// was loaded from, and there are no cross-origin rules to get wrong.
Handler withWebApp({required Handler api, required Directory webRoot}) {
  final files = createStaticHandler(
    webRoot.path,
    defaultDocument: 'index.html',
  );
  final index = File('${webRoot.path}/index.html');

  return (Request request) async {
    final path = request.url.path;
    if (path == 'api' || path.startsWith('api/') || path == 'health') {
      return api(request);
    }

    final response = await files(request);
    if (response.statusCode != 404) {
      return _noCacheForEntryPoints(path, response);
    }

    // A path the app knows about but no file matches — a page reloaded deep
    // inside the app — gets the app itself, which then routes to it.
    return Response.ok(
      index.openRead(),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
      },
    );
  };
}

/// The entry points must be re-checked on every load, or a browser keeps
/// running last week's app against this week's server. The hashed assets they
/// point at can be cached freely.
Response _noCacheForEntryPoints(String path, Response response) {
  const entryPoints = {
    '',
    'index.html',
    'flutter_bootstrap.js',
    'flutter_service_worker.js',
    'main.dart.js',
    'version.json',
    'manifest.json',
  };
  if (!entryPoints.contains(path)) return response;
  return response.change(headers: {'cache-control': 'no-cache'});
}
