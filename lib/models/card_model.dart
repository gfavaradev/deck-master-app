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
  final String? imageUrl; // Added to simplify UI

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
    this.quantity = 1,
    this.value = 0.0,
    this.imageUrl,
  });

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
    };
  }

  factory CardModel.fromMap(Map<String, dynamic> map) {
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
      quantity: map['quantity'] ?? 1,
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      imageUrl: map['imageUrl'],
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
      'value': value,
      'imageUrl': imageUrl,
    };
  }

  factory CardModel.fromFirestore(String docId, Map<String, dynamic> data) {
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
      quantity: data['quantity'] ?? 1,
      value: (data['value'] as num?)?.toDouble() ?? 0.0,
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
    String? imageUrl,
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
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
