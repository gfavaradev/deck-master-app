import 'dart:convert';
import 'package:flutter/services.dart';
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

/// Handles CSV and JSON export of the user's card collection.
class ExportService {
  static final ExportService _instance = ExportService._internal();
  factory ExportService() => _instance;
  ExportService._internal();

  final DataRepository _repo = DataRepository();
  final SubscriptionService _subService = SubscriptionService();

  String _buildCsv(List<Map<String, dynamic>> cards) {
    final buf = StringBuffer();
    buf.writeln('Name,SerialNumber,Collection,Rarity,Quantity,Value');
    for (final c in cards) {
      final name = (c['name'] ?? '').toString().replaceAll('"', '""');
      final serial = (c['serialNumber'] ?? '').toString().replaceAll('"', '""');
      final collection = (c['collection'] ?? '').toString();
      final rarity = (c['rarity'] ?? '').toString().replaceAll('"', '""');
      final qty = c['quantity']?.toString() ?? '0';
      final value = c['value']?.toString() ?? '0';
      buf.writeln('"$name","$serial","$collection","$rarity",$qty,$value');
    }
    return buf.toString();
  }

  String _buildJson(List<Map<String, dynamic>> cards) {
    return const JsonEncoder.withIndent('  ').convert(cards);
  }

  /// Exports the collection as [format] ('csv' or 'json') by copying to clipboard.
  /// Returns an [ExportResult] describing the outcome.
  Future<ExportResult> exportToClipboard(String format) async {
    final hasPro = await _subService.currentUserHasPro();
    if (!hasPro) {
      return const ExportResult(success: false, requiresPro: true);
    }

    final cards = await _repo.getAllCardsForExport();
    final text = format == 'csv' ? _buildCsv(cards) : _buildJson(cards);
    await Clipboard.setData(ClipboardData(text: text));

    return ExportResult(
      success: true,
      cardCount: cards.length,
      format: format.toUpperCase(),
    );
  }
}
