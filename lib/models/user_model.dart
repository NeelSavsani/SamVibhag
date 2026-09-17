import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final String fullName;
  final String username;
  final String usernameSearch;
  final String phoneNumber;
  final String countryCode;
  final String countryName;
  final String currencyName;
  final String currencyCode;
  final String currencySymbol;
  final String timezone;
  final String language;
  final String avatarLocalPath;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastActive;

  const UserModel({
    required this.uid,
    required this.email,
    this.displayName = '',
    this.fullName = '',
    this.username = '',
    this.usernameSearch = '',
    this.phoneNumber = '',
    this.countryCode = '+91',
    this.countryName = 'India',
    this.currencyName = 'Indian Rupee',
    this.currencyCode = 'INR',
    this.currencySymbol = '₹',
    this.timezone = 'Asia/Kolkata (GMT+5:30)',
    this.language = 'English (EN)',
    this.avatarLocalPath = '',
    this.createdAt,
    this.updatedAt,
    this.lastActive,
  });

  /// Helper to sanitize and normalize a username string
  static String normalizeUsername(String raw) {
    return raw.trim().toLowerCase().replaceFirst(RegExp(r'^@+'), '').trim();
  }

  /// Helper to create a fallback username from an email or name
  static String generateFallbackUsername(String? email, String? name) {
    if (email != null && email.isNotEmpty && email.contains('@')) {
      final prefix = email.split('@').first.toLowerCase();
      final sanitized = prefix.replaceAll(RegExp(r'[^a-z0-9_]'), '_');
      if (sanitized.isNotEmpty) return sanitized;
    }
    if (name != null && name.isNotEmpty) {
      final sanitized = name.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
      if (sanitized.isNotEmpty) return sanitized;
    }
    return 'user_${DateTime.now().millisecondsSinceEpoch % 10000}';
  }

  factory UserModel.fromMap(Map<String, dynamic> map, {String? docId}) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final rawUsername = (map['username'] as String?)?.trim().toLowerCase() ?? '';
    final rawSearch = (map['usernameSearch'] as String?)?.trim().toLowerCase() ?? '';
    final username = rawUsername.isNotEmpty ? rawUsername : rawSearch;

    return UserModel(
      uid: (map['uid'] as String?) ?? docId ?? '',
      email: (map['email'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? (map['fullName'] as String?) ?? '',
      fullName: (map['fullName'] as String?) ?? (map['displayName'] as String?) ?? '',
      username: username,
      usernameSearch: rawSearch.isNotEmpty ? rawSearch : username,
      phoneNumber: (map['phoneNumber'] as String?) ?? '',
      countryCode: (map['countryCode'] as String?) ?? '+91',
      countryName: (map['countryName'] as String?) ?? 'India',
      currencyName: (map['currencyName'] as String?) ?? 'Indian Rupee',
      currencyCode: (map['currencyCode'] as String?) ?? 'INR',
      currencySymbol: (map['currencySymbol'] as String?) ?? '₹',
      timezone: (map['timezone'] as String?) ?? 'Asia/Kolkata (GMT+5:30)',
      language: (map['language'] as String?) ?? 'English (EN)',
      avatarLocalPath: (map['avatarLocalPath'] as String?) ?? '',
      createdAt: parseDate(map['createdAt']),
      updatedAt: parseDate(map['updatedAt']),
      lastActive: parseDate(map['lastActive']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'fullName': fullName,
      'username': username,
      'usernameSearch': usernameSearch.isNotEmpty ? usernameSearch : username.toLowerCase(),
      'phoneNumber': phoneNumber,
      'countryCode': countryCode,
      'countryName': countryName,
      'currencyName': currencyName,
      'currencyCode': currencyCode,
      'currencySymbol': currencySymbol,
      'timezone': timezone,
      'language': language,
      'avatarLocalPath': avatarLocalPath,
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt,
      if (lastActive != null) 'lastActive': lastActive,
    };
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? displayName,
    String? fullName,
    String? username,
    String? usernameSearch,
    String? phoneNumber,
    String? countryCode,
    String? countryName,
    String? currencyName,
    String? currencyCode,
    String? currencySymbol,
    String? timezone,
    String? language,
    String? avatarLocalPath,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastActive,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      usernameSearch: usernameSearch ?? this.usernameSearch,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      currencyName: currencyName ?? this.currencyName,
      currencyCode: currencyCode ?? this.currencyCode,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      timezone: timezone ?? this.timezone,
      language: language ?? this.language,
      avatarLocalPath: avatarLocalPath ?? this.avatarLocalPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastActive: lastActive ?? this.lastActive,
    );
  }
}
