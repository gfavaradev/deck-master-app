import 'subscription_model.dart';

/// User model with role-based access control
class UserModel {
  final String uid;
  final String email;
  final String? displayName;
  final String? photoUrl;
  final UserRole role;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final bool isActive;

  // ── Pro subscription ──────────────────────────────────────────────────────
  final bool isPro;
  final String? proSource;     // 'iap' | 'manual'
  final DateTime? proExpiresAt; // null = nessuna scadenza (manual)

  // ── Donazioni ─────────────────────────────────────────────────────────────
  final double totalDonated;
  final DonationTier donationTier;
  final String? wallOfFameNickname; // solo per secretRare

  UserModel({
    required this.uid,
    required this.email,
    this.displayName,
    this.photoUrl,
    this.role = UserRole.user,
    required this.createdAt,
    this.lastLoginAt,
    this.isActive = true,
    this.isPro = false,
    this.proSource,
    this.proExpiresAt,
    this.totalDonated = 0.0,
    this.donationTier = DonationTier.none,
    this.wallOfFameNickname,
  });

  /// Check if user is administrator
  bool get isAdmin => role == UserRole.administrator;

  /// Check if user is regular user
  bool get isUser => role == UserRole.user;

  /// Pro attivo (admin ha sempre accesso Pro)
  bool get hasProAccess {
    if (isAdmin) return true;
    if (!isPro) return false;
    if (proExpiresAt == null) return true;
    return proExpiresAt!.isAfter(DateTime.now());
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'role': role.toString().split('.').last,
      'createdAt': createdAt.toIso8601String(),
      'lastLoginAt': lastLoginAt?.toIso8601String(),
      'isActive': isActive,
      'isPro': isPro,
      'proSource': proSource,
      'proExpiresAt': proExpiresAt?.toIso8601String(),
      'totalDonated': totalDonated,
      'donationTier': donationTier.name,
      'wallOfFameNickname': wallOfFameNickname,
    };
  }

  /// Create from Firestore document
  factory UserModel.fromFirestore(Map<String, dynamic> data) {
    return UserModel(
      uid: data['uid'] as String,
      email: data['email'] as String,
      displayName: data['displayName'] as String?,
      photoUrl: data['photoUrl'] as String?,
      role: UserRole.values.firstWhere(
        (e) => e.toString().split('.').last == data['role'],
        orElse: () => UserRole.user,
      ),
      createdAt: DateTime.parse(data['createdAt'] as String),
      lastLoginAt: data['lastLoginAt'] != null
          ? DateTime.parse(data['lastLoginAt'] as String)
          : null,
      isActive: data['isActive'] as bool? ?? true,
      isPro: data['isPro'] as bool? ?? false,
      proSource: data['proSource'] as String?,
      proExpiresAt: data['proExpiresAt'] != null
          ? DateTime.tryParse(data['proExpiresAt'] as String)
          : null,
      totalDonated: (data['totalDonated'] as num?)?.toDouble() ?? 0.0,
      donationTier: DonationTier.fromString(data['donationTier'] as String?),
      wallOfFameNickname: data['wallOfFameNickname'] as String?,
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? photoUrl,
    UserRole? role,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    bool? isActive,
    bool? isPro,
    String? proSource,
    DateTime? proExpiresAt,
    double? totalDonated,
    DonationTier? donationTier,
    String? wallOfFameNickname,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      isActive: isActive ?? this.isActive,
      isPro: isPro ?? this.isPro,
      proSource: proSource ?? this.proSource,
      proExpiresAt: proExpiresAt ?? this.proExpiresAt,
      totalDonated: totalDonated ?? this.totalDonated,
      donationTier: donationTier ?? this.donationTier,
      wallOfFameNickname: wallOfFameNickname ?? this.wallOfFameNickname,
    );
  }
}

/// User roles enum
enum UserRole {
  /// Administrator - full access to all features
  administrator,

  /// Regular user - limited access
  user,
}
