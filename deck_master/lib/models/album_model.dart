class AlbumModel {
  final int? id;
  final String name;
  final String collection; // To associate album with a specific game
  final int maxCapacity;
  final int currentCount;

  AlbumModel({
    this.id,
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
      name: map['name'],
      collection: map['collection'],
      maxCapacity: map['maxCapacity'],
      currentCount: map['currentCount'] ?? 0,
    );
  }
}
