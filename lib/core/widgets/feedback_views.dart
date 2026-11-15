import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:venvo_core/core/errors/failures.dart';
import '../theme/design_tokens.dart';

/// Placeholder shown when a list or table has nothing to display, with an
/// optional call to action so the user is never left at a dead end.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: context.colors.onSurfaceVariant),
              AppSpacing.gapLg,
              Text(
                title,
                style: context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message != null) ...[
                AppSpacing.gapSm,
                Text(
                  message!,
                  style: context.text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[AppSpacing.gapLg, action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows a failed operation with its message and a retry affordance.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.compact = false,
  });

  final Object error;
  final VoidCallback? onRetry;
  final bool compact;

  /// Turns any thrown object into a sentence worth showing a user. Expected
  /// business failures carry their own wording; anything else is reported as
  /// unexpected rather than dumped raw.
  static String describe(Object error) {
    if (error is AppFailure) return error.message;
    return 'Something went wrong. $error';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.statusColors;
    final message = describe(error);

    if (compact) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: colors.danger),
          AppSpacing.hGapSm,
          Expanded(
            child: Text(
              message,
              style: context.text.bodySmall?.copyWith(color: colors.danger),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 40, color: colors.danger),
              AppSpacing.gapLg,
              Text(
                'This did not work',
                style: context.text.titleMedium,
                textAlign: TextAlign.center,
              ),
              AppSpacing.gapSm,
              Text(
                message,
                style: context.text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (error is AppFailure &&
                  (error as AppFailure).details != null) ...[
                AppSpacing.gapSm,
                Text(
                  (error as AppFailure).details!,
                  style: context.text.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              if (onRetry != null) ...[
                AppSpacing.gapLg,
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders an [AsyncValue] with consistent loading and error presentation, so
/// no screen has to invent its own.
class AsyncValueView<T> extends StatelessWidget {
  const AsyncValueView({
    super.key,
    required this.value,
    required this.builder,
    this.onRetry,
    this.loading,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    return value.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      data: (data) => builder(context, data),
      loading: () =>
          loading ?? const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorView(error: error, onRetry: onRetry),
    );
  }
}

/// Shows a message in a snack bar using the app's error wording rules.
void showFailureSnackBar(BuildContext context, Object error) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(ErrorView.describe(error)),
      backgroundColor: Theme.of(context).colorScheme.error,
      showCloseIcon: true,
    ),
  );
}

void showSuccessSnackBar(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.showSnackBar(SnackBar(content: Text(message), showCloseIcon: true));
}
