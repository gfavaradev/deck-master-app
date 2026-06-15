import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'data_repository.dart';
import 'subscription_service.dart';

class ExportResult {
  final bool success;
  final bool requiresPro;
  final int cardCount;
  final String format;

  const ExportResult({
    required this.success,
    this.requiresPro = false,
    this.cardCount = 0,
    this.format = '',
  });
}

/// Handles Excel export of the user's card collection.
class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  final DataRepository _repo = DataRepository();
  final SubscriptionService _subService = SubscriptionService();

  Future<List<int>> _buildExcel(List<Map<String, dynamic>> cards) async {
    final excel = Excel.createExcel();
    final sheet = excel['Collection'];

    // Header row
    final headers = ['Name', 'Serial Number', 'Collection', 'Rarity', 'Quantity', 'Value'];
    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(bold: true);
    }

    // Data rows
    for (var r = 0; r < cards.length; r++) {
      final c = cards[r];
      final row = r + 1;
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          TextCellValue((c['name'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value =
          TextCellValue((c['serialNumber'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value =
          TextCellValue((c['collection'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value =
          TextCellValue((c['rarity'] ?? '').toString());
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value =
          IntCellValue((c['quantity'] as num?)?.toInt() ?? 0);
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value =
          DoubleCellValue((c['value'] as num?)?.toDouble() ?? 0.0);
    }

    return excel.encode()!;
  }

  /// Exports the collection as an Excel file shared via the system share sheet.
  Future<ExportResult> exportToExcel() async {
    final hasPro = await _subService.currentUserHasPro();
    if (!hasPro) {
      return const ExportResult(success: false, requiresPro: true);
    }

    final cards = await _repo.getAllCardsForExport();
    final bytes = await _buildExcel(cards);

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/deck_master_collection.xlsx');
    await file.writeAsBytes(bytes, flush: true);

    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')]),
    );

    return ExportResult(
      success: true,
      cardCount: cards.length,
      format: 'Excel',
    );
  }
}
