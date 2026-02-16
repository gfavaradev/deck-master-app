class YugiohCard {
  final int id;
  final String type;
  final String? humanReadableType;
  final String? frameType;
  final String race;
  final String? archetype;
  final String? ygoprodeckUrl;

  // Monster fields (null for spells/traps)
  final int? atk;
  final int? def;
  final int? level;
  final String? attribute;
  final int? scale;
  final int? linkval;
  final String? linkmarkers;

  // EN (base)
  final String name;
  final String description;

  // Translations
  final String? nameIt;
  final String? descriptionIt;
  final String? nameFr;
  final String? descriptionFr;
  final String? nameDe;
  final String? descriptionDe;
  final String? namePt;
  final String? descriptionPt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  YugiohCard({
    required this.id,
    required this.type,
    this.humanReadableType,
    this.frameType,
    required this.race,
    this.archetype,
    this.ygoprodeckUrl,
    this.atk,
    this.def,
    this.level,
    this.attribute,
    this.scale,
    this.linkval,
    this.linkmarkers,
    required this.name,
    required this.description,
    this.nameIt,
    this.descriptionIt,
    this.nameFr,
    this.descriptionFr,
    this.nameDe,
    this.descriptionDe,
    this.namePt,
    this.descriptionPt,
    this.createdAt,
    this.updatedAt,
  });

  String getLocalizedName(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return nameIt ?? name;
      case 'FR':
        return nameFr ?? name;
      case 'DE':
        return nameDe ?? name;
      case 'PT':
        return namePt ?? name;
      default:
        return name;
    }
  }

  String getLocalizedDescription(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return descriptionIt ?? description;
      case 'FR':
        return descriptionFr ?? description;
      case 'DE':
        return descriptionDe ?? description;
      case 'PT':
        return descriptionPt ?? description;
      default:
        return description;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'human_readable_type': humanReadableType,
      'frame_type': frameType,
      'race': race,
      'archetype': archetype,
      'ygoprodeck_url': ygoprodeckUrl,
      'atk': atk,
      'def': def,
      'level': level,
      'attribute': attribute,
      'scale': scale,
      'linkval': linkval,
      'linkmarkers': linkmarkers,
      'name': name,
      'description': description,
      'name_it': nameIt,
      'description_it': descriptionIt,
      'name_fr': nameFr,
      'description_fr': descriptionFr,
      'name_de': nameDe,
      'description_de': descriptionDe,
      'name_pt': namePt,
      'description_pt': descriptionPt,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory YugiohCard.fromMap(Map<String, dynamic> map) {
    return YugiohCard(
      id: map['id'] as int,
      type: map['type'] ?? '',
      humanReadableType: map['human_readable_type'],
      frameType: map['frame_type'],
      race: map['race'] ?? '',
      archetype: map['archetype'],
      ygoprodeckUrl: map['ygoprodeck_url'],
      atk: map['atk'] as int?,
      def: map['def'] as int?,
      level: map['level'] as int?,
      attribute: map['attribute'],
      scale: map['scale'] as int?,
      linkval: map['linkval'] as int?,
      linkmarkers: map['linkmarkers'],
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      nameIt: map['name_it'],
      descriptionIt: map['description_it'],
      nameFr: map['name_fr'],
      descriptionFr: map['description_fr'],
      nameDe: map['name_de'],
      descriptionDe: map['description_de'],
      namePt: map['name_pt'],
      descriptionPt: map['description_pt'],
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }
}

class YugiohPrint {
  final int? id;
  final int cardId;
  final String setCode;
  final String setName;
  final String rarity;
  final String? rarityCode;
  final double? setPrice;
  final String? artwork;

  // IT
  final String? setNameIt;
  final String? setCodeIt;
  final String? rarityIt;
  final String? rarityCodeIt;
  final double? setPriceIt;
  // FR
  final String? setNameFr;
  final String? setCodeFr;
  final String? rarityFr;
  final String? rarityCodeFr;
  final double? setPriceFr;
  // DE
  final String? setNameDe;
  final String? setCodeDe;
  final String? rarityDe;
  final String? rarityCodeDe;
  final double? setPriceDe;
  // PT
  final String? setNamePt;
  final String? setCodePt;
  final String? rarityPt;
  final String? rarityCodePt;
  final double? setPricePt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  YugiohPrint({
    this.id,
    required this.cardId,
    required this.setCode,
    required this.setName,
    required this.rarity,
    this.rarityCode,
    this.setPrice,
    this.artwork,
    this.setNameIt,
    this.setCodeIt,
    this.rarityIt,
    this.rarityCodeIt,
    this.setPriceIt,
    this.setNameFr,
    this.setCodeFr,
    this.rarityFr,
    this.rarityCodeFr,
    this.setPriceFr,
    this.setNameDe,
    this.setCodeDe,
    this.rarityDe,
    this.rarityCodeDe,
    this.setPriceDe,
    this.setNamePt,
    this.setCodePt,
    this.rarityPt,
    this.rarityCodePt,
    this.setPricePt,
    this.createdAt,
    this.updatedAt,
  });

  String getLocalizedSetName(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return setNameIt ?? setName;
      case 'FR':
        return setNameFr ?? setName;
      case 'DE':
        return setNameDe ?? setName;
      case 'PT':
        return setNamePt ?? setName;
      default:
        return setName;
    }
  }

  String getLocalizedSetCode(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return setCodeIt ?? setCode;
      case 'FR':
        return setCodeFr ?? setCode;
      case 'DE':
        return setCodeDe ?? setCode;
      case 'PT':
        return setCodePt ?? setCode;
      default:
        return setCode;
    }
  }

  String getLocalizedRarity(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return rarityIt ?? rarity;
      case 'FR':
        return rarityFr ?? rarity;
      case 'DE':
        return rarityDe ?? rarity;
      case 'PT':
        return rarityPt ?? rarity;
      default:
        return rarity;
    }
  }

  String? getLocalizedRarityCode(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return rarityCodeIt ?? rarityCode;
      case 'FR':
        return rarityCodeFr ?? rarityCode;
      case 'DE':
        return rarityCodeDe ?? rarityCode;
      case 'PT':
        return rarityCodePt ?? rarityCode;
      default:
        return rarityCode;
    }
  }

  double? getLocalizedPrice(String languageCode) {
    switch (languageCode.toUpperCase()) {
      case 'IT':
        return setPriceIt ?? setPrice;
      case 'FR':
        return setPriceFr ?? setPrice;
      case 'DE':
        return setPriceDe ?? setPrice;
      case 'PT':
        return setPricePt ?? setPrice;
      default:
        return setPrice;
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'card_id': cardId,
      'set_code': setCode,
      'set_name': setName,
      'rarity': rarity,
      'rarity_code': rarityCode,
      'set_price': setPrice,
      'artwork': artwork,
      'set_name_it': setNameIt,
      'set_code_it': setCodeIt,
      'rarity_it': rarityIt,
      'rarity_code_it': rarityCodeIt,
      'set_price_it': setPriceIt,
      'set_name_fr': setNameFr,
      'set_code_fr': setCodeFr,
      'rarity_fr': rarityFr,
      'rarity_code_fr': rarityCodeFr,
      'set_price_fr': setPriceFr,
      'set_name_de': setNameDe,
      'set_code_de': setCodeDe,
      'rarity_de': rarityDe,
      'rarity_code_de': rarityCodeDe,
      'set_price_de': setPriceDe,
      'set_name_pt': setNamePt,
      'set_code_pt': setCodePt,
      'rarity_pt': rarityPt,
      'rarity_code_pt': rarityCodePt,
      'set_price_pt': setPricePt,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory YugiohPrint.fromMap(Map<String, dynamic> map) {
    return YugiohPrint(
      id: map['id'] as int?,
      cardId: map['card_id'] as int,
      setCode: map['set_code'] ?? '',
      setName: map['set_name'] ?? '',
      rarity: map['rarity'] ?? '',
      rarityCode: map['rarity_code'],
      setPrice: (map['set_price'] as num?)?.toDouble(),
      artwork: map['artwork'],
      setNameIt: map['set_name_it'],
      setCodeIt: map['set_code_it'],
      rarityIt: map['rarity_it'],
      rarityCodeIt: map['rarity_code_it'],
      setPriceIt: (map['set_price_it'] as num?)?.toDouble(),
      setNameFr: map['set_name_fr'],
      setCodeFr: map['set_code_fr'],
      rarityFr: map['rarity_fr'],
      rarityCodeFr: map['rarity_code_fr'],
      setPriceFr: (map['set_price_fr'] as num?)?.toDouble(),
      setNameDe: map['set_name_de'],
      setCodeDe: map['set_code_de'],
      rarityDe: map['rarity_de'],
      rarityCodeDe: map['rarity_code_de'],
      setPriceDe: (map['set_price_de'] as num?)?.toDouble(),
      setNamePt: map['set_name_pt'],
      setCodePt: map['set_code_pt'],
      rarityPt: map['rarity_pt'],
      rarityCodePt: map['rarity_code_pt'],
      setPricePt: (map['set_price_pt'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }
}

class YugiohPrice {
  final int? id;
  final int printId;
  final String language;
  final double? cardmarketPrice;
  final double? tcgplayerPrice;
  final double? ebayPrice;
  final double? amazonPrice;
  final double? coolstuffincPrice;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  YugiohPrice({
    this.id,
    required this.printId,
    required this.language,
    this.cardmarketPrice,
    this.tcgplayerPrice,
    this.ebayPrice,
    this.amazonPrice,
    this.coolstuffincPrice,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'print_id': printId,
      'language': language,
      'cardmarket_price': cardmarketPrice,
      'tcgplayer_price': tcgplayerPrice,
      'ebay_price': ebayPrice,
      'amazon_price': amazonPrice,
      'coolstuffinc_price': coolstuffincPrice,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory YugiohPrice.fromMap(Map<String, dynamic> map) {
    return YugiohPrice(
      id: map['id'] as int?,
      printId: map['print_id'] as int,
      language: map['language'] ?? 'EN',
      cardmarketPrice: (map['cardmarket_price'] as num?)?.toDouble(),
      tcgplayerPrice: (map['tcgplayer_price'] as num?)?.toDouble(),
      ebayPrice: (map['ebay_price'] as num?)?.toDouble(),
      amazonPrice: (map['amazon_price'] as num?)?.toDouble(),
      coolstuffincPrice: (map['coolstuffinc_price'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }
}
