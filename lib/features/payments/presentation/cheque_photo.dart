import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:venvo_core/features/attachments/domain/attachment_models.dart';
import 'package:venvo_core/features/backup/domain/backup_models.dart';
import 'package:venvo_core/features/payments/api/cheque_extras_api.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/services/file_delivery.dart';
import '../../../core/theme/design_tokens.dart';
import '../../../core/widgets/feedback_views.dart';

/// A photo or scan of a cheque, picked but not yet uploaded.
class PickedChequePhoto {
  const PickedChequePhoto({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

final chequeExtrasApiProvider = Provider<ChequeExtrasApi>(
  (ref) => ChequeExtrasApi(ref.watch(apiClientProvider)),
);

/// Whether this device can open its camera directly. The browser's file input
/// offers the camera itself on a phone, so web goes through "choose".
bool get _hasCamera =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Asks for a cheque photo: the camera on a phone, or a file anywhere.
/// Returns null when the person backs out.
Future<PickedChequePhoto?> pickChequePhoto(BuildContext context) async {
  var useCamera = false;
  if (_hasCamera) {
    final choice = await showModalBottomSheet<bool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return null;
    useCamera = choice;
  }

  if (_hasCamera) {
    final image = await ImagePicker().pickImage(
      source: useCamera ? ImageSource.camera : ImageSource.gallery,
      // Big enough to read the cheque number and signature, small enough to
      // upload over a phone connection from a shop.
      maxWidth: 2000,
      imageQuality: 80,
    );
    if (image == null) return null;
    return PickedChequePhoto(
      bytes: await image.readAsBytes(),
      fileName: image.name,
    );
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    withData: true,
  );
  final file = result?.files.singleOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null) return null;
  return PickedChequePhoto(bytes: bytes, fileName: file.name);
}

/// The photos attached to one cheque, with a button to add another.
class ChequePhotosDialog extends ConsumerStatefulWidget {
  const ChequePhotosDialog({
    super.key,
    required this.chequeId,
    required this.title,
    required this.canAttach,
  });

  final int chequeId;
  final String title;
  final bool canAttach;

  static Future<void> show(
    BuildContext context, {
    required int chequeId,
    required String title,
    required bool canAttach,
  }) => showDialog<void>(
    context: context,
    builder: (context) => ChequePhotosDialog(
      chequeId: chequeId,
      title: title,
      canAttach: canAttach,
    ),
  );

  @override
  ConsumerState<ChequePhotosDialog> createState() => _ChequePhotosDialogState();
}

class _ChequePhotosDialogState extends ConsumerState<ChequePhotosDialog> {
  late Future<List<AttachmentInfo>> _attachments;
  late Future<List<ChequeReminderAttempt>> _reminders;
  bool _uploading = false;

  ChequeExtrasApi get _api => ref.read(chequeExtrasApiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _attachments = _api.chequeAttachments(widget.chequeId);
    _reminders = _api.reminderHistory(widget.chequeId);
  }

  Future<void> _attach() async {
    final photo = await pickChequePhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      await _api.uploadChequeImage(
        chequeId: widget.chequeId,
        bytes: photo.bytes,
        fileName: photo.fileName,
      );
      if (mounted) showSuccessSnackBar(context, 'Cheque photo attached.');
    } catch (error) {
      if (mounted) showFailureSnackBar(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _uploading = false;
          _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: size.width < 720 ? size.width : 680,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FutureBuilder<List<AttachmentInfo>>(
                future: _attachments,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ErrorView(error: snapshot.error!);
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final files = snapshot.data!;
                  if (files.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Text('No photo has been attached to this cheque.'),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final file in files) _AttachmentTile(file: file),
                    ],
                  );
                },
              ),
              AppSpacing.gapLg,
              Text(
                'WhatsApp reminders',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              AppSpacing.gapSm,
              FutureBuilder<List<ChequeReminderAttempt>>(
                future: _reminders,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(ErrorView.describe(snapshot.error!));
                  }
                  if (!snapshot.hasData) return const LinearProgressIndicator();
                  final attempts = snapshot.data!;
                  if (attempts.isEmpty) {
                    return const Text('No reminder has been sent yet.');
                  }
                  final format = DateFormat('d MMM yyyy, h:mm a');
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final attempt in attempts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Text(
                            '${format.format(attempt.attemptedAt.toLocal())} '
                            '→ +${attempt.recipient}: '
                            '${attempt.delivered ? 'sent' : 'failed — ${attempt.error ?? 'no reason given'}'}',
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.canAttach)
          FilledButton.tonalIcon(
            onPressed: _uploading ? null : _attach,
            icon: _uploading
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_a_photo_outlined),
            label: Text(_uploading ? 'Uploading…' : 'Attach a photo'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AttachmentTile extends ConsumerStatefulWidget {
  const _AttachmentTile({required this.file});

  final AttachmentInfo file;

  @override
  ConsumerState<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends ConsumerState<_AttachmentTile> {
  late final Future<Uint8List> _bytes = ref
      .read(chequeExtrasApiProvider)
      .attachmentBytes(widget.file.id);

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorView(error: snapshot.error!);
          if (!snapshot.hasData) {
            return const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final bytes = snapshot.data!;
          final caption = Row(
            children: [
              Expanded(
                child: Text(
                  '${file.fileName} · ${formatBytes(file.byteSize)} · '
                  '${DateFormat('d MMM yyyy').format(file.uploadedAt.toLocal())}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    await FileDelivery.save(
                      bytes: bytes,
                      fileName: file.fileName,
                      mimeType: file.mimeType,
                    );
                  } catch (error) {
                    if (context.mounted) showFailureSnackBar(context, error);
                  }
                },
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Save'),
              ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (file.isImage)
                ClipRRect(
                  borderRadius: AppRadii.mdAll,
                  child: InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                )
              else
                const ListTile(
                  leading: Icon(Icons.picture_as_pdf_outlined),
                  title: Text('PDF scan — use Save to open it'),
                ),
              caption,
            ],
          );
        },
      ),
    );
  }
}
