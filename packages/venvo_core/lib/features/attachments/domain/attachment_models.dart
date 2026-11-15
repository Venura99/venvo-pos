import 'package:json_annotation/json_annotation.dart';

part 'attachment_models.g.dart';

/// An attached file, as anyone looking at the record sees it.
///
/// Deliberately without the path on the server's disk: a client has no use for
/// it, and it says more about the server than a client needs to know.
@JsonSerializable()
class AttachmentInfo {
  const AttachmentInfo({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.byteSize,
    required this.uploadedAt,
  });

  final int id;
  final String fileName;
  final String mimeType;
  final int byteSize;
  final DateTime uploadedAt;

  bool get isImage => mimeType.startsWith('image/');

  factory AttachmentInfo.fromJson(Map<String, dynamic> json) =>
      _$AttachmentInfoFromJson(json);

  Map<String, dynamic> toJson() => _$AttachmentInfoToJson(this);
}
