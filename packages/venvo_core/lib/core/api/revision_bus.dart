import 'dart:async';

/// The areas of data a screen can be watching.
///
/// A mutation bumps the topics it affects and every stream watching one of
/// them re-fetches. This is what replaces the behaviour the offline build got
/// for free: a Drift query stream re-ran itself whenever its tables were
/// written to, so a list refreshed the moment a form saved. Over HTTP there is
/// nothing watching the tables, so the writes say what they touched.
enum ApiTopic {
  products,
  categories,
  agents,
  shops,
  employees,
  locations,
  stock,
  invoices,
  payments,
  returns,
  finance,
  users,
  settings,
}

/// Broadcasts "this area of data changed".
///
/// Deliberately not a general event bus: the only payload is a revision
/// number, so nothing can come to depend on the contents of a notification
/// and get out of step with the server. A listener's only correct response is
/// to ask the server again.
class RevisionBus {
  final Map<ApiTopic, int> _revisions = {};
  final StreamController<ApiTopic> _changes =
      StreamController<ApiTopic>.broadcast();

  int revisionOf(ApiTopic topic) => _revisions[topic] ?? 0;

  /// Records a change to each of [topics] and notifies listeners.
  void bump(Iterable<ApiTopic> topics) {
    for (final topic in topics) {
      _revisions[topic] = revisionOf(topic) + 1;
      if (!_changes.isClosed) _changes.add(topic);
    }
  }

  /// Fires whenever any of [topics] changes.
  Stream<ApiTopic> changesTo(Set<ApiTopic> topics) =>
      _changes.stream.where(topics.contains);

  final StreamController<void> _background = StreamController<void>.broadcast();

  /// Asks every watching screen to re-read from the server, because another
  /// device may have changed something. Unlike [bump] this is not caused by
  /// a write on this device, so a failure to re-read keeps the data already
  /// shown rather than replacing it with an error (see `ApiClient.watch`).
  void refreshInBackground() {
    if (!_background.isClosed) _background.add(null);
  }

  Stream<void> get backgroundRefreshes => _background.stream;

  Future<void> dispose() async {
    await _changes.close();
    await _background.close();
  }
}
