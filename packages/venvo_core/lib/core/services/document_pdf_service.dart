import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants/app_constants.dart';
import '../enums/app_enums.dart';
import '../errors/failures.dart';
import '../utils/money.dart';
import 'app_paths.dart';
import 'settings_service.dart';

/// The business's own details, as they print on a document.
class BusinessIdentity {
  const BusinessIdentity({
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.taxId,
    this.footerNote,
  });

  /// Reads the identity out of the settings table.
  static Future<BusinessIdentity> fromSettings(SettingsService settings) async {
    String? clean(String? value) {
      final text = (value ?? '').trim();
      return text.isEmpty ? null : text;
    }

    return BusinessIdentity(
      name: await settings.businessName,
      address: clean(await settings.getString(SettingKeys.businessAddress)),
      phone: clean(await settings.getString(SettingKeys.businessPhone)),
      email: clean(await settings.getString(SettingKeys.businessEmail)),
      taxId: clean(await settings.getString(SettingKeys.businessTaxId)),
      footerNote: clean(
        await settings.getString(SettingKeys.invoiceFooterNote),
      ),
    );
  }

  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxId;
  final String? footerNote;

  /// Contact details on one line, for the header.
  String get contactLine => [
    if (phone != null) 'Tel $phone',
    if (email != null) email!,
    if (taxId != null) 'Tax $taxId',
  ].join('  ·  ');
}

/// One printable line on a document.
class PdfDocumentLine {
  const PdfDocumentLine({
    required this.description,
    required this.reference,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.discountLabel,
  });

  final String description;

  /// The SKU or other short identifier shown under the description.
  final String reference;
  final int quantity;
  final Money unitPrice;
  final Money lineTotal;

  /// How the discount was entered, e.g. "10%". Null when there was none.
  final String? discountLabel;
}

/// A money line in the totals block.
class PdfTotalLine {
  const PdfTotalLine(this.label, this.amount, {this.emphasise = false});

  final String label;
  final Money amount;
  final bool emphasise;
}

/// A free-text row in the party or meta block.
class PdfField {
  const PdfField(this.label, this.value);

  final String label;
  final String value;
}

/// Everything a printable business document needs.
///
/// Built by the feature that owns the document, so this service knows how to
/// *lay out* an invoice, a receipt or a delivery note without knowing what an
/// invoice is.
class PdfDocumentSpec {
  const PdfDocumentSpec({
    required this.title,
    required this.documentNumber,
    required this.documentDate,
    required this.partyBlockTitle,
    required this.partyName,
    this.partyFields = const [],
    this.metaFields = const [],
    this.lines = const [],
    this.totals = const [],
    this.notes,
    this.watermark,
    this.footnotes = const [],
    this.showUnitPrices = true,
  });

  final String title;
  final String documentNumber;
  final DateTime documentDate;

  /// "Billed to", "Received from", "Deliver to".
  final String partyBlockTitle;
  final String partyName;
  final List<PdfField> partyFields;

  /// Document-level details printed opposite the party block.
  final List<PdfField> metaFields;

  final List<PdfDocumentLine> lines;
  final List<PdfTotalLine> totals;
  final String? notes;

  /// Printed diagonally across the page, e.g. "CANCELLED".
  final String? watermark;

  /// Printed above the footer: the terms, the pending-cheque caveat, and so on.
  final List<String> footnotes;

  /// A delivery note shows quantities without prices when the goods have not
  /// been billed.
  final bool showUnitPrices;
}

/// Renders business documents as PDF, and saves or prints them.
///
/// One layout serves invoices, receipts and delivery notes: they differ in
/// their title, their blocks and their totals, not in how a page is put
/// together. That keeps every document the business sends out looking like it
/// came from the same place.
class DocumentPdfService {
  /// [paths] is only needed by [save], which writes to the exports folder. A
  /// browser has no folder, so a web client calls [build] for the bytes and
  /// hands them over as a download, and constructs this without paths.
  const DocumentPdfService({
    AppPaths? paths,
    required BusinessIdentity business,
  }) : _paths = paths,
       _business = business;

  final AppPaths? _paths;
  final BusinessIdentity _business;

  static final DateFormat _dateFormat = DateFormat('d MMM yyyy');
  static final DateFormat _dateTimeFormat = DateFormat('d MMM yyyy, HH:mm');

  /// Builds the PDF bytes.
  Future<Uint8List> build(PdfDocumentSpec spec) async {
    final document = pw.Document(
      title: '${spec.title} ${spec.documentNumber}',
      author: _business.name,
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
        header: (context) =>
            context.pageNumber == 1 ? _header(spec) : _continuationHeader(spec),
        footer: _footer,
        build: (context) => [
          _titleBlock(spec),
          pw.SizedBox(height: 14),
          _partyAndMeta(spec),
          pw.SizedBox(height: 16),
          if (spec.lines.isNotEmpty) _linesTable(spec),
          if (spec.totals.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            _totalsBlock(spec),
          ],
          if (spec.notes != null) ...[
            pw.SizedBox(height: 16),
            _notesBlock(spec.notes!),
          ],
          if (spec.footnotes.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _footnotes(spec.footnotes),
          ],
          pw.SizedBox(height: 28),
          _signatures(),
        ],
      ),
    );

    return Uint8List.fromList(await document.save());
  }

  /// Saves the PDF under the exports folder and returns the file.
  ///
  /// Documents are kept on disk as well as being printable, so a reprint never
  /// depends on the database still holding exactly what it held on the day.
  Future<File> save(PdfDocumentSpec spec, {String? subfolder}) async {
    final paths = _paths;
    if (paths == null) {
      throw const StorageFailure(
        'This device has no exports folder to save into.',
        details: 'DocumentPdfService was built without AppPaths.',
      );
    }
    final bytes = await build(spec);
    final folder = subfolder == null
        ? paths.exportsDir
        : Directory(p.join(paths.exportsDir.path, subfolder));

    try {
      if (!folder.existsSync()) {
        await folder.create(recursive: true);
      }
      final safeNumber = spec.documentNumber.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '-',
      );
      final file = File(p.join(folder.path, '$safeNumber.pdf'));
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } on FileSystemException catch (error) {
      throw StorageFailure(
        'The document could not be saved.',
        details: '${error.path}: ${error.message}',
      );
    }
  }

  // --- Layout -------------------------------------------------------------

  pw.Widget _header(PdfDocumentSpec spec) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _business.name,
                    style: pw.TextStyle(
                      fontSize: 17,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (_business.address != null)
                    pw.Text(
                      _business.address!,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  if (_business.contactLine.isNotEmpty)
                    pw.Text(
                      _business.contactLine,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey200,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(
                spec.title.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 0.8, color: PdfColors.grey600),
      ],
    );
  }

  pw.Widget _continuationHeader(PdfDocumentSpec spec) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        '${spec.title} ${spec.documentNumber} (continued)',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
      ),
    );
  }

  pw.Widget _footer(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 0.5, color: PdfColors.grey400),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(
                _business.footerNote ?? '',
                style: const pw.TextStyle(
                  fontSize: 7.5,
                  color: PdfColors.grey700,
                ),
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _titleBlock(PdfDocumentSpec spec) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              spec.documentNumber,
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _dateFormat.format(spec.documentDate.toLocal()),
              style: const pw.TextStyle(fontSize: 9.5),
            ),
          ],
        ),
        if (spec.watermark != null)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red700, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              spec.watermark!,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red700,
                letterSpacing: 1.5,
              ),
            ),
          ),
      ],
    );
  }

  pw.Widget _partyAndMeta(PdfDocumentSpec spec) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                spec.partyBlockTitle.toUpperCase(),
                style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                  letterSpacing: 0.8,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                spec.partyName,
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              for (final field in spec.partyFields)
                pw.Text(field.value, style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.SizedBox(width: 24),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (final field in spec.metaFields)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2),
                  child: pw.Row(
                    children: [
                      pw.SizedBox(
                        width: 86,
                        child: pw.Text(
                          field.label,
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          field.value,
                          style: const pw.TextStyle(fontSize: 9),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _linesTable(PdfDocumentSpec spec) {
    final headers = <String>[
      '#',
      'Description',
      'Qty',
      if (spec.showUnitPrices) 'Unit price',
      if (spec.showUnitPrices) 'Disc.',
      if (spec.showUnitPrices) 'Amount',
    ];

    return pw.TableHelper.fromTextArray(
      headers: headers,
      headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: spec.showUnitPrices
          ? {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FlexColumnWidth(5),
              2: const pw.FixedColumnWidth(40),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FixedColumnWidth(48),
              5: const pw.FixedColumnWidth(78),
            }
          : {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FlexColumnWidth(6),
              2: const pw.FixedColumnWidth(50),
            },
      cellAlignments: spec.showUnitPrices
          ? {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            }
          : {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
            },
      data: [
        for (var index = 0; index < spec.lines.length; index++)
          _lineRow(spec, index),
      ],
    );
  }

  List<String> _lineRow(PdfDocumentSpec spec, int index) {
    final line = spec.lines[index];
    final description = '${line.description}\n${line.reference}';

    return [
      '${index + 1}',
      description,
      '${line.quantity}',
      if (spec.showUnitPrices) line.unitPrice.plain,
      if (spec.showUnitPrices) line.discountLabel ?? '—',
      if (spec.showUnitPrices) line.lineTotal.plain,
    ];
  }

  pw.Widget _totalsBlock(PdfDocumentSpec spec) {
    return pw.Row(
      children: [
        pw.Spacer(flex: 3),
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            children: [
              for (final total in spec.totals)
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 3),
                  decoration: total.emphasise
                      ? const pw.BoxDecoration(
                          border: pw.Border(
                            top: pw.BorderSide(width: 0.8),
                            bottom: pw.BorderSide(width: 0.8),
                          ),
                        )
                      : null,
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          total.label,
                          style: pw.TextStyle(
                            fontSize: total.emphasise ? 10.5 : 9.5,
                            fontWeight: total.emphasise
                                ? pw.FontWeight.bold
                                : pw.FontWeight.normal,
                          ),
                        ),
                      ),
                      pw.Text(
                        total.amount.formatted(),
                        style: pw.TextStyle(
                          fontSize: total.emphasise ? 10.5 : 9.5,
                          fontWeight: total.emphasise
                              ? pw.FontWeight.bold
                              : pw.FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _notesBlock(String notes) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'NOTES',
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(notes, style: const pw.TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  pw.Widget _footnotes(List<String> footnotes) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final note in footnotes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              note,
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
            ),
          ),
      ],
    );
  }

  pw.Widget _signatures() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _signatureLine('Prepared by'),
        _signatureLine('Received by'),
        _signatureLine('Authorised by'),
      ],
    );
  }

  pw.Widget _signatureLine(String label) {
    return pw.SizedBox(
      width: 140,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            height: 0.8,
            color: PdfColors.grey600,
            margin: const pw.EdgeInsets.only(bottom: 3),
          ),
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  /// Formats a timestamp the way documents show it.
  static String formatDateTime(DateTime value) =>
      _dateTimeFormat.format(value.toLocal());

  /// Formats a date the way documents show it.
  static String formatDate(DateTime value) =>
      _dateFormat.format(value.toLocal());

  /// The caveat that goes on any document where a pending cheque is involved.
  static const String pendingChequeFootnote =
      'A cheque is credited only when it clears. Amounts shown as received '
      'exclude cheques still in clearing.';

  /// The caveat that goes on a delivery note.
  static const String deliveryNoteFootnote =
      'This is a record of goods moved, not an invoice. It does not create a '
      'payable on its own.';

  /// Human label for a payment method, for receipts.
  static String methodLabel(PaymentMethod method) => switch (method) {
    PaymentMethod.cash => 'Cash',
    PaymentMethod.bankTransfer => 'Bank transfer',
    PaymentMethod.cheque => 'Cheque',
    PaymentMethod.cardOrDigital => 'Card or digital',
    PaymentMethod.creditNote => 'Credit note',
    PaymentMethod.openingBalance => 'Opening balance',
  };
}
