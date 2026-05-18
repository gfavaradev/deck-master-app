class MagicCardModel {
  final int? id;
  final String apiId;
  final String name;
  final String? manaCost;
  final double? cmc;
  final String? typeLine;
  final String? oracleText;
  final String? power;
  final String? toughness;
  final String? colors;
  final String? rarity;
  final String? setCode;
  final String? setName;
  final String? collectorNumber;
  final String? imageUrl;
  final double? priceEur;
  final String? createdAt;
  final String? updatedAt;

  const MagicCardModel({
    this.id,
    required this.apiId,
    required this.name,
    this.manaCost,
    this.cmc,
    this.typeLine,
    this.oracleText,
    this.power,
    this.toughness,
    this.colors,
    this.rarity,
    this.setCode,
    this.setName,
    this.collectorNumber,
    this.imageUrl,
    this.priceEur,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    final now = DateTime.now().toIso8601String();
    return {
      if (id != null) 'id': id,
      'api_id': apiId,
      'name': name,
      'mana_cost': manaCost,
      'cmc': cmc,
      'type_line': typeLine,
      'oracle_text': oracleText,
      'power': power,
      'toughness': toughness,
      'colors': colors,
      'rarity': rarity,
      'set_code': setCode,
      'set_name': setName,
      'collector_number': collectorNumber,
      'image_url': imageUrl,
      'price_eur': priceEur,
      'created_at': createdAt ?? now,
      'updated_at': now,
    };
  }

  factory MagicCardModel.fromMap(Map<String, dynamic> map) {
    return MagicCardModel(
      id: map['id'] as int?,
      apiId: map['api_id'] as String,
      name: map['name'] as String,
      manaCost: map['mana_cost'] as String?,
      cmc: (map['cmc'] as num?)?.toDouble(),
      typeLine: map['type_line'] as String?,
      oracleText: map['oracle_text'] as String?,
      power: map['power'] as String?,
      toughness: map['toughness'] as String?,
      colors: map['colors'] as String?,
      rarity: map['rarity'] as String?,
      setCode: map['set_code'] as String?,
      setName: map['set_name'] as String?,
      collectorNumber: map['collector_number'] as String?,
      imageUrl: map['image_url'] as String?,
      priceEur: (map['price_eur'] as num?)?.toDouble(),
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }

  factory MagicCardModel.fromScryfall(Map<String, dynamic> json) {
    // Handle double-faced cards (image in card_faces[0])
    String? imageUrl;
    final imageUris = json['image_uris'] as Map<String, dynamic>?;
    if (imageUris != null) {
      imageUrl = imageUris['normal'] as String?;
    } else {
      final faces = json['card_faces'] as List<dynamic>?;
      if (faces != null && faces.isNotEmpty) {
        final face0 = faces[0] as Map<String, dynamic>?;
        imageUrl = (face0?['image_uris'] as Map<String, dynamic>?)?['normal'] as String?;
      }
    }

    // Colors as comma-separated string
    final colorsRaw = json['colors'] as List<dynamic>? ?? (json['color_identity'] as List<dynamic>? ?? []);
    final colors = colorsRaw.join(',');

    // Prices
    final prices = json['prices'] as Map<String, dynamic>?;
    final priceEur = double.tryParse(prices?['eur']?.toString() ?? '');

    return MagicCardModel(
      apiId: json['id'] as String,
      name: json['name'] as String,
      manaCost: json['mana_cost'] as String?,
      cmc: (json['cmc'] as num?)?.toDouble(),
      typeLine: json['type_line'] as String?,
      oracleText: json['oracle_text'] as String?,
      power: json['power'] as String?,
      toughness: json['toughness'] as String?,
      colors: colors.isEmpty ? null : colors,
      rarity: json['rarity'] as String?,
      setCode: json['set'] as String?,
      setName: json['set_name'] as String?,
      collectorNumber: json['collector_number'] as String?,
      imageUrl: imageUrl,
      priceEur: priceEur,
    );
  }
}
