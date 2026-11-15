import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/errors/failures.dart';
import 'package:venvo_core/features/authentication/api/auth_api.dart';
import 'package:venvo_core/features/authentication/domain/authenticated_user.dart';

import '../../../core/providers/core_providers.dart';

/// Sign-in, account creation and password changes, on the server.
///
/// Keeps the name it had when it was a local repository: the methods are the
/// same, so the screens that call it did not have to change.
final authRepositoryProvider = Provider<AuthApi>(
  (ref) => ref.watch(clientBootstrapProvider).auth,
);

/// Session state for the whole application. The router redirects on it and the
/// shell reads the signed-in user from it.
class AuthState {
  const AuthState({
    this.user,
    required this.needsFirstRun,
    this.isBusy = false,
    this.errorMessage,
  });

  final AuthenticatedUser? user;

  /// No account exists yet, so the first-run screen must create one.
  final bool needsFirstRun;
  final bool isBusy;
  final String? errorMessage;

  bool get isSignedIn => user != null;

  /// A signed-in user who still has to choose a new password sees only the
  /// change-password screen.
  bool get mustChangePassword => user?.mustChangePassword ?? false;

  AuthState copyWith({
    AuthenticatedUser? user,
    bool clearUser = false,
    bool? needsFirstRun,
    bool? isBusy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      needsFirstRun: needsFirstRun ?? this.needsFirstRun,
      isBusy: isBusy ?? this.isBusy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    final bootstrap = ref.watch(clientBootstrapProvider);
    // A session token kept from last time has already been checked against the
    // server, so a browser refresh or reopening the app carries on signed in.
    return AuthState(
      user: bootstrap.restoredUser,
      needsFirstRun: bootstrap.needsFirstRunSetup,
    );
  }

  AuthApi get _repository => ref.read(authRepositoryProvider);

  Future<bool> signIn({
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repository.signIn(
        username: username,
        password: password,
      );
      await ref.read(clientBootstrapProvider).loadSettingsFor(user);
      state = AuthState(user: user, needsFirstRun: false);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(isBusy: false, errorMessage: failure.message);
      return false;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: 'Could not sign in: $error',
      );
      return false;
    }
  }

  Future<bool> createFirstAdministrator({
    required String fullName,
    required String username,
    required String password,
  }) async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final user = await _repository.createFirstAdministrator(
        fullName: fullName,
        username: username,
        password: password,
      );
      await ref.read(clientBootstrapProvider).loadSettingsFor(user);
      state = AuthState(user: user, needsFirstRun: false);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(isBusy: false, errorMessage: failure.message);
      return false;
    } catch (error) {
      state = state.copyWith(
        isBusy: false,
        errorMessage: 'Could not create the account: $error',
      );
      return false;
    }
  }

  Future<bool> changeOwnPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = state.user;
    if (user == null) return false;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repository.changeOwnPassword(
        user: user,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      final updated = user.copyWith(mustChangePassword: false);
      // The server kept everything else closed until now, so this is the
      // first moment the business settings can be fetched for this account.
      await ref.read(clientBootstrapProvider).loadSettingsFor(updated);
      state = state.copyWith(user: updated, isBusy: false, clearError: true);
      return true;
    } on AppFailure catch (failure) {
      state = state.copyWith(isBusy: false, errorMessage: failure.message);
      return false;
    }
  }

  Future<void> signOut() async {
    final user = state.user;
    if (user != null) {
      await _repository.signOut(user);
    }
    // The next person at this device may be allowed to see different things,
    // and must not inherit what this one loaded.
    ref.read(clientBootstrapProvider).settings.clear();
    state = const AuthState(needsFirstRun: false);
  }

  /// Re-reads the signed-in user, for use after their roles were changed.
  Future<void> refreshPermissions() async {
    final user = state.user;
    if (user == null) return;
    state = state.copyWith(user: await _repository.refresh(user.id));
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The signed-in user, or null. Convenience for widgets and services.
final currentUserProvider = Provider<AuthenticatedUser?>(
  (ref) => ref.watch(authControllerProvider).user,
);

/// The signed-in user, asserting that there is one. Used inside the shell,
/// which is only reachable when signed in.
final requireCurrentUserProvider = Provider<AuthenticatedUser>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    throw StateError('No user is signed in.');
  }
  return user;
});
