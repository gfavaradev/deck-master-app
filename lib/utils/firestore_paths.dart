import '../constants/app_constants.dart';

/// Centralized Firestore path builders
/// This ensures consistency and prevents typos in collection paths
class FirestorePaths {
  /// Get catalog collection path
  static String catalog(String catalogName) {
    return CatalogConstants.getCollectionName(catalogName);
  }

  /// Get catalog metadata document path
  static String catalogMetadata(String catalogName) {
    return '${catalog(catalogName)}/${FirestoreConstants.catalogMetadata}';
  }

  /// Get catalog chunks collection path
  static String catalogChunks(String catalogName) {
    return '${catalog(catalogName)}/${FirestoreConstants.catalogChunks}/${FirestoreConstants.catalogItems}';
  }

  /// Get specific chunk document path
  static String catalogChunk(String catalogName, int chunkIndex) {
    return '${catalogChunks(catalogName)}/${FirestoreConstants.getChunkId(chunkIndex)}';
  }

  /// Get user document path
  static String user(String userId) {
    return '${FirestoreConstants.users}/$userId';
  }

  /// Get user collections path
  static String userCollections(String userId) {
    return '${user(userId)}/${FirestoreConstants.collections}';
  }

  /// Get specific user collection path
  static String userCollection(String userId, String collectionKey) {
    return '${userCollections(userId)}/$collectionKey';
  }

  /// Get user albums path
  static String userAlbums(String userId) {
    return '${user(userId)}/${FirestoreConstants.albums}';
  }

  /// Get specific user album path
  static String userAlbum(String userId, String albumId) {
    return '${userAlbums(userId)}/$albumId';
  }

  /// Get user cards path
  static String userCards(String userId) {
    return '${user(userId)}/${FirestoreConstants.cards}';
  }

  /// Get specific user card path
  static String userCard(String userId, String cardId) {
    return '${userCards(userId)}/$cardId';
  }

  /// Get user decks path
  static String userDecks(String userId) {
    return '${user(userId)}/${FirestoreConstants.decks}';
  }

  /// Get specific user deck path
  static String userDeck(String userId, String deckId) {
    return '${userDecks(userId)}/$deckId';
  }
}
