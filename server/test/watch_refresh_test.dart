import 'dart:async';

import 'package:test/test.dart';
import 'package:venvo_core/core/api/api_client.dart';
import 'package:venvo_core/core/api/revision_bus.dart';

/// The periodic refresh that shows other devices' changes: what it re-reads,
/// and what happens to the data on screen when a re-read fails.
void main() {
  late ApiClient client;

  setUp(() {
    client = ApiClient(
      baseUrl: Uri.parse('http://unused.invalid/'),
      tokens: InMemoryTokenStore(),
    );
  });

  tearDown(() => client.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a background refresh re-reads and delivers new data', () async {
    var n = 0;
    final events = <Object>[];
    final sub = client
        .watch({ApiTopic.invoices}, () async => ++n)
        .listen(events.add, onError: events.add);
    await settle();
    client.revisions.refreshInBackground();
    await settle();
    expect(events, [1, 2]);
    await sub.cancel();
  });

  test('a failed background refresh keeps the data already shown', () async {
    var fail = false;
    final events = <Object>[];
    final sub = client
        .watch({ApiTopic.invoices}, () async {
          if (fail) throw StateError('network down');
          return 'data';
        })
        .listen(events.add, onError: events.add);
    await settle();
    fail = true;
    client.revisions.refreshInBackground();
    await settle();
    expect(events, ['data']);

    // Recovers on the next refresh.
    fail = false;
    client.revisions.refreshInBackground();
    await settle();
    expect(events, ['data', 'data']);
    await sub.cancel();
  });

  test(
    'a failed refresh after a change on this device is still an error',
    () async {
      var fail = false;
      final events = <Object>[];
      final sub = client
          .watch({ApiTopic.invoices}, () async {
            if (fail) throw StateError('network down');
            return 'data';
          })
          .listen(events.add, onError: events.add);
      await settle();
      fail = true;
      client.refresh({ApiTopic.invoices});
      await settle();
      expect(events.last, isA<StateError>());
      await sub.cancel();
    },
  );

  test(
    'a failed first load is an error even if it came from a refresh',
    () async {
      final events = <Object>[];
      final gate = Completer<void>();
      var calls = 0;
      final sub = client
          .watch({ApiTopic.invoices}, () async {
            calls++;
            await gate.future;
            throw StateError('network down');
          })
          .listen(events.add, onError: events.add);
      await settle();
      client.revisions.refreshInBackground(); // queued behind the first load
      gate.complete();
      await settle();
      await settle();
      expect(calls, 2);
      expect(events.whereType<StateError>(), hasLength(2));
      await sub.cancel();
    },
  );
}
