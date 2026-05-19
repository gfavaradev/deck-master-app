// Regression test: setState called after widget dispose → UI freeze / "setState after dispose" error
//
// Root cause: several async methods (catalog_page._loadAlbumsAndOwned,
// card_list_page initState .then() callback, card_detail_page._loadExtraInfo)
// call setState without a `if (!mounted) return;` guard. When the user
// navigates away before the Future resolves, Flutter throws:
//   "setState() called after dispose()" → widget tree inconsistency → UI freeze.
//
// Expected (fixed) behaviour: every setState inside an async method that may
// outlive the widget must be guarded with `if (!mounted) return;`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal harness that mimics the async-setState pattern without importing
// the full CatalogPage (which would require Firebase initialisation).
// Each test uses a small StatefulWidget that reproduces the exact pattern.

/// Widget that replicates the unmounted-setState bug in _loadAlbumsAndOwned.
class _UnguardedAsyncWidget extends StatefulWidget {
  final Future<void> Function(void Function() setStateCallback) asyncOp;
  const _UnguardedAsyncWidget({required this.asyncOp});

  @override
  State<_UnguardedAsyncWidget> createState() => _UnguardedAsyncWidgetState();
}

class _UnguardedAsyncWidgetState extends State<_UnguardedAsyncWidget> {
  String _label = 'initial';

  @override
  void initState() {
    super.initState();
    // Mirrors the pattern in catalog_page._loadAlbumsAndOwned:
    // async op fires, then setState is called with no mounted guard.
    widget.asyncOp(() {
      setState(() => _label = 'updated'); // ← BUG: no mounted check
    });
  }

  @override
  Widget build(BuildContext context) => Text(_label);
}

/// Fixed version with mounted guard.
class _GuardedAsyncWidget extends StatefulWidget {
  final Future<void> Function(void Function() setStateCallback) asyncOp;
  const _GuardedAsyncWidget({required this.asyncOp});

  @override
  State<_GuardedAsyncWidget> createState() => _GuardedAsyncWidgetState();
}

class _GuardedAsyncWidgetState extends State<_GuardedAsyncWidget> {
  String _label = 'initial';

  @override
  void initState() {
    super.initState();
    widget.asyncOp(() {
      if (!mounted) return; // ← FIX
      setState(() => _label = 'updated');
    });
  }

  @override
  Widget build(BuildContext context) => Text(_label);
}

void main() {
  group('UI freeze – setState after dispose', () {
    testWidgets(
        'unguarded setState after dispose throws FlutterError (documents current bug)',
        (tester) async {
      // Capture Flutter errors instead of letting them propagate
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) => errors.add(details);

      final completer = Future<void>.delayed(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        MaterialApp(
          home: _UnguardedAsyncWidget(
            asyncOp: (cb) async {
              await completer;
              cb(); // called after the widget may be disposed
            },
          ),
        ),
      );

      // Navigate away (dispose the widget) before the Future resolves
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // Wait for the delayed Future to fire and call setState on a dead widget
      await tester.pump(const Duration(milliseconds: 100));

      // Restore error handler
      FlutterError.onError = FlutterError.presentError;

      // The unguarded version SHOULD have produced an error.
      // If it does not, this test needs updating.
      // (With the bug present, errors.isNotEmpty — this is the regression marker.)
      expect(
        errors.any((e) => e.toString().contains('setState') || e.toString().contains('mounted')),
        isTrue,
        reason: 'Expected a "setState after dispose" error with the unguarded pattern. '
            'If this assertion fails, the bug may already be fixed — verify and update this test.',
      );
    });

    testWidgets('guarded setState after dispose produces NO error (passing target)', (tester) async {
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) => errors.add(details);

      final completer = Future<void>.delayed(const Duration(milliseconds: 50));

      await tester.pumpWidget(
        MaterialApp(
          home: _GuardedAsyncWidget(
            asyncOp: (cb) async {
              await completer;
              cb();
            },
          ),
        ),
      );

      // Dispose before future resolves
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 100));

      FlutterError.onError = FlutterError.presentError;

      expect(
        errors,
        isEmpty,
        reason: 'Guarded setState must not throw after widget dispose.',
      );
    });

    testWidgets('setState called while mounted completes normally', (tester) async {
      final errors = <FlutterErrorDetails>[];
      FlutterError.onError = (details) => errors.add(details);

      await tester.pumpWidget(
        MaterialApp(
          home: _GuardedAsyncWidget(
            asyncOp: (cb) async {
              // resolves immediately — widget still mounted
              cb();
            },
          ),
        ),
      );

      await tester.pump();
      FlutterError.onError = FlutterError.presentError;

      expect(errors, isEmpty);
      expect(find.text('updated'), findsOneWidget);
    });
  });
}
