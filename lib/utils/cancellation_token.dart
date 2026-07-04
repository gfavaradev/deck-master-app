/// Thrown from an `onProgress` callback to unwind a long-running admin
/// operation once [CancellationToken.cancel] has been called.
class CancelledException implements Exception {
  const CancelledException();
}

/// Cooperative cancellation flag shared between an admin page (which owns the
/// "Annulla" button) and the `onProgress` callback passed into
/// `AdminCatalogService` — the callback checks [isCancelled] and throws
/// [CancelledException] to stop the operation at its next checkpoint.
class CancellationToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}
