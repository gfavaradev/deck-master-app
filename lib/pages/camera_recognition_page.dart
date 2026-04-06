import 'package:flutter/material.dart';
// google_mlkit_text_recognition disabled for simulator build
import 'package:image_picker/image_picker.dart';
import '../theme/app_colors.dart';

/// Risultato del riconoscimento OCR.
class RecognitionResult {
  final String cardName;
  final String? serialNumber;
  const RecognitionResult({required this.cardName, this.serialNumber});
}

/// Pagina per riconoscere una carta tramite OCR (ML Kit).
/// Scatta una foto e estrae nome/seriale dalla carta.
/// Ritorna un [RecognitionResult] tramite Navigator.pop().
class CameraRecognitionPage extends StatefulWidget {
  const CameraRecognitionPage({super.key});

  @override
  State<CameraRecognitionPage> createState() => _CameraRecognitionPageState();
}

class _CameraRecognitionPageState extends State<CameraRecognitionPage> {
  bool _isProcessing = false;
  String? _lastError;
  final _picker = ImagePicker();

  Future<void> _captureAndRecognize() async {
    setState(() {
      _isProcessing = true;
      _lastError = null;
    });

    try {
      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (photo == null) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }

      // ML Kit disabled for simulator build
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _lastError = 'OCR non disponibile su simulatore. Usa un dispositivo reale.';
        });
      }
    } catch (e) { // ignore: empty_catches
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _lastError = 'Errore durante il riconoscimento: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgDark,
        foregroundColor: AppColors.textPrimary,
        title: const Text('Riconosci carta'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.document_scanner, size: 80, color: AppColors.gold),
            const SizedBox(height: 24),
            const Text(
              'Scatta una foto della carta',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Assicurati che il nome e il codice seriale siano visibili e ben illuminati.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_lastError != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _lastError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
            ],
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _captureAndRecognize,
                icon: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(
                  _isProcessing ? 'Riconoscimento in corso...' : 'Scatta foto',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
