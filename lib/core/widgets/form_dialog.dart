import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:venvo_core/core/errors/failures.dart';
import '../theme/design_tokens.dart';

/// Standard shell for a create/edit form.
///
/// Owns the [Form], the submit button's busy state and the error banner, so
/// every master-data form behaves the same way: validate, submit, show the
/// failure in place if there is one, and pop with the result only on success.
///
/// A failure is shown inside the dialog rather than as a snack bar, because the
/// user needs to see it next to the fields they have to correct, and the dialog
/// stays open with their input intact.
class AppFormDialog extends StatefulWidget {
  const AppFormDialog({
    super.key,
    required this.title,
    required this.child,
    required this.onSubmit,
    this.subtitle,
    this.submitLabel = 'Save',
    this.cancelLabel = 'Cancel',
    this.width = 560,
    this.extraActions = const [],
  });

  final String title;
  final String? subtitle;

  /// The fields. Wrapped in a [Form] by this widget.
  final Widget child;

  /// Runs after validation passes. Throw an [AppFailure] to show its message
  /// in the dialog; return normally to close it.
  final Future<void> Function() onSubmit;

  final String submitLabel;
  final String cancelLabel;
  final double width;

  /// Buttons placed to the left of cancel, for actions such as Archive.
  final List<Widget> extraActions;

  /// Opens the dialog and resolves to true when it submitted successfully.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required Widget child,
    required Future<void> Function() onSubmit,
    String? subtitle,
    String submitLabel = 'Save',
    double width = 560,
    List<Widget> extraActions = const [],
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AppFormDialog(
        title: title,
        subtitle: subtitle,
        submitLabel: submitLabel,
        width: width,
        extraActions: extraActions,
        onSubmit: onSubmit,
        child: child,
      ),
    );
    return result ?? false;
  }

  @override
  State<AppFormDialog> createState() => _AppFormDialogState();
}

class _AppFormDialogState extends State<AppFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  String? _errorMessage;
  String? _errorDetails;

  Future<void> _submit() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
      _errorDetails = null;
    });

    try {
      await widget.onSubmit();
      if (mounted) Navigator.of(context).pop(true);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = failure.message;
        _errorDetails = failure.details;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = 'This could not be saved.';
        _errorDetails = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (!_isSaving) Navigator.of(context).pop(false);
        },
        // Ctrl+Enter submits from anywhere in the form, including a multi-line
        // notes field where plain Enter inserts a newline.
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _submit,
      },
      child: AlertDialog(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            if (widget.subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(widget.subtitle!, style: context.text.bodySmall),
            ],
          ],
        ),
        content: SizedBox(
          width: widget.width,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    _ErrorBanner(
                      message: _errorMessage!,
                      details: _errorDetails,
                    ),
                    AppSpacing.gapLg,
                  ],
                  widget.child,
                ],
              ),
            ),
          ),
        ),
        actions: [
          ...widget.extraActions,
          if (widget.extraActions.isNotEmpty) const Spacer(),
          TextButton(
            onPressed: _isSaving
                ? null
                : () => Navigator.of(context).pop(false),
            child: Text(widget.cancelLabel),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _submit,
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.details});

  final String message;
  final String? details;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: context.text.bodyMedium?.copyWith(
                    color: colors.onDangerContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (details != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    details!,
                    style: context.text.bodySmall?.copyWith(
                      color: colors.onDangerContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled group of fields inside a form.
class FormSection extends StatelessWidget {
  const FormSection({
    super.key,
    required this.title,
    required this.children,
    this.description,
  });

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.toUpperCase(),
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(description!, style: context.text.bodySmall),
        ],
        AppSpacing.gapMd,
        ...children,
      ],
    );
  }
}

/// Places fields side by side with even spacing. Collapses to a single column
/// when the dialog is too narrow to keep them readable.
class FormRow extends StatelessWidget {
  const FormRow({super.key, required this.children, this.minFieldWidth = 180});

  final List<Widget> children;
  final double minFieldWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fitsInARow =
            constraints.maxWidth >= minFieldWidth * children.length;

        if (!fitsInARow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0) AppSpacing.gapLg,
                children[index],
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0) AppSpacing.hGapLg,
              Expanded(child: children[index]),
            ],
          ],
        );
      },
    );
  }
}
