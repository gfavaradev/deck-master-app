import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:deck_master/models/user_model.dart';

/// Service for managing user data and roles in Firestore
class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Admin email - automatically gets administrator role
  static const String _adminEmail = 'g.favara.dev@gmail.com';

  /// Collection reference for users
  CollectionReference get _usersCollection => _firestore.collection('users');

  /// Get current user's UID
  String? get currentUserId => _auth.currentUser?.uid;

  /// Check if email should have admin role
  bool _isAdminEmail(String email) {
    return email.toLowerCase() == _adminEmail.toLowerCase();
  }

  /// Create a new user document in Firestore
  Future<void> createUser({
    required String uid,
    required String email,
    String? displayName,
    String? photoUrl,
    UserRole role = UserRole.user,
  }) async {
    // Automatically assign admin role to configured email
    final finalRole = _isAdminEmail(email) ? UserRole.administrator : role;

    final user = UserModel(
      uid: uid,
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      role: finalRole,
      createdAt: DateTime.now(),
      lastLoginAt: DateTime.now(),
    );

    await _usersCollection.doc(uid).set(user.toFirestore());
  }

  /// Get user by UID
  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _usersCollection.doc(uid).get();
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data() as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  /// Get current logged-in user
  Future<UserModel?> getCurrentUser() async {
    if (currentUserId == null) return null;
    return getUser(currentUserId!);
  }

  /// Update user's last login timestamp
  Future<void> updateLastLogin(String uid) async {
    await _usersCollection.doc(uid).update({
      'lastLoginAt': DateTime.now().toIso8601String(),
    });
  }

  /// Update user role (admin only operation)
  Future<void> updateUserRole(String uid, UserRole newRole) async {
    await _usersCollection.doc(uid).update({
      'role': newRole.toString().split('.').last,
    });
  }

  /// Check if current user is administrator
  Future<bool> isCurrentUserAdmin() async {
    final user = await getCurrentUser();
    return user?.isAdmin ?? false;
  }

  /// Check if user with given UID is administrator
  Future<bool> isUserAdmin(String uid) async {
    final user = await getUser(uid);
    return user?.isAdmin ?? false;
  }

  /// Get all users (admin only)
  Future<List<UserModel>> getAllUsers() async {
    final snapshot = await _usersCollection.get();
    return snapshot.docs
        .map((doc) => UserModel.fromFirestore(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Get users by role
  Future<List<UserModel>> getUsersByRole(UserRole role) async {
    final roleString = role.toString().split('.').last;
    final snapshot = await _usersCollection
        .where('role', isEqualTo: roleString)
        .get();
    return snapshot.docs
        .map((doc) => UserModel.fromFirestore(doc.data() as Map<String, dynamic>))
        .toList();
  }

  /// Activate/deactivate user account (admin only)
  Future<void> setUserActiveStatus(String uid, bool isActive) async {
    await _usersCollection.doc(uid).update({
      'isActive': isActive,
    });
  }

  /// Check if user exists in Firestore
  Future<bool> userExists(String uid) async {
    final doc = await _usersCollection.doc(uid).get();
    return doc.exists;
  }

  /// Update user profile
  Future<void> updateUserProfile({
    required String uid,
    String? displayName,
    String? photoUrl,
  }) async {
    final Map<String, dynamic> updates = {};
    if (displayName != null) updates['displayName'] = displayName;
    if (photoUrl != null) updates['photoUrl'] = photoUrl;

    if (updates.isNotEmpty) {
      await _usersCollection.doc(uid).update(updates);
    }
  }

  /// Stream of current user data
  Stream<UserModel?> currentUserStream() {
    if (currentUserId == null) {
      return Stream<UserModel?>.empty();
    }
    return _usersCollection.doc(currentUserId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return UserModel.fromFirestore(doc.data() as Map<String, dynamic>);
    });
  }

  /// Delete user document (admin only, be careful!)
  Future<void> deleteUser(String uid) async {
    await _usersCollection.doc(uid).delete();
  }
}
