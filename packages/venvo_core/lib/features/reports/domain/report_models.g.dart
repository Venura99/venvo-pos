// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'report_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReportValue _$ReportValueFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportValue', json, ($checkedConvert) {
      final val = ReportValue._(
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(_$ReportValueKindEnumMap, v),
        ),
        text: $checkedConvert('text', (v) => v as String?),
        money: $checkedConvert(
          'money',
          (v) => v == null ? null : Money.fromJson((v as num).toInt()),
        ),
        number: $checkedConvert('number', (v) => (v as num?)?.toInt()),
        date: $checkedConvert(
          'date',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        bps: $checkedConvert('bps', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$ReportValueToJson(ReportValue instance) =>
    <String, dynamic>{
      'kind': _$ReportValueKindEnumMap[instance.kind]!,
      'text': ?instance.text,
      'money': ?instance.money?.toJson(),
      'number': ?instance.number,
      'date': ?instance.date?.toIso8601String(),
      'bps': ?instance.bps,
    };

const _$ReportValueKindEnumMap = {
  ReportValueKind.text: 'text',
  ReportValueKind.money: 'money',
  ReportValueKind.integer: 'integer',
  ReportValueKind.date: 'date',
  ReportValueKind.month: 'month',
  ReportValueKind.percent: 'percent',
};

ReportColumn _$ReportColumnFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportColumn', json, ($checkedConvert) {
      final val = ReportColumn(
        label: $checkedConvert('label', (v) => v as String),
        kind: $checkedConvert(
          'kind',
          (v) => $enumDecode(_$ReportValueKindEnumMap, v),
        ),
        width: $checkedConvert('width', (v) => (v as num?)?.toDouble()),
        flex: $checkedConvert('flex', (v) => (v as num?)?.toInt() ?? 1),
        totalled: $checkedConvert('totalled', (v) => v as bool? ?? false),
      );
      return val;
    });

Map<String, dynamic> _$ReportColumnToJson(ReportColumn instance) =>
    <String, dynamic>{
      'label': instance.label,
      'kind': _$ReportValueKindEnumMap[instance.kind]!,
      'width': ?instance.width,
      'flex': instance.flex,
      'totalled': instance.totalled,
    };

ReportRow _$ReportRowFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportRow', json, ($checkedConvert) {
      final val = ReportRow(
        $checkedConvert(
          'values',
          (v) => (v as List<dynamic>)
              .map((e) => ReportValue.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        emphasise: $checkedConvert('emphasise', (v) => v as bool? ?? false),
        id: $checkedConvert('id', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$ReportRowToJson(ReportRow instance) => <String, dynamic>{
  'values': instance.values.map((e) => e.toJson()).toList(),
  'emphasise': instance.emphasise,
  'id': ?instance.id,
};

ReportNote _$ReportNoteFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportNote', json, ($checkedConvert) {
      final val = ReportNote($checkedConvert('text', (v) => v as String));
      return val;
    });

Map<String, dynamic> _$ReportNoteToJson(ReportNote instance) =>
    <String, dynamic>{'text': instance.text};

ReportResult _$ReportResultFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportResult', json, ($checkedConvert) {
      final val = ReportResult(
        title: $checkedConvert('title', (v) => v as String),
        columns: $checkedConvert(
          'columns',
          (v) => (v as List<dynamic>)
              .map((e) => ReportColumn.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        rows: $checkedConvert(
          'rows',
          (v) => (v as List<dynamic>)
              .map((e) => ReportRow.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        generatedAt: $checkedConvert(
          'generatedAt',
          (v) => DateTime.parse(v as String),
        ),
        filter: $checkedConvert(
          'filter',
          (v) => ReportFilter.fromJson(v as Map<String, dynamic>),
        ),
        totals: $checkedConvert(
          'totals',
          (v) => (v as List<dynamic>?)
              ?.map((e) => ReportValue.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
        notes: $checkedConvert(
          'notes',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => ReportNote.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              const [],
        ),
        subtitle: $checkedConvert('subtitle', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ReportResultToJson(ReportResult instance) =>
    <String, dynamic>{
      'title': instance.title,
      'subtitle': ?instance.subtitle,
      'columns': instance.columns.map((e) => e.toJson()).toList(),
      'rows': instance.rows.map((e) => e.toJson()).toList(),
      'totals': ?instance.totals?.map((e) => e.toJson()).toList(),
      'notes': instance.notes.map((e) => e.toJson()).toList(),
      'generatedAt': instance.generatedAt.toIso8601String(),
      'filter': instance.filter.toJson(),
    };

ReportFilter _$ReportFilterFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportFilter', json, ($checkedConvert) {
      final val = ReportFilter(
        from: $checkedConvert(
          'from',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        to: $checkedConvert(
          'to',
          (v) => v == null ? null : DateTime.parse(v as String),
        ),
        agentId: $checkedConvert('agentId', (v) => (v as num?)?.toInt()),
        shopId: $checkedConvert('shopId', (v) => (v as num?)?.toInt()),
        productId: $checkedConvert('productId', (v) => (v as num?)?.toInt()),
        categoryId: $checkedConvert('categoryId', (v) => (v as num?)?.toInt()),
        employeeId: $checkedConvert('employeeId', (v) => (v as num?)?.toInt()),
        locationId: $checkedConvert('locationId', (v) => (v as num?)?.toInt()),
        limit: $checkedConvert('limit', (v) => (v as num?)?.toInt() ?? 2000),
      );
      return val;
    });

Map<String, dynamic> _$ReportFilterToJson(ReportFilter instance) =>
    <String, dynamic>{
      'from': ?instance.from?.toIso8601String(),
      'to': ?instance.to?.toIso8601String(),
      'agentId': ?instance.agentId,
      'shopId': ?instance.shopId,
      'productId': ?instance.productId,
      'categoryId': ?instance.categoryId,
      'employeeId': ?instance.employeeId,
      'locationId': ?instance.locationId,
      'limit': instance.limit,
    };

ReportDefinition _$ReportDefinitionFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReportDefinition', json, ($checkedConvert) {
      final val = ReportDefinition(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        description: $checkedConvert('description', (v) => v as String),
        group: $checkedConvert(
          'group',
          (v) => $enumDecode(_$ReportGroupEnumMap, v),
        ),
        permission: $checkedConvert('permission', (v) => v as String),
        filters: $checkedConvert(
          'filters',
          (v) =>
              (v as List<dynamic>?)
                  ?.map((e) => $enumDecode(_$ReportFilterFieldEnumMap, e))
                  .toSet() ??
              const {ReportFilterField.period},
        ),
      );
      return val;
    });

Map<String, dynamic> _$ReportDefinitionToJson(ReportDefinition instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'group': _$ReportGroupEnumMap[instance.group]!,
      'permission': instance.permission,
      'filters': instance.filters
          .map((e) => _$ReportFilterFieldEnumMap[e]!)
          .toList(),
    };

const _$ReportGroupEnumMap = {
  ReportGroup.sales: 'sales',
  ReportGroup.stock: 'stock',
  ReportGroup.money: 'money',
  ReportGroup.finance: 'finance',
};

const _$ReportFilterFieldEnumMap = {
  ReportFilterField.period: 'period',
  ReportFilterField.agent: 'agent',
  ReportFilterField.shop: 'shop',
  ReportFilterField.product: 'product',
  ReportFilterField.category: 'category',
  ReportFilterField.employee: 'employee',
  ReportFilterField.location: 'location',
};
