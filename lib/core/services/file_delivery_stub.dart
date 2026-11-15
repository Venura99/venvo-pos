import 'dart:typed_data';

/// Fallback for a platform with neither a browser nor a file system. There is
/// no such platform this application builds for; this exists so the
/// conditional import always resolves to something, and says so if reached.
Future<String?> saveBytes({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) => throw UnsupportedError('Saving files is not supported on this platform.');
