class WishlistModel {
  final int? id;
  final String catalogId;
  final String name;
  final String collection;
  final String? imageUrl;
  final String? serialNumber;
  final String? rarity;
  final double? targetPrice;
  final String addedAt;
  // Enriched at query time from cardtrader_prices — not persisted
  final double? cardtraderValue;

  WishlistModel({
    this.id,
    required this.catalogId,
    required this.name,
    required this.collection,
    this.imageUrl,
    this.serialNumber,
    this.rarity,
    this.targetPrice,
    required this.addedAt,
    this.cardtraderValue,
  });

  Map<String, dynamic> toMap() => {
        'catalogId': catalogId,
        'name': name,
        'collection': collection,
        'imageUrl': imageUrl,
        'serialNumber': serialNumber,
        'rarity': rarity,
        'target_price': targetPrice,
        'added_at': addedAt,
      };

  factory WishlistModel.fromMap(Map<String, dynamic> map) => WishlistModel(
        id: map['id'] as int?,
        catalogId: map['catalogId'] as String? ?? '',
        name: map['name'] as String? ?? '',
        collection: map['collection'] as String? ?? '',
        imageUrl: map['imageUrl'] as String?,
        serialNumber: map['serialNumber'] as String?,
        rarity: map['rarity'] as String?,
        targetPrice: (map['target_price'] as num?)?.toDouble(),
        addedAt: map['added_at'] as String? ?? '',
        cardtraderValue: (map['cardtrader_value'] as num?)?.toDouble(),
      );

  WishlistModel copyWith({double? cardtraderValue}) => WishlistModel(
        id: id,
        catalogId: catalogId,
        name: name,
        collection: collection,
        imageUrl: imageUrl,
        serialNumber: serialNumber,
        rarity: rarity,
        targetPrice: targetPrice,
        addedAt: addedAt,
        cardtraderValue: cardtraderValue ?? this.cardtraderValue,
      );
}
