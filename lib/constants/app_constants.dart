/// Centralized constants for the entire application
/// This ensures consistency and easy maintenance

// ============================================================
// Catalog Constants
// ============================================================

class CatalogConstants {
  static const String yugioh = 'yugioh';
  static const String pokemon = 'pokemon';
  static const String magic = 'magic';

  static const List<String> allCatalogs = [yugioh, pokemon, magic];

  /// Get Firestore collection name for a catalog
  static String getCollectionName(String catalog) => '${catalog}_catalog';

  /// Get display name for a catalog
  static String getDisplayName(String catalog) {
    switch (catalog) {
      case yugioh:
        return 'Yu-Gi-Oh!';
      case pokemon:
        return 'Pokémon';
      case magic:
        return 'Magic: The Gathering';
      default:
        return catalog;
    }
  }
}

// ============================================================
// Language Constants
// ============================================================

class LanguageConstants {
  static const String english = 'en';
  static const String italian = 'it';
  static const String french = 'fr';
  static const String german = 'de';
  static const String portuguese = 'pt';

  static const List<String> allLanguages = [
    english,
    italian,
    french,
    german,
    portuguese,
  ];

  static const Map<String, String> languageNames = {
    english: 'English',
    italian: 'Italiano',
    french: 'Français',
    german: 'Deutsch',
    portuguese: 'Português',
  };

  /// Get field name for a language (e.g., 'name_it', 'description_fr')
  static String getFieldName(String baseField, String language) {
    if (language == english) return baseField;
    return '${baseField}_$language';
  }
}

// ============================================================
// Yu-Gi-Oh Card Type Constants
// ============================================================

class YugiohCardTypes {
  static const String monster = 'Monster Card';
  static const String spell = 'Spell Card';
  static const String trap = 'Trap Card';

  static const List<String> allTypes = [monster, spell, trap];
}

class YugiohFrameTypes {
  static const String normal = 'Normal';
  static const String effect = 'Effect';
  static const String ritual = 'Ritual';
  static const String fusion = 'Fusion';
  static const String synchro = 'Synchro';
  static const String xyz = 'Xyz';
  static const String pendulum = 'Pendulum';
  static const String link = 'Link';

  static const List<String> allFrameTypes = [
    normal,
    effect,
    ritual,
    fusion,
    synchro,
    xyz,
    pendulum,
    link,
  ];
}

class YugiohRaces {
  static const List<String> allRaces = [
    'Dragon',
    'Spellcaster',
    'Warrior',
    'Beast-Warrior',
    'Beast',
    'Fiend',
    'Zombie',
    'Machine',
    'Aqua',
    'Pyro',
    'Rock',
    'Winged Beast',
    'Plant',
    'Insect',
    'Thunder',
    'Dinosaur',
    'Fish',
    'Sea Serpent',
    'Reptile',
    'Psychic',
    'Divine-Beast',
    'Creator God',
    'Wyrm',
    'Cyberse',
  ];
}

class YugiohAttributes {
  static const String dark = 'DARK';
  static const String light = 'LIGHT';
  static const String water = 'WATER';
  static const String fire = 'FIRE';
  static const String earth = 'EARTH';
  static const String wind = 'WIND';
  static const String divine = 'DIVINE';

  static const List<String> allAttributes = [
    dark,
    light,
    water,
    fire,
    earth,
    wind,
    divine,
  ];
}

class YugiohLinkMarkers {
  static const List<String> allMarkers = [
    'Top',
    'Top-Left',
    'Top-Right',
    'Left',
    'Right',
    'Bottom',
    'Bottom-Left',
    'Bottom-Right',
  ];
}

class YugiohRarities {
  static const List<String> commonRarities = [
    'Common',
    'Rare',
    'Super Rare',
    'Ultra Rare',
    'Secret Rare',
    'Ultimate Rare',
    'Ghost Rare',
    'Starlight Rare',
    'Collector\'s Rare',
    'Prismatic Secret Rare',
  ];
}

// ============================================================
// ID Range Constants
// ============================================================

class IdRangeConstants {
  /// Custom card IDs start from this value to avoid conflicts with YGOPRODeck
  static const int customCardIdBase = 900000000;

  /// Maximum value for modulo operation (100 million)
  static const int customCardIdModulo = 100000000;

  /// Generate a unique custom card ID
  static int generateCustomCardId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return customCardIdBase + (timestamp % customCardIdModulo);
  }
}

// ============================================================
// Firestore Constants
// ============================================================

class FirestoreConstants {
  /// Collection names
  static const String users = 'users';
  static const String collections = 'collections';
  static const String albums = 'albums';
  static const String cards = 'cards';
  static const String decks = 'decks';

  /// Catalog structure
  static const String catalogMetadata = 'metadata';
  static const String catalogChunks = 'chunks';
  static const String catalogItems = 'items';

  /// Chunk size for catalog uploads
  static const int catalogChunkSize = 1000;

  /// Chunk ID format
  static String getChunkId(int index) => 'chunk_${(index).toString().padLeft(3, '0')}';
}

// ============================================================
// Database Constants
// ============================================================

class DatabaseConstants {
  /// Table names
  static const String albums = 'albums';
  static const String cards = 'cards';
  static const String decks = 'decks';
  static const String deckCards = 'deck_cards';
  static const String collectionsTable = 'collections';
  static const String pendingSync = 'pending_sync';
  static const String catalogMetadata = 'catalog_metadata';

  /// Yugioh-specific tables
  static const String yugiohCards = 'yugioh_cards';
  static const String yugiohPrints = 'yugioh_prints';
  static const String yugiohPrices = 'yugioh_prices';
}

// ============================================================
// Validation Constants
// ============================================================

class ValidationConstants {
  /// Minimum lengths
  static const int minNameLength = 1;
  static const int minDescriptionLength = 1;

  /// Maximum lengths
  static const int maxNameLength = 200;
  static const int maxDescriptionLength = 2000;
  static const int maxAlbumCapacity = 1000;

  /// Card value limits
  static const double minCardValue = 0.0;
  static const double maxCardValue = 999999.99;
}

// ============================================================
// UI Constants
// ============================================================

class UIConstants {
  /// Default pagination
  static const int catalogPageSize = 60;

  /// Dialog sizes
  static const double adminCardDialogWidth = 800;
  static const double adminCardDialogHeight = 700;

  /// Debounce durations
  static const Duration searchDebounce = Duration(milliseconds: 500);
}
