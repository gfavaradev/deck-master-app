// Dart 3 extension methods for common operations in DeckMaster.
// Centralises repeated patterns to reduce boilerplate and improve consistency.

/// Price formatting for CardTrader prices (stored as euro cents).
extension PriceCentsExt on int {
  /// Formats cents to a Euro string, e.g. 350 → "€3.50"
  String get euroDisplay => '€${(this / 100).toStringAsFixed(2)}';
}

extension NullablePriceCentsExt on int? {
  /// Returns "—" if null, otherwise formats as euro.
  String get euroDisplayOrDash => this == null ? '—' : '€${(this! / 100).toStringAsFixed(2)}';
}

extension NullableDoubleExt on double? {
  /// Formats a nullable price double, e.g. 3.5 → "€3.50", null → "—"
  String get euroDisplayOrDash => this == null || this! <= 0 ? '—' : '€${this!.toStringAsFixed(2)}';
}

/// Common string helpers used throughout the app.
extension StringExt on String {
  /// Extracts the expansion code from a serial number.
  /// "LOB-EN001" → "lob", "swsh1-1" → "swsh1", "OP01-001" → "op01"
  String get serialExpansionCode => isEmpty ? '' : split('-').first.toLowerCase();

  /// Extracts the collector number from a serial number.
  /// "LOB-EN001" → "EN001", "swsh1-1" → "1", "OP01-001" → "001"
  String get serialCollectorNumber {
    final idx = indexOf('-');
    return idx < 0 ? '' : substring(idx + 1);
  }

  /// Returns the display name for a collection key.
  String get collectionDisplayName => switch (this) {
    'yugioh'           => 'Yu-Gi-Oh!',
    'pokemon'          => 'Pokémon',
    'onepiece'         => 'One Piece TCG',
    'magic'            => 'Magic: The Gathering',
    'digimon'          => 'Digimon',
    'lorcana'          => 'Disney Lorcana',
    'flesh-and-blood'  => 'Flesh and Blood',
    'vanguard'         => 'Cardfight!! Vanguard',
    'dragon-ball-super'=> 'Dragon Ball Super',
    'star-wars'        => 'Star Wars: Unlimited',
    'riftbound'        => 'Riftbound',
    'gundam'           => 'Gundam Card Game',
    'union-arena'      => 'Union Arena',
    _                  => this,
  };

  /// Returns the CardTrader search URL slug for a collection.
  String? get ctSlug => switch (this) {
    'yugioh'   => 'yu-gi-oh',
    'pokemon'  => 'pokemon',
    'onepiece' => 'one-piece',
    _          => null,
  };

  /// Whether this string is null-safe non-empty (trim-aware).
  bool get isNotBlank => trim().isNotEmpty;
}

/// Null-safe string extensions.
extension NullableStringExt on String? {
  bool get isNullOrBlank => this == null || this!.trim().isEmpty;
  bool get isNotNullOrBlank => !isNullOrBlank;
  String get orEmpty => this ?? '';
}

/// List helpers for common card operations.
extension ListExt<T> on List<T> {
  /// Returns null if the list is empty, otherwise returns itself.
  List<T>? get nullIfEmpty => isEmpty ? null : this;
}
