/// Source of the current time.
///
/// Every timestamp written to the database goes through a [Clock] rather than
/// calling `DateTime.now()` directly, so that tests can post a sequence of
/// documents at controlled instants and assert on date-filtered reports.
///
/// Stored instants are always UTC; the UI converts to local time for display.
abstract class Clock {
  const Clock();

  DateTime nowUtc();

  /// Midnight at the start of the local day containing [instant], expressed in
  /// UTC. Used for day-bounded report filters.
  DateTime startOfLocalDay(DateTime instant) {
    final local = instant.toLocal();
    return DateTime(local.year, local.month, local.day).toUtc();
  }

  DateTime endOfLocalDay(DateTime instant) {
    final local = instant.toLocal();
    return DateTime(
      local.year,
      local.month,
      local.day,
      23,
      59,
      59,
      999,
    ).toUtc();
  }

  DateTime today() => startOfLocalDay(nowUtc());
}

class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();
}

/// Clock whose time only moves when a test moves it.
class FixedClock extends Clock {
  FixedClock(this._now);

  DateTime _now;

  @override
  DateTime nowUtc() => _now.toUtc();

  void set(DateTime instant) => _now = instant;

  void advance(Duration by) => _now = _now.add(by);
}
