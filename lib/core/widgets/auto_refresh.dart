import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/authentication/presentation/auth_controller.dart';
import '../providers/core_providers.dart';

/// Re-reads the screens on display every [interval], so that a change made
/// on another device (an agent's sale, a payment entered at the office)
/// appears here without anyone having to leave the page and come back.
///
/// Only while someone is signed in and the app is in the foreground: a
/// phone in a pocket should not keep calling the server. Coming back to the
/// app refreshes at once.
class AutoRefresh extends ConsumerStatefulWidget {
  const AutoRefresh({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 30),
  });

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<AutoRefresh> createState() => _AutoRefreshState();
}

class _AutoRefreshState extends ConsumerState<AutoRefresh>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final wasForeground = _foreground;
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !wasForeground) _refresh();
  }

  void _refresh() {
    if (!mounted || !_foreground) return;
    if (!ref.read(authControllerProvider).isSignedIn) return;
    ref.read(apiClientProvider).revisions.refreshInBackground();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
