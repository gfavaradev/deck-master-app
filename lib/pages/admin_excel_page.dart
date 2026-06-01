import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/admin_excel_service.dart';
import '../theme/app_colors.dart';

class AdminExcelPage extends StatefulWidget {
  final String initialCollection;
  const AdminExcelPage({super.key, this.initialCollection = 'yugioh'});

  @override
  State<AdminExcelPage> createState() => _AdminExcelPageState();
}

class _AdminExcelPageState extends State<AdminExcelPage> {
  final AdminExcelService _service = AdminExcelService();

  late String _selectedCollection;
  bool _isRunning = false;
  double? _progress;
  String _statusText = '';
  ImportPreview? _preview;
  String _resultText = '';
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    _selectedCollection = widget.initialCollection;
  }

  static const _collections = [
    (key: 'yugioh',            label: 'Yu-Gi-Oh!',              icon: Icons.auto_awesome,        color: Color(0xFF7B1FA2)),
    (key: 'pokemon',           label: 'Pokémon TCG',             icon: Icons.catching_pokemon,    color: Color(0xFFF57C00)),
    (key: 'onepiece',          label: 'One Piece TCG',           icon: Icons.sailing,             color: Color(0xFFD32F2F)),
    (key: 'magic',             label: 'Magic: The Gathering',    icon: Icons.diamond_outlined,    color: Color(0xFF7B5EA7)),
    (key: 'digimon',           label: 'Digimon',                 icon: Icons.pets,                color: Color(0xFF0288D1)),
    (key: 'lorcana',           label: 'Disney Lorcana',          icon: Icons.auto_stories,        color: Color(0xFF7B1FA2)),
    (key: 'flesh-and-blood',   label: 'Flesh and Blood',         icon: Icons.sports_martial_arts, color: Color(0xFF880E4F)),
    (key: 'vanguard',          label: 'Cardfight!! Vanguard',    icon: Icons.shield,              color: Color(0xFF1565C0)),
    (key: 'dragon-ball-super', label: 'Dragon Ball Super',       icon: Icons.bolt,                color: Color(0xFFFF6F00)),
    (key: 'star-wars',         label: 'Star Wars: Unlimited',    icon: Icons.rocket_launch,       color: Color(0xFF212121)),
    (key: 'riftbound',         label: 'Riftbound',               icon: Icons.casino,              color: Color(0xFF4A148C)),
    (key: 'gundam',            label: 'Gundam Card Game',        icon: Icons.smart_toy,           color: Color(0xFF37474F)),
    (key: 'union-arena',       label: 'Union Arena',             icon: Icons.people,              color: Color(0xFF2E7D32)),
  ];

  Color get _accentColor =>
      _collections.firstWhere((c) => c.key == _selectedCollection).color;

  // ── Export ─────────────────────────────────────────────────────────────────

  Future<void> _export() async {
    if (kIsWeb) {
      _showResult('L\'esportazione Excel non è supportata su web.', isError: true);
      return;
    }
    _startOp();
    try {
      final bytes = await _service.exportToExcel(
        _selectedCollection,
        onProgress: (s, p) => _updateProgress(s, p),
      );
      final label = _collections.firstWhere((c) => c.key == _selectedCollection).label;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final filename = 'deck_master_${_selectedCollection}_$ts.xlsx';
      _updateProgress('Condivisione file...', null);
      await Share.shareXFiles(
        [XFile.fromData(bytes, name: filename,
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
        subject: 'Catalogo $label — Deck Master',
      );
      _showResult('File Excel esportato (${(bytes.length / 1024).toStringAsFixed(0)} KB).');
    } catch (e) {
      _showResult('Errore esportazione: $e', isError: true);
    } finally {
      _endOp();
    }
  }

  // ── Import ─────────────────────────────────────────────────────────────────

  Future<void> _pickAndPreview() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) {
      _showResult('Impossibile leggere il file selezionato.', isError: true);
      return;
    }

    _startOp();
    try {
      _updateProgress('Analisi file Excel...', null);
      final preview = await _service.previewImport(_selectedCollection, bytes);
      if (!mounted) return;
      setState(() => _preview = preview);
      _showResult(
        preview.totalChanged == 0
            ? 'Nessuna modifica rilevata (${preview.totalScanned} carte analizzate).'
            : '${preview.totalChanged} carte modificate su ${preview.totalScanned} analizzate.',
        isError: false,
      );
    } catch (e) {
      _showResult('Errore analisi: $e', isError: true);
    } finally {
      _endOp();
    }
  }

  Future<void> _applyImport() async {
    final preview = _preview;
    if (preview == null || preview.totalChanged == 0) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showResult('Sessione scaduta. Fai il logout e accedi di nuovo.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgMedium,
        title: const Text('Conferma importazione',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Verranno aggiornate ${preview.totalChanged} carte su Firestore.\n\n'
          'Solo i campi non vuoti nel file Excel sovrascriveranno i dati esistenti. '
          'Immagini, prezzi e set non vengono modificati.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Applica'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _startOp();
    try {
      final result = await _service.applyImport(
        preview,
        uid,
        onProgress: (s, p) => _updateProgress(s, p),
      );
      if (!mounted) return;
      setState(() => _preview = null);
      _showResult(
        '${result.updatedCards} carte aggiornate in ${result.affectedChunks} chunk Firestore.',
      );
    } catch (e) {
      _showResult('Errore importazione: $e', isError: true);
    } finally {
      _endOp();
    }
  }

  // ── State helpers ───────────────────────────────────────────────────────────

  void _startOp() => setState(() {
    _isRunning = true;
    _statusText = '';
    _progress = null;
    _resultText = '';
    _resultIsError = false;
  });

  void _endOp() {
    if (mounted) setState(() { _isRunning = false; _statusText = ''; _progress = null; });
  }

  void _updateProgress(String status, double? progress) {
    if (mounted) setState(() { _statusText = status; _progress = progress; });
  }

  void _showResult(String msg, {bool isError = false}) {
    if (mounted) setState(() { _resultText = msg; _resultIsError = isError; });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: const Text('Export / Import Excel'),
        backgroundColor: AppColors.bgMedium,
        foregroundColor: AppColors.textPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCollectionSelector(),
          const SizedBox(height: 16),
          if (_isRunning) ...[_buildProgressCard(), const SizedBox(height: 16)],
          _buildExportCard(),
          const SizedBox(height: 12),
          _buildImportCard(),
          if (_resultText.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildResultBanner(),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildCollectionSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedCollection,
          dropdownColor: AppColors.bgMedium,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
          isExpanded: true,
          onChanged: _isRunning
              ? null
              : (v) => setState(() {
                    _selectedCollection = v!;
                    _preview = null;
                    _resultText = '';
                  }),
          items: _collections.map((c) => DropdownMenuItem(
            value: c.key,
            child: Row(
              children: [
                Icon(c.icon, color: c.color, size: 18),
                const SizedBox(width: 10),
                Text(c.label),
              ],
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _statusText.isNotEmpty ? _statusText : 'In corso...',
                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _progress,
            backgroundColor: AppColors.bgDark,
            valueColor: AlwaysStoppedAnimation(_accentColor),
            minHeight: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildExportCard() {
    return _card(
      title: 'Esporta in Excel',
      icon: Icons.download,
      subtitle: 'Genera un file .xlsx con due fogli:\n'
          '• Carte — dati completi della carta (tutte le traduzioni)\n'
          '• Stampe — tutti i print con set/rarità/prezzi per lingua\n'
          'Il catalogo deve essere già stato scaricato da Firestore.',
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: _isRunning ? null : _export,
          icon: const Icon(Icons.table_chart, size: 18),
          label: const Text('Esporta e Condividi'),
          style: FilledButton.styleFrom(backgroundColor: _accentColor),
        ),
      ),
    );
  }

  Widget _buildImportCard() {
    final preview = _preview;
    return _card(
      title: 'Importa da Excel',
      icon: Icons.upload,
      subtitle: 'Seleziona un file .xlsx esportato da questa app con le '
          'traduzioni o i metadati modificati.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _isRunning ? null : _pickAndPreview,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Seleziona file .xlsx'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _accentColor,
              side: BorderSide(color: _accentColor.withValues(alpha: 0.6)),
            ),
          ),
          if (preview != null && preview.totalChanged > 0) ...[
            const SizedBox(height: 12),
            _buildPreviewSummary(preview),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _isRunning ? null : _applyImport,
              icon: const Icon(Icons.cloud_upload, size: 18),
              label: Text('Applica ${preview.totalChanged} modifiche su Firestore'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewSummary(ImportPreview preview) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${preview.totalChanged} carte con modifiche',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green,
                  ),
                ),
                Text(
                  '${preview.unchanged} invariate · ${preview.totalScanned} totali analizzate',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBanner() {
    final color = _resultIsError ? Colors.red : Colors.green;
    final icon = _resultIsError ? Icons.error_outline : Icons.check_circle_outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _resultText,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    required IconData icon,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgMedium,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _accentColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: _accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
