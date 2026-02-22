/// Model for tracking pending catalog changes before publishing to Firestore
class PendingCatalogChange {
  final String changeId;
  final ChangeType type;
  final Map<String, dynamic> cardData;
  final int? originalCardId; // For edits/deletes
  final DateTime timestamp;
  final String adminUid;

  PendingCatalogChange({
    required this.changeId,
    required this.type,
    required this.cardData,
    this.originalCardId,
    required this.timestamp,
    required this.adminUid,
  });

  Map<String, dynamic> toMap() {
    return {
      'changeId': changeId,
      'type': type.toString().split('.').last,
      'cardData': cardData,
      'originalCardId': originalCardId,
      'timestamp': timestamp.toIso8601String(),
      'adminUid': adminUid,
    };
  }

  factory PendingCatalogChange.fromMap(Map<String, dynamic> map) {
    return PendingCatalogChange(
      changeId: map['changeId'] as String,
      type: ChangeType.values.firstWhere(
        (e) => e.toString().split('.').last == map['type'],
      ),
      cardData: map['cardData'] as Map<String, dynamic>,
      originalCardId: map['originalCardId'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
      adminUid: map['adminUid'] as String,
    );
  }
}

enum ChangeType {
  add,    // New card
  edit,   // Modify existing card
  delete, // Remove card
}
