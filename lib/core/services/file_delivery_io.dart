import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Asks where to save, through the system's own dialog.
///
/// On Android the picker writes the bytes itself, through the storage access
/// framework. On the desktop it only returns the chosen path — it accepts the
/// bytes and does nothing with them — so they are written here. Without that
/// the dialog would close, report success, and leave no file behind.
Future<String?> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  final extension = fileName.contains('.') ? fileName.split('.').last : null;
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save $fileName',
    fileName: fileName,
    type: extension == null ? FileType.any : FileType.custom,
    allowedExtensions: extension == null ? null : [extension],
    bytes: bytes,
  );
  if (path == null) return null;

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path;
}
