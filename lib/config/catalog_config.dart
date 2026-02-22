import '../constants/app_constants.dart';

/// Configuration for different card game catalogs
/// This allows easy addition of new catalogs in the future
class CatalogConfig {
  final String key;
  final String displayName;
  final String collectionName;
  final List<String> supportedLanguages;
  final CatalogFieldConfig fieldConfig;

  const CatalogConfig({
    required this.key,
    required this.displayName,
    required this.collectionName,
    required this.supportedLanguages,
    required this.fieldConfig,
  });

  /// Get catalog configuration by key
  static CatalogConfig? getConfig(String catalogKey) {
    return _catalogConfigs[catalogKey];
  }

  /// Get all available catalogs
  static List<CatalogConfig> getAllConfigs() {
    return _catalogConfigs.values.toList();
  }

  /// Get all catalog keys
  static List<String> getAllKeys() {
    return _catalogConfigs.keys.toList();
  }

  /// Check if a catalog exists
  static bool exists(String catalogKey) {
    return _catalogConfigs.containsKey(catalogKey);
  }
}

/// Field configuration for a catalog
class CatalogFieldConfig {
  final List<CardFieldDefinition> fields;
  final List<String> requiredFields;

  const CatalogFieldConfig({
    required this.fields,
    required this.requiredFields,
  });

  /// Get field by key
  CardFieldDefinition? getField(String key) {
    try {
      return fields.firstWhere((f) => f.key == key);
    } catch (e) {
      return null;
    }
  }
}

/// Definition of a card field
class CardFieldDefinition {
  final String key;
  final String label;
  final FieldType type;
  final bool isMultilingual;
  final List<String>? options; // For dropdown fields
  final int? maxLines;
  final bool isRequired;

  const CardFieldDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.isMultilingual = false,
    this.options,
    this.maxLines = 1,
    this.isRequired = false,
  });
}

enum FieldType {
  text,
  number,
  dropdown,
  multiselect,
  textarea,
}

// ============================================================
// Catalog Configurations
// ============================================================

final Map<String, CatalogConfig> _catalogConfigs = {
  CatalogConstants.yugioh: CatalogConfig(
    key: CatalogConstants.yugioh,
    displayName: 'Yu-Gi-Oh!',
    collectionName: CatalogConstants.getCollectionName(CatalogConstants.yugioh),
    supportedLanguages: LanguageConstants.allLanguages,
    fieldConfig: const CatalogFieldConfig(
      fields: [
        // Names
        CardFieldDefinition(
          key: 'name',
          label: 'Nome',
          type: FieldType.text,
          isMultilingual: true,
          isRequired: true,
        ),
        // Description
        CardFieldDefinition(
          key: 'description',
          label: 'Descrizione',
          type: FieldType.textarea,
          isMultilingual: true,
          maxLines: 4,
          isRequired: true,
        ),
        // Card Type
        CardFieldDefinition(
          key: 'type',
          label: 'Tipo Carta',
          type: FieldType.dropdown,
          options: YugiohCardTypes.allTypes,
        ),
        // Frame Type
        CardFieldDefinition(
          key: 'frame_type',
          label: 'Frame Type',
          type: FieldType.dropdown,
          options: YugiohFrameTypes.allFrameTypes,
        ),
        // Race (Monster Type)
        CardFieldDefinition(
          key: 'race',
          label: 'Razza',
          type: FieldType.dropdown,
          options: YugiohRaces.allRaces,
        ),
        // Attribute
        CardFieldDefinition(
          key: 'attribute',
          label: 'Attributo',
          type: FieldType.dropdown,
          options: YugiohAttributes.allAttributes,
        ),
        // Archetype
        CardFieldDefinition(
          key: 'archetype',
          label: 'Archetipo',
          type: FieldType.text,
        ),
        // ATK
        CardFieldDefinition(
          key: 'atk',
          label: 'ATK',
          type: FieldType.number,
        ),
        // DEF
        CardFieldDefinition(
          key: 'def',
          label: 'DEF',
          type: FieldType.number,
        ),
        // Level/Rank
        CardFieldDefinition(
          key: 'level',
          label: 'Level/Rank',
          type: FieldType.number,
        ),
        // Pendulum Scale
        CardFieldDefinition(
          key: 'scale',
          label: 'Scale (Pendulum)',
          type: FieldType.number,
        ),
      ],
      requiredFields: ['name', 'description'],
    ),
  ),

  CatalogConstants.pokemon: CatalogConfig(
    key: CatalogConstants.pokemon,
    displayName: 'Pokémon',
    collectionName: CatalogConstants.getCollectionName(CatalogConstants.pokemon),
    supportedLanguages: LanguageConstants.allLanguages,
    fieldConfig: const CatalogFieldConfig(
      fields: [
        CardFieldDefinition(
          key: 'name',
          label: 'Nome',
          type: FieldType.text,
          isMultilingual: true,
          isRequired: true,
        ),
        CardFieldDefinition(
          key: 'description',
          label: 'Descrizione',
          type: FieldType.textarea,
          isMultilingual: true,
          maxLines: 4,
          isRequired: true,
        ),
        // Add Pokemon-specific fields here in the future
      ],
      requiredFields: ['name', 'description'],
    ),
  ),

  CatalogConstants.magic: CatalogConfig(
    key: CatalogConstants.magic,
    displayName: 'Magic: The Gathering',
    collectionName: CatalogConstants.getCollectionName(CatalogConstants.magic),
    supportedLanguages: LanguageConstants.allLanguages,
    fieldConfig: const CatalogFieldConfig(
      fields: [
        CardFieldDefinition(
          key: 'name',
          label: 'Nome',
          type: FieldType.text,
          isMultilingual: true,
          isRequired: true,
        ),
        CardFieldDefinition(
          key: 'description',
          label: 'Descrizione',
          type: FieldType.textarea,
          isMultilingual: true,
          maxLines: 4,
          isRequired: true,
        ),
        // Add MTG-specific fields here in the future
      ],
      requiredFields: ['name', 'description'],
    ),
  ),
};
