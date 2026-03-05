class OnePieceCard {
  final int? id;
  final String name;
  final String? cardType;
  final String? color;
  final int? cost;
  final int? power;
  final int? life;
  final String? subTypes;
  final int? counterAmount;
  final String? attribute;
  final String? cardText;
  final String? imageUrl;

  const OnePieceCard({
    this.id,
    required this.name,
    this.cardType,
    this.color,
    this.cost,
    this.power,
    this.life,
    this.subTypes,
    this.counterAmount,
    this.attribute,
    this.cardText,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'card_type': cardType,
    'color': color,
    'cost': cost,
    'power': power,
    'life': life,
    'sub_types': subTypes,
    'counter_amount': counterAmount,
    'attribute': attribute,
    'card_text': cardText,
    'image_url': imageUrl,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  factory OnePieceCard.fromMap(Map<String, dynamic> map) => OnePieceCard(
    id: map['id'] as int?,
    name: map['name'] as String? ?? '',
    cardType: map['card_type'] as String?,
    color: map['color'] as String?,
    cost: map['cost'] as int?,
    power: map['power'] as int?,
    life: map['life'] as int?,
    subTypes: map['sub_types'] as String?,
    counterAmount: map['counter_amount'] as int?,
    attribute: map['attribute'] as String?,
    cardText: map['card_text'] as String?,
    imageUrl: map['image_url'] as String?,
  );
}

class OnePiecePrint {
  final int? id;
  final int cardId;
  final String cardSetId;
  final String? setId;
  final String? setName;
  final String? rarity;
  final double? inventoryPrice;
  final double? marketPrice;
  final String? artwork;

  const OnePiecePrint({
    this.id,
    required this.cardId,
    required this.cardSetId,
    this.setId,
    this.setName,
    this.rarity,
    this.inventoryPrice,
    this.marketPrice,
    this.artwork,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'card_id': cardId,
    'card_set_id': cardSetId,
    'set_id': setId,
    'set_name': setName,
    'rarity': rarity,
    'inventory_price': inventoryPrice,
    'market_price': marketPrice,
    'artwork': artwork,
    'created_at': DateTime.now().toIso8601String(),
    'updated_at': DateTime.now().toIso8601String(),
  };

  factory OnePiecePrint.fromMap(Map<String, dynamic> map) => OnePiecePrint(
    id: map['id'] as int?,
    cardId: map['card_id'] as int,
    cardSetId: map['card_set_id'] as String,
    setId: map['set_id'] as String?,
    setName: map['set_name'] as String?,
    rarity: map['rarity'] as String?,
    inventoryPrice: (map['inventory_price'] as num?)?.toDouble(),
    marketPrice: (map['market_price'] as num?)?.toDouble(),
    artwork: map['artwork'] as String?,
  );
}
