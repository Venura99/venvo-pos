import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venvo_core/core/api/revision_bus.dart';

import '../providers/core_providers.dart';

/// The company logo, from the public endpoint, so it can be shown on the
/// sign-in screen before anyone has signed in. Null when none is uploaded.
///
/// Re-read whenever settings change (an upload or removal bumps them).
final companyLogoProvider = StreamProvider<Uint8List?>((ref) {
  final api = ref.watch(apiClientProvider);
  return api.watch({ApiTopic.settings}, () async {
    final file = await api.getBytes(
      '/api/v1/branding/logo?t=${DateTime.now().millisecondsSinceEpoch}',
    );
    // An empty reply (204) means no logo has been uploaded.
    return file.bytes.isEmpty ? null : Uint8List.fromList(file.bytes);
  });
});

/// Shows the uploaded logo, or [fallback] while it loads, when there is none,
/// or when it could not be fetched (the app still works without a logo).
class CompanyLogo extends ConsumerWidget {
  const CompanyLogo({
    super.key,
    required this.height,
    required this.fallback,
    this.maxWidth = 180,
    this.onDarkBackground = false,
  });

  final double height;
  final double maxWidth;
  final Widget fallback;

  /// Puts the logo on a white card so a dark logo stays visible on a
  /// coloured background.
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(companyLogoProvider).valueOrNull;
    if (bytes == null) return fallback;
    final image = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height, maxWidth: maxWidth),
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
    if (!onDarkBackground) return image;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: image,
    );
  }
}
