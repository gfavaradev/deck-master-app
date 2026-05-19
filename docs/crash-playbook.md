# Crash Playbook — deck_master

Regression tests live in `integration_test/crashes/`. Each section below documents
the root cause, the test file that catches it, and the required fix.

Run the full suite:
```bash
# Headless (CI / no device)
flutter test integration_test/regression_suite.dart

# On a connected Android emulator
flutter drive \
  --driver test_driver/integration_test.dart \
  --target integration_test/regression_suite.dart
```

---

## CRASH-1 · Firestore OOM — unbounded collection queries

**Test file:** `integration_test/crashes/firestore_oom_test.dart`

**Symptom:** App crashes with `OutOfMemoryError` or a Firestore serialization crash
on Android devices with < 3 GB RAM when the user has large collections (> 500 cards,
> 200 albums).

**Root cause:** `FirestoreService.getCards()`, `getAlbums()`, `getCollections()`, and
`getDecks()` all call `.get()` with no `.limit()` guard. A user with 2 000 cards
materialises all 2 000 `DocumentSnapshot` objects into the Dart heap at once before
any can be GC'd.

**Files:** `lib/services/firestore_service.dart` lines 262–404

**Fix:**
```dart
// Add .limit(500) to every unbounded .get() call, e.g.:
Future<List<Map<String, dynamic>>> getCards(String userId) async {
  const int kLimit = 500;
  final snapshot = await _firestore
      .collection(FirestorePaths.userCards(userId))
      .limit(kLimit)      // ← add this
      .get();
  // ...
}
```
For callers that genuinely need all documents, implement a paginated helper that
fetches in batches of 500 and yields results via a `Stream`.

**Verified fixed when:** `firestore_oom_test.dart` passes with 10 000 seeded documents.

---

## CRASH-2 · Parallel catalog downloads — heap OOM

**Test file:** `integration_test/crashes/parallel_download_test.dart`

**Symptom:** App runs out of memory mid-download on low-RAM devices (2 GB) when
fetching a large catalog (e.g. Yu-Gi-Oh with 10 000+ cards across 50+ chunks).

**Root cause:** `fetchCatalog()` in `firestore_service.dart` (lines 112–169) accumulates
all card maps from all batches into a single `allCards` list before writing to SQLite.
Peak memory = `totalChunks × cardsPerChunk × mapSize` held simultaneously.

**Files:** `lib/services/firestore_service.dart` lines 130–154

**Fix:** Flush each batch to SQLite via the `onBatch` callback before fetching the next,
so peak memory is bounded to `batchSize × cardsPerChunk`:
```dart
// Change fetchCatalog signature to accept an onBatch callback:
Future<void> fetchCatalog(
  String catalogName, {
  required Future<void> Function(List<Map<String, dynamic>> batch) onBatch,
  void Function(int current, int total)? onProgress,
}) async {
  // ...
  for (int start = 1; start <= totalChunks; start += batchSize) {
    final batch = await _fetchChunkCards(catalogName, start, end);
    await onBatch(batch);   // ← flush before next batch
    onProgress?.call(end, totalChunks);
  }
}
```

**Verified fixed when:** `parallel_download_test.dart` passes with 30 chunks × 200 cards.

---

## CRASH-3 · UI freeze — setState after widget dispose

**Test file:** `integration_test/crashes/ui_freeze_test.dart`

**Symptom:** Navigating away from `CatalogPage` or `CardListPage` during a background
load causes a Flutter error: _"setState() called after dispose()"_ which leaves the
widget tree in an inconsistent state and freezes the UI.

**Root cause:** Multiple async methods call `setState()` without checking `mounted`:
- `catalog_page.dart` line 272 — `_loadAlbumsAndOwned()`
- `catalog_page.dart` line 119 — `initState` `Future.wait` callback
- `card_list_page.dart` line 68 — `LanguageService.then()` callback
- `card_detail_page.dart` lines 93, 107 — `_loadExtraInfo()`, `_navigateTo()`

**Fix:** Add `if (!mounted) return;` before every `setState` inside an `async` method:
```dart
Future<void> _loadAlbumsAndOwned() async {
  final albums = await _repo.getAlbums(...);
  if (!mounted) return;   // ← add before every setState
  setState(() {
    _albums = albums;
  });
}
```

**Verified fixed when:** `ui_freeze_test.dart` — the "unguarded" test produces an error
(documents the bug) and the "guarded" test produces no error.

---

## CRASH-4 · Negative number handling

**Test file:** `integration_test/crashes/negative_number_test.dart`

**Symptom:** Collection total value shows negative numbers (e.g. "−€120") and card
counts show negative totals in the collection summary bar.

**Root cause:** `CardModel.fromMap()` (`card_model.dart` lines 73–75) accepts any
integer/double for `quantity` and `value` without clamping. A card synced from
Firestore with `quantity: -5` corrupts every downstream fold calculation.

**Files:** `lib/models/card_model.dart` lines 73–75, `lib/pages/card_list_page.dart`
lines 616–636

**Fix:**
```dart
// In CardModel.fromMap():
quantity: ((map['quantity'] as int?) ?? 1).clamp(0, 9999),
value: ((map['value'] as num?)?.toDouble() ?? 0.0).clamp(0.0, double.infinity),
purchasePrice: ((map['purchase_price'] as num?)?.toDouble())?.clamp(0.0, double.infinity),
```

**Verified fixed when:** `negative_number_test.dart` passes (all clamp/fold tests green).

---

## CRASH-5 · Search scope bugs

**Test file:** `integration_test/crashes/search_scope_test.dart`

**Symptom:** Searching by card name returns no results even though the card is in the
collection. Typing quickly produces stale results from a previous query.

**Root cause:**
1. `_applyFilter()` in `card_list_page.dart` line 133 checks only `serialNumber`,
   not `name`. A search for "Dark Magician" returns nothing.
2. `_searchCatalog()` in `card_list_page.dart` does have a `if (!mounted) return`
   guard but does not discard results if the query changed before resolution —
   stale results overwrite the current UI state.

**Files:** `lib/pages/card_list_page.dart` lines 130–164

**Fix:**
```dart
// Widen the local filter to include name:
bool matches(CardModel card) =>
    card.serialNumber.toLowerCase().contains(q) ||
    card.name.toLowerCase().contains(q);

// Guard catalog results against stale queries:
Future<void> _searchCatalog(String query) async {
  final results = await _repo.getCatalogCardsByCollection(...);
  if (!mounted || _lastQuery != query) return; // ← stale guard
  setState(() { _catalogSuggestions = results; });
}
```

**Verified fixed when:** `search_scope_test.dart` — name search returns 1 result
and stale result test shows empty suggestions.

---

## CRASH-6 · Album selection state

**Test file:** `integration_test/crashes/album_selection_test.dart`

**Symptom:** After navigating between cards, the wrong album is pre-selected in the
"add card" dialog. Occasionally crashes with a `StateError` when a previously-used
album has been deleted.

**Root cause:**
1. `albumId = -1` is the sentinel for "no album" but the mapping to `null` for UI
   state only happens in `card_detail_page.dart` line 110 — other code paths don't
   apply the same conversion, causing inconsistency.
2. `lastUsedAlbumId` persisted in `SharedPreferences` is never validated against the
   current album list — a deleted album causes `.firstWhere()` to throw `StateError`
   unless `orElse` is present.
3. The `forEachState` in `card_dialogs.dart` already has a null guard before
   `selectedAlbumId!` (line 542), but stale navigation state can bypass it.

**Files:** `lib/pages/card_detail_page.dart` line 110, `lib/widgets/card_dialogs.dart`
lines 274, 550–551, `lib/pages/catalog_page.dart` lines 108, 449, 522

**Fix:**
```dart
// Validate lastUsedAlbumId on load:
final lastId = prefs.getInt('last_album_id_$collectionKey');
final isValid = availableAlbums.any((a) => a.id == lastId);
_lastUsedAlbumId = isValid ? lastId : null;

// Always use orElse in firstWhere:
final targetAlbum = availableAlbums.firstWhere(
  (a) => a.id == selectedAlbumId,
  orElse: () => AlbumModel(name: '', collection: '', maxCapacity: 0),
);
```

**Verified fixed when:** `album_selection_test.dart` — all 8 tests pass including the
deleted-album and stale-prefs scenarios.

---

## Running with memory profiling

To capture a memory profile alongside the regression suite on a real device:

```bash
# 1. Start the app in profile mode with Observatory
flutter run --profile integration_test/regression_suite.dart

# 2. In a second terminal, capture a DevTools memory snapshot:
flutter pub global run devtools --vm-service-uri=<observatory-uri>

# 3. Or use the built-in timeline recorder:
flutter drive \
  --driver test_driver/integration_test.dart \
  --target integration_test/regression_suite.dart \
  --profile \
  --trace-startup
```

The CRASH-1 (Firestore OOM) and CRASH-2 (parallel download OOM) tests are the ones
most worth profiling — look for heap spikes above 150 MB during those groups.

---

## CI integration

The regression suite runs as the `test` job in `.github/workflows/release.yml` and
**blocks the build job** — a failing regression test prevents a release from shipping.

The `APP_SECRETS_DART_BASE64` secret must be set in the repository for the test job
to compile successfully (same pattern as the existing secrets for keystore / .env).
