import 'package:flutter_test/flutter_test.dart';

import '../integration_test/crashes/firestore_oom_test.dart' as firestore_oom;
import '../integration_test/crashes/parallel_download_test.dart' as parallel_download;
import '../integration_test/crashes/ui_freeze_test.dart' as ui_freeze;
import '../integration_test/crashes/negative_number_test.dart' as negative_number;
import '../integration_test/crashes/search_scope_test.dart' as search_scope;
import '../integration_test/crashes/album_selection_test.dart' as album_selection;

void main() {
  group('Regression suite — deck_master crash classes', () {
    group('[CRASH-1] Firestore OOM', firestore_oom.main);
    group('[CRASH-2] Parallel download OOM', parallel_download.main);
    group('[CRASH-3] UI freeze / setState after dispose', ui_freeze.main);
    group('[CRASH-4] Negative number handling', negative_number.main);
    group('[CRASH-5] Search scope', search_scope.main);
    group('[CRASH-6] Album selection state', album_selection.main);
  });
}
