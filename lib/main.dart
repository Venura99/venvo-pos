import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/constants/app_constants.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:window_manager/window_manager.dart';

import 'core/bootstrap/client_bootstrap.dart';
import 'core/bootstrap/client_preferences.dart';
import 'core/providers/core_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _configureWindow();
  final preferences = await SharedClientPreferences.load();
  runApp(VenvoRoot(preferences: preferences));
}

/// True on the platforms that have a window to size and title. A phone and a
/// browser tab do not, and `window_manager` has no implementation for them.
bool get _isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS);

Future<void> _configureWindow() async {
  if (!_isDesktop) return;
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1440, 900),
    minimumSize: Size(
      AppConstants.minWindowWidth,
      AppConstants.minWindowHeight,
    ),
    center: true,
    title: '${AppConstants.appName} - ${AppConstants.companyName}',
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Reaches the server before showing the application.
///
/// The application proper never has to wonder whether it is connected: by the
/// time [VenvoApp] is built there is a [ClientBootstrap], which means the
/// server answered, speaks a version this build understands, and has said
/// whether anybody is signed in. Until then this shows either a progress
/// indicator or the screen that asks for the server's address.
class VenvoRoot extends StatefulWidget {
  const VenvoRoot({super.key, required this.preferences});

  final ClientPreferences preferences;

  @override
  State<VenvoRoot> createState() => _VenvoRootState();
}

class _VenvoRootState extends State<VenvoRoot> {
  ClientBootstrap? _bootstrap;
  bool _connecting = false;
  String? _error;
  String? _errorDetail;

  @override
  void initState() {
    super.initState();
    final address = resolveServerUrl(widget.preferences);
    if (address != null) _connect(address, remember: false);
  }

  @override
  void dispose() {
    _bootstrap?.dispose();
    super.dispose();
  }

  /// Tries [address]. [remember] is set when somebody typed it, so that an
  /// address that works is kept and one that does not is never stored.
  Future<void> _connect(Uri address, {required bool remember}) async {
    setState(() {
      _connecting = true;
      _error = null;
      _errorDetail = null;
    });
    try {
      final bootstrap = await ClientBootstrap.connect(
        serverUrl: address,
        preferences: widget.preferences,
      );
      if (remember) await widget.preferences.setServerUrl('$address');
      if (!mounted) {
        await bootstrap.dispose();
        return;
      }
      setState(() {
        _bootstrap = bootstrap;
        _connecting = false;
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = failure.message;
        _errorDetail = failure.details;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = 'Could not connect to the server.';
        _errorDetail = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = _bootstrap;
    if (bootstrap != null) {
      return ProviderScope(
        overrides: [clientBootstrapProvider.overrideWithValue(bootstrap)],
        child: const VenvoApp(),
      );
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: ConnectScreen(
        initialAddress:
            widget.preferences.serverUrl ??
            resolveServerUrl(widget.preferences)?.toString() ??
            '',
        isConnecting: _connecting,
        error: _error,
        errorDetail: _errorDetail,
        onConnect: (address) => _connect(address, remember: true),
      ),
    );
  }
}

/// Asks which server to use, and says plainly when one cannot be reached.
///
/// A browser user normally never sees this — the page was served by the
/// server, so its address is already known. It appears on a device that has
/// not been pointed at a server yet, and whenever the server does not answer:
/// with no local copy of the data, there is nothing useful the application
/// can show until it does.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.initialAddress,
    required this.isConnecting,
    required this.onConnect,
    this.error,
    this.errorDetail,
  });

  final String initialAddress;
  final bool isConnecting;
  final String? error;
  final String? errorDetail;
  final void Function(Uri address) onConnect;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController _address = TextEditingController(
    text: widget.initialAddress,
  );
  String? _inputError;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    final address = normaliseServerUrl(_address.text);
    if (address == null) {
      setState(
        () => _inputError =
            'Enter the server address, for example pos.example.com',
      );
      return;
    }
    setState(() => _inputError = null);
    widget.onConnect(address);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppConstants.appName,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to your server',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Everything is kept on the server, so every device signed '
                  'in to it sees the same data.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _address,
                  enabled: !widget.isConnecting,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Server address',
                    hintText: 'pos.example.com',
                    errorText: _inputError,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: widget.isConnecting ? null : _submit,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: widget.isConnecting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Connect'),
                  ),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.error!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.errorDetail != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      widget.errorDetail!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class VenvoApp extends ConsumerWidget {
  const VenvoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Scroll behaviour that works with a mouse wheel, a trackpad and a
      // finger, with no overscroll glow.
      scrollBehavior: const MaterialScrollBehavior(),
    );
  }
}
