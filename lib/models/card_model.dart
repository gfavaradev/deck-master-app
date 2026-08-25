import 'dart:math' as math;

class CardModel {
  final int? id;
  final String? firestoreId;
  final String? catalogId; // Reference to catalog_cards.id
  final String name;
  final String serialNumber;
  final String collection;
  final int albumId;
  final String type;
  final String rarity;
  final String description;
  final int quantity;
  final double value;
  final double? cardtraderValue;
  final String? imageUrl; // Added to simplify UI
  final String? cardtraderSyncedAt;
  final int? cardtraderListingCount;
  final double? purchasePrice;

  CardModel({
    this.id,
    this.firestoreId,
    this.catalogId,
    required this.name,
    required this.serialNumber,
    required this.collection,
    required this.albumId,
    required this.type,
    required this.rarity,
    required this.description,
    int quantity = 1,
    double value = 0.0,
    double? cardtraderValue,
    this.imageUrl,
    this.cardtraderSyncedAt,
    this.cardtraderListingCount,
    double? purchasePrice,
  })  : quantity = quantity < 0 ? 0 : quantity,
        value = value < 0 ? 0.0 : value,
        cardtraderValue = (cardtraderValue != null && cardtraderValue < 0) ? 0.0 : cardtraderValue,
        purchasePrice = (purchasePrice != null && purchasePrice < 0) ? 0.0 : purchasePrice;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'catalogId': catalogId,
      'name': name,
      'type': type,
      'description': description,
      'collection': collection,
      'imageUrl': imageUrl,
      'serialNumber': serialNumber,
      'albumId': albumId,
      'rarity': rarity,
      'quantity': quantity,
      'value': value,
      'cardtrader_value': cardtraderValue,
      'purchase_price': purchasePrice,
      // added_at is intentionally excluded: set once at insert time and
      // must not be overwritten by subsequent updateCard() calls.
    };
  }

  factory CardModel.fromMap(Map<String, dynamic> map) {
    final rawQty = (map['quantity'] as num?)?.toInt() ?? 1;
    final rawVal = (map['value'] as num?)?.toDouble() ?? 0.0;
    final rawCtVal = (map['cardtrader_value'] as num?)?.toDouble();
    final rawPurch = (map['purchase_price'] as num?)?.toDouble();

    return CardModel(
      id: map['id'],
      firestoreId: map['firestoreId'],
      catalogId: map['catalogId'],
      name: map['name'] ?? '',
      serialNumber: map['serialNumber'] ?? '',
      collection: map['collection'] ?? '',
      albumId: map['albumId'] ?? -1,
      type: map['type'] ?? '',
      rarity: map['rarity'] ?? '',
      description: map['description'] ?? '',
      quantity: rawQty < 0 ? 0 : rawQty,
      value: math.max(0.0, rawVal),
      cardtraderValue: rawCtVal != null ? math.max(0.0, rawCtVal) : null,
      imageUrl: map['imageUrl'],
      cardtraderSyncedAt: map['ct_synced_at'] as String?,
      cardtraderListingCount: map['ct_listing_count'] as int?,
      purchasePrice: rawPurch != null ? math.max(0.0, rawPurch) : null,
    );
  }

  Map<String, dynamic> toFirestore({String? albumFirestoreId}) {
    return {
      'catalogId': catalogId,
      'name': name,
      'serialNumber': serialNumber,
      'collection': collection,
      'albumId': albumId,
      'albumFirestoreId': albumFirestoreId,
      'type': type,
      'rarity': rarity,
      'description': description,
      'quantity': quantity,
      'cardtraderValue': cardtraderValue,
      'imageUrl': imageUrl,
    };
  }

  factory CardModel.fromFirestore(String docId, Map<String, dynamic> data) {
    final rawQty = (data['quantity'] as num?)?.toInt() ?? 1;
    final rawVal = (data['value'] as num?)?.toDouble() ?? 0.0;
    final rawCtVal = (data['cardtraderValue'] as num?)?.toDouble();

    return CardModel(
      firestoreId: docId,
      catalogId: data['catalogId'],
      name: data['name'] ?? '',
      serialNumber: data['serialNumber'] ?? '',
      collection: data['collection'] ?? '',
      albumId: data['albumId'] ?? -1,
      type: data['type'] ?? '',
      rarity: data['rarity'] ?? '',
      description: data['description'] ?? '',
      quantity: rawQty < 0 ? 0 : rawQty,
      value: math.max(0.0, rawVal),
      cardtraderValue: rawCtVal != null ? math.max(0.0, rawCtVal) : null,
      imageUrl: data['imageUrl'],
    );
  }

  CardModel copyWith({
    int? id,
    String? firestoreId,
    String? catalogId,
    String? name,
    String? serialNumber,
    String? collection,
    int? albumId,
    String? type,
    String? rarity,
    String? description,
    int? quantity,
    double? value,
    double? cardtraderValue,
    String? imageUrl,
    String? cardtraderSyncedAt,
    int? cardtraderListingCount,
    double? purchasePrice,
    bool resetId = false,
  }) {
    return CardModel(
      id: resetId ? null : (id ?? this.id),
      firestoreId: resetId ? null : (firestoreId ?? this.firestoreId),
      catalogId: catalogId ?? this.catalogId,
      name: name ?? this.name,
      serialNumber: serialNumber ?? this.serialNumber,
      collection: collection ?? this.collection,
      albumId: albumId ?? this.albumId,
      type: type ?? this.type,
      rarity: rarity ?? this.rarity,
      description: description ?? this.description,
      quantity: quantity ?? this.quantity,
      value: value ?? this.value,
      cardtraderValue: cardtraderValue ?? this.cardtraderValue,
      imageUrl: imageUrl ?? this.imageUrl,
      cardtraderSyncedAt: cardtraderSyncedAt ?? this.cardtraderSyncedAt,
      cardtraderListingCount: cardtraderListingCount ?? this.cardtraderListingCount,
      purchasePrice: purchasePrice ?? this.purchasePrice,
    );
  }
}
