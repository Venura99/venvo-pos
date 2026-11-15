import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/design_tokens.dart';
import 'auth_controller.dart';
import 'auth_scaffold.dart';

/// Sign-in. The router sends every unauthenticated route here.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(authControllerProvider.notifier)
        .signIn(
          username: _usernameController.text,
          password: _passwordController.text,
        );
    // On success the router redirects; on failure the error is in auth state.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Sign in',
      subtitle: 'Enter the credentials your administrator gave you.',
      footer: Text(
        'This application stores all data on this computer. '
        'Keep your password private and take regular backups.',
        style: context.text.bodySmall,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _usernameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline, size: 18),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter your username' : null,
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
            ),
            AppSpacing.gapLg,
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Enter your password' : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (state.errorMessage != null) ...[
              AppSpacing.gapLg,
              _ErrorBanner(message: state.errorMessage!),
            ],
            AppSpacing.gapXl,
            FilledButton(
              onPressed: state.isBusy ? null : _submit,
              child: state.isBusy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.dangerContainer,
        borderRadius: AppRadii.smAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: colors.onDangerContainer),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(
                color: colors.onDangerContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown once, on a brand-new installation, to create the administrator.
///
/// No default credentials exist anywhere in the application, so this is the
/// only way the first account comes into being.
class FirstRunScreen extends ConsumerStatefulWidget {
  const FirstRunScreen({super.key});

  @override
  ConsumerState<FirstRunScreen> createState() => _FirstRunScreenState();
}

class _FirstRunScreenState extends ConsumerState<FirstRunScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(authControllerProvider.notifier)
        .createFirstAdministrator(
          fullName: _fullNameController.text,
          username: _usernameController.text,
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return AuthScaffold(
      title: 'Create the administrator account',
      subtitle:
          'This is a new installation. Choose the credentials for the account '
          'that will manage users, settings and backups.',
      maxWidth: 480,
      footer: Text(
        'There is no default password. If you lose these credentials the only '
        'way back in is a database backup, so record them somewhere safe.',
        style: context.text.bodySmall,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _fullNameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline, size: 18),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Enter your name' : null,
            ),
            AppSpacing.gapLg,
            TextFormField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Username',
                helperText: 'Letters, numbers, dots, underscores and hyphens.',
                prefixIcon: Icon(Icons.alternate_email, size: 18),
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.length < 3) {
                  return 'At least 3 characters';
                }
                return null;
              },
            ),
            AppSpacing.gapLg,
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Password',
                helperText: 'At least 8 characters, with letters and numbers.',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: _validatePassword,
            ),
            AppSpacing.gapLg,
            TextFormField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                prefixIcon: Icon(Icons.lock_outline, size: 18),
              ),
              validator: (value) => value != _passwordController.text
                  ? 'The two passwords do not match'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (state.errorMessage != null) ...[
              AppSpacing.gapLg,
              _ErrorBanner(message: state.errorMessage!),
            ],
            AppSpacing.gapXl,
            FilledButton(
              onPressed: state.isBusy ? null : _submit,
              child: state.isBusy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create account and continue'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Forced when an administrator has reset someone's password, and reachable
/// from the account menu at any time.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final changed = await ref
        .read(authControllerProvider.notifier)
        .changeOwnPassword(
          currentPassword: _currentController.text,
          newPassword: _newController.text,
        );
    if (changed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been changed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final forced = state.mustChangePassword;

    return AuthScaffold(
      title: 'Change your password',
      subtitle: forced
          ? 'Your password was reset by an administrator. Choose a new one to '
                'continue.'
          : 'Choose a new password for your account.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _currentController,
              obscureText: _obscure,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Current password',
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) =>
                  (value ?? '').isEmpty ? 'Enter your current password' : null,
            ),
            AppSpacing.gapLg,
            TextFormField(
              controller: _newController,
              obscureText: _obscure,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters, with letters and numbers.',
                prefixIcon: Icon(Icons.lock_reset_outlined, size: 18),
              ),
              validator: _validatePassword,
            ),
            AppSpacing.gapLg,
            TextFormField(
              controller: _confirmController,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                prefixIcon: Icon(Icons.lock_outline, size: 18),
              ),
              validator: (value) => value != _newController.text
                  ? 'The two passwords do not match'
                  : null,
              onFieldSubmitted: (_) => _submit(),
            ),
            if (state.errorMessage != null) ...[
              AppSpacing.gapLg,
              _ErrorBanner(message: state.errorMessage!),
            ],
            AppSpacing.gapXl,
            FilledButton(
              onPressed: state.isBusy ? null : _submit,
              child: const Text('Change password'),
            ),
            if (!forced) ...[
              AppSpacing.gapSm,
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shared password policy validator for the forms above. The same rule is
/// enforced again in the repository, so a bypassed form cannot weaken it.
String? _validatePassword(String? value) {
  final password = value ?? '';
  if (password.length < 8) return 'At least 8 characters';
  if (!password.contains(RegExp(r'[A-Za-z]')) ||
      !password.contains(RegExp(r'\d'))) {
    return 'Must contain both letters and numbers';
  }
  return null;
}
