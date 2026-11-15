// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AttachmentInfo _$AttachmentInfoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AttachmentInfo', json, ($checkedConvert) {
      final val = AttachmentInfo(
        id: $checkedConvert('id', (v) => (v as num).toInt()),
        fileName: $checkedConvert('fileName', (v) => v as String),
        mimeType: $checkedConvert('mimeType', (v) => v as String),
        byteSize: $checkedConvert('byteSize', (v) => (v as num).toInt()),
        uploadedAt: $checkedConvert(
          'uploadedAt',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$AttachmentInfoToJson(AttachmentInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'fileName': instance.fileName,
      'mimeType': instance.mimeType,
      'byteSize': instance.byteSize,
      'uploadedAt': instance.uploadedAt.toIso8601String(),
    };
