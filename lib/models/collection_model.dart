class CollectionModel {
  final String key;
  final String name;
  final bool isUnlocked;

  CollectionModel({
    required this.key,
    required this.name,
    this.isUnlocked = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': key,
      'name': name,
      'isUnlocked': isUnlocked ? 1 : 0,
    };
  }

  factory CollectionModel.fromMap(Map<String, dynamic> map) {
    return CollectionModel(
      key: map['id'],
      name: map['name'],
      isUnlocked: map['isUnlocked'] == 1,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'isUnlocked': isUnlocked,
    };
  }

  factory CollectionModel.fromFirestore(String docId, Map<String, dynamic> data) {
    return CollectionModel(
      key: docId,
      name: data['name'] ?? docId,
      isUnlocked: data['isUnlocked'] ?? false,
    );
  }
}
