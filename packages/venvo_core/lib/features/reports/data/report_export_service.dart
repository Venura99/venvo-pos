import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/errors/failures.dart';
import '../../../core/services/app_paths.dart';
import '../../../core/services/document_pdf_service.dart';
import '../../../core/utils/money.dart';
import '../domain/report_models.dart';

/// Turns a run report into a PDF or a CSV.
///
/// Kept apart from [DocumentPdfService], which lays out business *documents* -
/// an invoice has a party block, line prices and a signature panel. A report
/// is a grid with a period, a totals row and its own caveats printed under it.
/// Forcing one layout to do both would make neither read well.
///
/// The caveats are printed, not optional. A collections figure that counts
/// only cleared money has to say so on the page: a report leaves the
/// application and gets read by somebody who cannot ask what it means.
class ReportExportService {
  /// [paths] is only needed by [savePdf] and [saveCsv], which write to a
  /// folder. A browser has no folder to write to, so a web client builds the
  /// bytes with [buildPdf] or [buildCsvBytes] and hands them to the browser as
  /// a download, and constructs this without paths.
  const ReportExportService({
    AppPaths? paths,
    required BusinessIdentity business,
  }) : _paths = paths,
       _business = business;

  final AppPaths? _paths;
  final BusinessIdentity _business;

  static final DateFormat _date = DateFormat('d MMM yyyy');
  static final DateFormat _month = DateFormat('MMMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, HH:mm');
  static final DateFormat _fileStamp = DateFormat('yyyy-MM-dd-HHmm');

  // --- PDF -----------------------------------------------------------------

  Future<Uint8List> buildPdf(ReportResult report) async {
    // A wide report is landscape; a narrow one reads better portrait.
    final landscape = report.columns.length > 6;
    final document = pw.Document(title: report.title, author: _business.name);

    document.addPage(
      pw.MultiPage(
        pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 36),
        header: (context) => _pdfHeader(report, context.pageNumber),
        footer: (context) => _pdfFooter(report, context),
        build: (context) => [
          _pdfTable(report),
          if (report.notes.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _pdfNotes(report),
          ],
        ],
      ),
    );

    return Uint8List.fromList(await document.save());
  }

  /// Saves the PDF under the exports folder and returns the file.
  Future<File> savePdf(ReportResult report, {required String reportId}) async {
    final bytes = await buildPdf(report);
    return _write(
      bytes,
      reportId: reportId,
      extension: 'pdf',
      generatedAt: report.generatedAt,
    );
  }

  pw.Widget _pdfHeader(ReportResult report, int pageNumber) {
    if (pageNumber > 1) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              report.title,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text(
              _periodLine(report.filter),
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
      );
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _business.name,
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if (_business.address != null)
                    pw.Text(
                      _business.address!,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  if (_business.contactLine.isNotEmpty)
                    pw.Text(
                      _business.contactLine,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    report.title.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                  pw.Text(
                    _periodLine(report.filter),
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  if (report.subtitle != null)
                    pw.Text(
                      report.subtitle!,
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(height: 1, thickness: 0.8),
        ],
      ),
    );
  }

  pw.Widget _pdfFooter(ReportResult report, pw.Context context) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated ${_dateTime.format(report.generatedAt.toLocal())}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfTable(ReportResult report) {
    if (report.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 28),
        child: pw.Center(
          child: pw.Text(
            'Nothing to report for this period.',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
      );
    }

    final widths = <int, pw.TableColumnWidth>{};
    for (var index = 0; index < report.columns.length; index++) {
      final column = report.columns[index];
      widths[index] = column.width == null
          ? pw.FlexColumnWidth(column.flex.toDouble())
          : pw.FixedColumnWidth(column.width! * 0.62);
    }

    return pw.TableHelper.fromTextArray(
      columnWidths: widths,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      headerAlignments: {
        for (var index = 0; index < report.columns.length; index++)
          index: report.columns[index].isNumeric
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
      cellAlignments: {
        for (var index = 0; index < report.columns.length; index++)
          index: report.columns[index].isNumeric
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
      },
      headers: [for (final column in report.columns) column.label],
      data: [
        for (final row in report.rows)
          [for (final value in row.values) formatForDisplay(value)],
        if (report.totals != null)
          [for (final value in report.totals!) formatForDisplay(value)],
      ],
      // The last row is the totals row, where there is one.
      rowDecoration: null,
    );
  }

  pw.Widget _pdfNotes(ReportResult report) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'How to read this report',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 3),
        for (final note in report.notes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              '· ${note.text}',
              style: const pw.TextStyle(
                fontSize: 7.5,
                color: PdfColors.grey800,
              ),
            ),
          ),
      ],
    );
  }

  // --- CSV -----------------------------------------------------------------

  /// The report as CSV.
  ///
  /// Money and quantities go out as bare numbers so a spreadsheet reads them
  /// back as numbers rather than as text: an exported report that cannot be
  /// summed in Excel is not much of an export. The caveats are written as
  /// comment rows under the data, because they belong with the figures.
  String buildCsv(ReportResult report) {
    final rows = <List<Object?>>[
      [_business.name],
      [report.title],
      [_periodLine(report.filter)],
      if (report.subtitle != null) [report.subtitle],
      ['Generated', _dateTime.format(report.generatedAt.toLocal())],
      [],
      [for (final column in report.columns) column.label],
      for (final row in report.rows)
        [for (final value in row.values) _csvValue(value)],
      if (report.totals != null) ...[
        [],
        [
          for (var index = 0; index < report.totals!.length; index++)
            index == 0 ? 'Total' : _csvValue(report.totals![index]),
        ],
      ],
      if (report.notes.isNotEmpty) ...[
        [],
        ['How to read this report'],
        for (final note in report.notes) [note.text],
      ],
    ];

    return const ListToCsvConverter().convert(rows);
  }

  /// The CSV as bytes, ready to save or to hand to a browser as a download.
  ///
  /// UTF-8 with a byte-order mark. The BOM is what makes Excel on Windows
  /// open the file as UTF-8 rather than as the system codepage, which would
  /// otherwise turn every separator and currency name into mojibake.
  Uint8List buildCsvBytes(ReportResult report) =>
      Uint8List.fromList([...utf8BOM, ...utf8.encode(buildCsv(report))]);

  /// The name an exported report is saved under, shared by every way of
  /// saving it so a download and a file on disk are called the same thing.
  static String fileNameFor(
    String reportId,
    DateTime generatedAt, {
    required String extension,
  }) => '$reportId-${_fileStamp.format(generatedAt.toLocal())}.$extension';

  Future<File> saveCsv(ReportResult report, {required String reportId}) async {
    return _write(
      buildCsvBytes(report),
      reportId: reportId,
      extension: 'csv',
      generatedAt: report.generatedAt,
    );
  }

  static const List<int> utf8BOM = [0xEF, 0xBB, 0xBF];

  static Object? _csvValue(ReportValue value) {
    if (value.isEmpty) return '';
    return switch (value.kind) {
      ReportValueKind.text => value.text ?? '',
      // Major units with two decimals: a number to a spreadsheet, and still
      // exact because it comes from an integer cent count.
      ReportValueKind.money =>
        (value.money!.cents / Money.minorPerMajor).toStringAsFixed(2),
      ReportValueKind.integer => value.number,
      ReportValueKind.date => DateFormat(
        'yyyy-MM-dd',
      ).format(value.date!.toLocal()),
      ReportValueKind.month => DateFormat(
        'yyyy-MM',
      ).format(value.date!.toLocal()),
      ReportValueKind.percent => (value.bps! / 100).toStringAsFixed(2),
    };
  }

  // --- Shared --------------------------------------------------------------

  /// How a value reads on a page or on screen.
  static String formatForDisplay(ReportValue value) {
    if (value.isEmpty) return '';
    return switch (value.kind) {
      ReportValueKind.text => value.text ?? '',
      ReportValueKind.money => value.money!.plain,
      ReportValueKind.integer => NumberFormat.decimalPattern().format(
        value.number,
      ),
      ReportValueKind.date => _date.format(value.date!.toLocal()),
      ReportValueKind.month => _month.format(value.date!.toLocal()),
      ReportValueKind.percent => formatBps(value.bps!),
    };
  }

  /// "1 Nov 2026 to 30 Nov 2026", or "All time".
  static String _periodLine(ReportFilter filter) {
    if (filter.from == null && filter.to == null) return 'All time';
    if (filter.from != null && filter.to != null) {
      return '${_date.format(filter.from!.toLocal())} to '
          '${_date.format(filter.to!.toLocal())}';
    }
    if (filter.from != null) {
      return 'From ${_date.format(filter.from!.toLocal())}';
    }
    return 'Up to ${_date.format(filter.to!.toLocal())}';
  }

  /// Writes an export under `exports/reports/`, stamped so a second run on the
  /// same day does not overwrite the first.
  Future<File> _write(
    Uint8List bytes, {
    required String reportId,
    required String extension,
    required DateTime generatedAt,
  }) async {
    final paths = _paths;
    if (paths == null) {
      throw const StorageFailure(
        'This device has no exports folder to save into.',
        details: 'ReportExportService was built without AppPaths.',
      );
    }
    final folder = Directory(p.join(paths.exportsDir.path, 'reports'));
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }

    final stamp = _fileStamp.format(generatedAt.toLocal());
    final file = File(p.join(folder.path, '$reportId-$stamp.$extension'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
