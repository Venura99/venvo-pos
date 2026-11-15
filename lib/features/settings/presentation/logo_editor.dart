import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/errors/failures.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/company_logo.dart';
import '../../../core/widgets/confirm_dialog.dart';

/// The company logo in Settings: a preview, and buttons to upload a new one
/// or remove it. Saved straight away, separately from the text fields.
class LogoEditor extends ConsumerStatefulWidget {
  const LogoEditor({super.key, required this.canEdit});

  final bool canEdit;

  @override
  ConsumerState<LogoEditor> createState() => _LogoEditorState();
}

class _LogoEditorState extends ConsumerState<LogoEditor> {
  bool _busy = false;

  Future<void> _upload() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final isPng = file.name.toLowerCase().endsWith('.png');
    await _run(
      () => ref
          .read(settingsServiceProvider)
          .uploadLogo(bytes, contentType: isPng ? 'image/png' : 'image/jpeg'),
      done: 'Logo updated.',
    );
  }

  Future<void> _remove() async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Remove the logo?',
      message:
          'Documents and the sign-in screen go back to showing the business '
          'name only. You can upload a logo again at any time.',
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (confirmed != true) return;
    await _run(
      () => ref.read(settingsServiceProvider).removeLogo(),
      done: 'Logo removed.',
    );
  }

  Future<void> _run(
    Future<void> Function() action, {
    required String done,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _busy = true);
    try {
      await action();
      messenger?.showSnackBar(SnackBar(content: Text(done)));
    } on AppFailure catch (failure) {
      messenger?.showSnackBar(
        SnackBar(backgroundColor: errorColor, content: Text(failure.message)),
      );
    } catch (error) {
      messenger?.showSnackBar(
        SnackBar(
          backgroundColor: errorColor,
          content: Text('The logo could not be saved: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = ref.watch(companyLogoProvider);
    final hasLogo = logo.valueOrNull != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          height: 72,
          width: 200,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: context.colors.outlineVariant),
            borderRadius: AppRadii.mdAll,
          ),
          child: logo.isLoading && !logo.hasValue
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : CompanyLogo(
                  height: 56,
                  maxWidth: 184,
                  fallback: Text(
                    logo.hasError ? 'Could not load the logo' : 'No logo yet',
                    style: context.text.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                ),
        ),
        AppSpacing.hGapLg,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Company logo', style: context.text.titleSmall),
              Text(
                'PNG or JPEG, up to 2 MB. Shown on the sign-in screen, the '
                'menu and printed documents.',
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              if (widget.canEdit) ...[
                AppSpacing.gapSm,
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _upload,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_outlined, size: 18),
                      label: Text(hasLogo ? 'Change logo' : 'Upload logo'),
                    ),
                    if (hasLogo)
                      TextButton.icon(
                        onPressed: _busy ? null : _remove,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
