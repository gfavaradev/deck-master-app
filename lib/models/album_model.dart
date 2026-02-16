class AlbumModel {
  final int? id;
  final String? firestoreId;
  final String name;
  final String collection; // To associate album with a specific game
  final int maxCapacity;
  final int currentCount;

  AlbumModel({
    this.id,
    this.firestoreId,
    required this.name,
    required this.collection,
    required this.maxCapacity,
    this.currentCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'collection': collection,
      'maxCapacity': maxCapacity,
      // currentCount is not stored in the albums table
    };
  }

  factory AlbumModel.fromMap(Map<String, dynamic> map) {
    return AlbumModel(
      id: map['id'],
      firestoreId: map['firestoreId'],
      name: map['name'],
      collection: map['collection'],
      maxCapacity: map['maxCapacity'],
      currentCount: map['currentCount'] ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'collection': collection,
      'maxCapacity': maxCapacity,
    };
  }

  factory AlbumModel.fromFirestore(String docId, Map<String, dynamic> data) {
    return AlbumModel(
      firestoreId: docId,
      name: data['name'] ?? '',
      collection: data['collection'] ?? '',
      maxCapacity: data['maxCapacity'] ?? 100,
    );
  }

  AlbumModel copyWith({
    int? id,
    String? firestoreId,
    String? name,
    String? collection,
    int? maxCapacity,
    int? currentCount,
  }) {
    return AlbumModel(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      name: name ?? this.name,
      collection: collection ?? this.collection,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      currentCount: currentCount ?? this.currentCount,
    );
  }
}
