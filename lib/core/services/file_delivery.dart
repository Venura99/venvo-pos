import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'file_delivery_stub.dart'
    if (dart.library.js_interop) 'file_delivery_web.dart'
    if (dart.library.io) 'file_delivery_io.dart'
    as platform;

/// Gets a generated file out of the application and into the user's hands.
///
/// The desktop build wrote exports into a folder under the data directory and
/// offered to open it. That cannot be the general answer: a browser has no
/// folder to write to, and on a phone a folder nobody can find is not a
/// delivery. So the bytes are built in memory and handed over in whatever way
/// the device has for it.
class FileDelivery {
  const FileDelivery._();

  /// Saves [bytes] as [fileName].
  ///
  /// In a browser this is a download. On Android and the desktop it is the
  /// system's save dialog, so the user chooses where it goes. Returns a
  /// description of where it went, or null if the user cancelled — which is
  /// not an error and is not reported as one.
  static Future<String?> save({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) =>
      platform.saveBytes(bytes: bytes, fileName: fileName, mimeType: mimeType);

  /// Sends a PDF to the system print dialog.
  ///
  /// The same call works in a browser, on Android and on Windows, and each
  /// of those dialogs also offers "save as PDF" — so this covers both printing
  /// an invoice for the customer in front of you and keeping a copy.
  static Future<void> printPdf({
    required Uint8List bytes,
    required String documentName,
  }) async {
    await Printing.layoutPdf(name: documentName, onLayout: (_) async => bytes);
  }
}
