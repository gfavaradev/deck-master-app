class PokemonCard {
  final int id;
  final String apiId; // pokemontcg.io id, e.g. "base1-4"
  final String name;
  final String? supertype; // Pokémon, Trainer, Energy
  final String? subtype; // Stage 1, Basic, Item, etc.
  final int? hp;
  final String? types; // comma-separated
  final String? rarity;
  final String? setId; // e.g. "base1"
  final String? setName; // e.g. "Base Set"
  final String? setSeries; // e.g. "Base"
  final String? number; // collector's number
  final String? imageUrl;       // images.large (compressed, stored in Firebase Storage)

  // Translations
  final String? nameIt;
  final String? nameFr;
  final String? nameDe;
  final String? namePt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  PokemonCard({
    required this.id,
    required this.apiId,
    required this.name,
    this.supertype,
    this.subtype,
    this.hp,
    this.types,
    this.rarity,
    this.setId,
    this.setName,
    this.setSeries,
    this.number,
    this.imageUrl,
    this.nameIt,
    this.nameFr,
    this.nameDe,
    this.namePt,
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'api_id': apiId,
      'name': name,
      'supertype': supertype,
      'subtype': subtype,
      'hp': hp,
      'types': types,
      'rarity': rarity,
      'set_id': setId,
      'set_name': setName,
      'set_series': setSeries,
      'number': number,
      'image_url': imageUrl,
      'name_it': nameIt,
      'name_fr': nameFr,
      'name_de': nameDe,
      'name_pt': namePt,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory PokemonCard.fromMap(Map<String, dynamic> map) {
    return PokemonCard(
      id: map['id'] as int,
      apiId: map['api_id'] ?? '',
      name: map['name'] ?? '',
      supertype: map['supertype'],
      subtype: map['subtype'],
      hp: map['hp'] as int?,
      types: map['types'],
      rarity: map['rarity'],
      setId: map['set_id'],
      setName: map['set_name'],
      setSeries: map['set_series'],
      number: map['number'],
      imageUrl: map['image_url'],
      nameIt: map['name_it'],
      nameFr: map['name_fr'],
      nameDe: map['name_de'],
      namePt: map['name_pt'],
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }
}

class PokemonPrint {
  final int? id;
  final int cardId;
  final String setCode; // EN api_id, e.g. "base1-4"
  final String? setName;
  final String? rarity;
  final double? setPrice;
  final String? artwork;

  // IT
  final String? setCodeIt;
  final String? setNameIt;
  final String? rarityIt;
  final double? setPriceIt;
  // FR
  final String? setCodeFr;
  final String? setNameFr;
  final String? rarityFr;
  final double? setPriceFr;
  // DE
  final String? setCodeDe;
  final String? setNameDe;
  final String? rarityDe;
  final double? setPriceDe;
  // PT
  final String? setCodePt;
  final String? setNamePt;
  final String? rarityPt;
  final double? setPricePt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  PokemonPrint({
    this.id,
    required this.cardId,
    required this.setCode,
    this.setName,
    this.rarity,
    this.setPrice,
    this.artwork,
    this.setCodeIt,
    this.setNameIt,
    this.rarityIt,
    this.setPriceIt,
    this.setCodeFr,
    this.setNameFr,
    this.rarityFr,
    this.setPriceFr,
    this.setCodeDe,
    this.setNameDe,
    this.rarityDe,
    this.setPriceDe,
    this.setCodePt,
    this.setNamePt,
    this.rarityPt,
    this.setPricePt,
    this.createdAt,
    this.updatedAt,
  });

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

  String? getLocalizedSetName(String languageCode) {
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

  String? getLocalizedRarity(String languageCode) {
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
      'set_price': setPrice,
      'artwork': artwork,
      'set_code_it': setCodeIt,
      'set_name_it': setNameIt,
      'rarity_it': rarityIt,
      'set_price_it': setPriceIt,
      'set_code_fr': setCodeFr,
      'set_name_fr': setNameFr,
      'rarity_fr': rarityFr,
      'set_price_fr': setPriceFr,
      'set_code_de': setCodeDe,
      'set_name_de': setNameDe,
      'rarity_de': rarityDe,
      'set_price_de': setPriceDe,
      'set_code_pt': setCodePt,
      'set_name_pt': setNamePt,
      'rarity_pt': rarityPt,
      'set_price_pt': setPricePt,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory PokemonPrint.fromMap(Map<String, dynamic> map) {
    return PokemonPrint(
      id: map['id'] as int?,
      cardId: map['card_id'] as int,
      setCode: map['set_code'] ?? '',
      setName: map['set_name'],
      rarity: map['rarity'],
      setPrice: (map['set_price'] as num?)?.toDouble(),
      artwork: map['artwork'],
      setCodeIt: map['set_code_it'],
      setNameIt: map['set_name_it'],
      rarityIt: map['rarity_it'],
      setPriceIt: (map['set_price_it'] as num?)?.toDouble(),
      setCodeFr: map['set_code_fr'],
      setNameFr: map['set_name_fr'],
      rarityFr: map['rarity_fr'],
      setPriceFr: (map['set_price_fr'] as num?)?.toDouble(),
      setCodeDe: map['set_code_de'],
      setNameDe: map['set_name_de'],
      rarityDe: map['rarity_de'],
      setPriceDe: (map['set_price_de'] as num?)?.toDouble(),
      setCodePt: map['set_code_pt'],
      setNamePt: map['set_name_pt'],
      rarityPt: map['rarity_pt'],
      setPricePt: (map['set_price_pt'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }
}

class PokemonPrice {
  final int? id;
  final int printId;
  final String language;
  final double? cardmarketPrice;
  final double? tcgplayerPrice;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  PokemonPrice({
    this.id,
    required this.printId,
    required this.language,
    this.cardmarketPrice,
    this.tcgplayerPrice,
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
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory PokemonPrice.fromMap(Map<String, dynamic> map) {
    return PokemonPrice(
      id: map['id'] as int?,
      printId: map['print_id'] as int,
      language: map['language'] ?? 'EN',
      cardmarketPrice: (map['cardmarket_price'] as num?)?.toDouble(),
      tcgplayerPrice: (map['tcgplayer_price'] as num?)?.toDouble(),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at']) : null,
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at']) : null,
    );
  }
}
