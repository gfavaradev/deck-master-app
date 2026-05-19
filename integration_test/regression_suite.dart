// Entry point for the full regression test suite.
// Run via:
//   flutter test integration_test/regression_suite.dart          ← headless (CI)
//   flutter drive --driver test_driver/integration_test.dart \   ← on device
//               --target integration_test/regression_suite.dart

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'crashes/firestore_oom_test.dart' as firestore_oom;
import 'crashes/parallel_download_test.dart' as parallel_download;
import 'crashes/ui_freeze_test.dart' as ui_freeze;
import 'crashes/negative_number_test.dart' as negative_number;
import 'crashes/search_scope_test.dart' as search_scope;
import 'crashes/album_selection_test.dart' as album_selection;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Regression suite — deck_master crash classes', () {
    group('[CRASH-1] Firestore OOM', firestore_oom.main);
    group('[CRASH-2] Parallel download OOM', parallel_download.main);
    group('[CRASH-3] UI freeze / setState after dispose', ui_freeze.main);
    group('[CRASH-4] Negative number handling', negative_number.main);
    group('[CRASH-5] Search scope', search_scope.main);
    group('[CRASH-6] Album selection state', album_selection.main);
  });
}
