import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'user_service.dart';

class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final UserService _userService;

  static StreamSubscription<User?>? _authSubscription;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    UserService? userService,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _userService = userService ??
            UserService(firestore: firestore ?? FirebaseFirestore.instance);

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Starts autonomous self-healing listener on active auth sessions.
  void initializeAuthListener() {
    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen((user) async {
      if (user != null) {
        try {
          await syncUserUsername(user);
          await syncExistingUsersToUsernames();
        } catch (e, st) {
          debugPrint('AuthService authStateChanges listener note: $e\n$st');
        }
      }
    });
  }

  /// Self-healing auto-backfill for an individual user:
  /// Reads users/{user.uid}, extracts username (or generates fallback from email prefix),
  /// checks if usernames/{username} exists in Firestore, and creates it if not.
  Future<void> syncUserUsername(User user) async {
    try {
      final userDocRef = _firestore.collection('users').doc(user.uid);
      final userSnapshot = await userDocRef.get();
      final userData = userSnapshot.data();

      final effectiveEmail = (user.email ?? userData?['email'] as String? ?? '').toLowerCase().trim();
      String rawUsername = (userData?['username'] as String?)?.trim() ?? '';

      if (rawUsername.isEmpty) {
        if (effectiveEmail.isNotEmpty && effectiveEmail.contains('@')) {
          rawUsername = effectiveEmail.split('@').first.replaceAll(RegExp(r'[^a-z0-9_]'), '');
        } else {
          final displayName = user.displayName ?? userData?['displayName'] as String? ?? userData?['fullName'] as String?;
          rawUsername = UserModel.generateFallbackUsername(effectiveEmail, displayName);
        }
        if (rawUsername.length < 3) rawUsername = '${rawUsername}_01';
        if (rawUsername.length > 20) rawUsername = rawUsername.substring(0, 20);
      }

      final normalized = UserModel.normalizeUsername(rawUsername);
      if (!UserModel.isValidUsername(normalized)) return;

      final usernameDocRef = _firestore.collection('usernames').doc(normalized);
      final usernameDoc = await usernameDocRef.get();

      if (!usernameDoc.exists) {
        await _firestore.runTransaction((transaction) async {
          final checkDoc = await transaction.get(usernameDocRef);
          if (!checkDoc.exists) {
            transaction.set(usernameDocRef, {
              'uid': user.uid,
              'email': effectiveEmail,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          transaction.set(
            userDocRef,
            {
              'username': normalized,
              'usernameSearch': normalized,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });

        print('Backfilled username: $normalized for UID: ${user.uid}');
        debugPrint('Backfilled username: $normalized for UID: ${user.uid}');
      } else {
        // If username doc exists and belongs to this user, ensure users/{uid} is synced
        final existingUid = usernameDoc.data()?['uid'];
        if (existingUid == user.uid) {
          if (userData?['username'] != normalized || userData?['usernameSearch'] != normalized) {
            await userDocRef.set({
              'username': normalized,
              'usernameSearch': normalized,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            print('Synchronized user doc username: $normalized for UID: ${user.uid}');
            debugPrint('Synchronized user doc username: $normalized for UID: ${user.uid}');
          }
        }
      }
    } catch (e, st) {
      debugPrint('syncUserUsername note (non-fatal): $e\n$st');
      print('syncUserUsername note (non-fatal): $e');
    }
  }

  /// Global Admin / Migration Routine (Self-Check):
  /// Queries `users` collection and ensures every registered user with a valid UID
  /// has an associated `usernames/{normalized_username}` entry.
  Future<int> syncExistingUsersToUsernames() async {
    int backfilledCount = 0;
    try {
      final usersSnapshot = await _firestore.collection('users').get();

      for (final doc in usersSnapshot.docs) {
        final uid = doc.id;
        final data = doc.data();
        final effectiveEmail = (data['email'] as String? ?? '').toLowerCase().trim();
        final displayName = (data['displayName'] ?? data['fullName']) as String?;

        String rawUsername = (data['username'] as String?)?.trim() ?? '';
        if (rawUsername.isEmpty) {
          if (effectiveEmail.isNotEmpty && effectiveEmail.contains('@')) {
            rawUsername = effectiveEmail.split('@').first.replaceAll(RegExp(r'[^a-z0-9_]'), '');
          } else {
            rawUsername = UserModel.generateFallbackUsername(effectiveEmail, displayName);
          }
          if (rawUsername.length < 3) rawUsername = '${rawUsername}_01';
          if (rawUsername.length > 20) rawUsername = rawUsername.substring(0, 20);
        }

        final normalized = UserModel.normalizeUsername(rawUsername);
        if (!UserModel.isValidUsername(normalized)) continue;

        final usernameDocRef = _firestore.collection('usernames').doc(normalized);
        final usernameDoc = await usernameDocRef.get();

        if (!usernameDoc.exists) {
          await _firestore.runTransaction((transaction) async {
            final checkDoc = await transaction.get(usernameDocRef);
            if (!checkDoc.exists) {
              transaction.set(usernameDocRef, {
                'uid': uid,
                'email': effectiveEmail,
                'createdAt': FieldValue.serverTimestamp(),
              });
            }
            transaction.set(
              doc.reference,
              {
                'username': normalized,
                'usernameSearch': normalized,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          });
          backfilledCount++;
          print('Backfilled username: $normalized for UID: $uid');
          debugPrint('Backfilled username: $normalized for UID: $uid');
        } else {
          final existingUid = usernameDoc.data()?['uid'];
          if (existingUid == uid) {
            if (data['username'] != normalized || data['usernameSearch'] != normalized) {
              await doc.reference.set({
                'username': normalized,
                'usernameSearch': normalized,
                'updatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
              print('Synchronized user doc username: $normalized for UID: $uid');
              debugPrint('Synchronized user doc username: $normalized for UID: $uid');
            }
          }
        }
      }
    } catch (e, st) {
      debugPrint('syncExistingUsersToUsernames note (non-fatal): $e\n$st');
      print('syncExistingUsersToUsernames note (non-fatal): $e');
    }
    return backfilledCount;
  }

  /// Registers a new user, creates their profile document in `users/{uid}`,
  /// and attempts non-fatal reservation in the `usernames` collection.
  Future<UserCredential> registerWithEmailAndPassword({
    required String email,
    required String password,
    required String fullName,
    String phone = '',
    String countryCode = '+91',
    String countryName = 'India',
    String currencyCode = 'INR',
    String currencyName = 'Indian Rupee',
    String currencySymbol = '₹',
    String? avatarLocalPath,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      // 1. Update Display Name
      await user.updateDisplayName(fullName.trim());

      // 2. Prepare user profile fields
      final defaultUsername = UserModel.generateFallbackUsername(email, fullName);
      String chosenUsername = defaultUsername;

      // 3. Robust write to users/{user.uid} with SetOptions(merge: true)
      await _firestore.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'fullName': fullName.trim(),
        'displayName': fullName.trim(),
        'email': email.trim().toLowerCase(),
        'phone': phone.trim(),
        'phoneNumber': '$countryCode${phone.trim()}',
        'currency': currencyCode,
        'currencyCode': currencyCode,
        'currencyName': currencyName,
        'currencySymbol': currencySymbol,
        'countryCode': countryCode,
        'countryName': countryName,
        'username': chosenUsername,
        'usernameSearch': chosenUsername.toLowerCase(),
        'avatarLocalPath': avatarLocalPath ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 4. Best-effort atomic username reservation (non-fatal)
      try {
        bool claimed = await _userService.claimUsername(
          newUsername: chosenUsername,
          uid: user.uid,
        );
        if (!claimed) {
          final randomSuffix =
              (DateTime.now().millisecondsSinceEpoch % 1000).toString();
          final trimmedBase = chosenUsername.length > 16
              ? chosenUsername.substring(0, 16)
              : chosenUsername;
          chosenUsername = '${trimmedBase}_$randomSuffix';
          await _userService.claimUsername(
            newUsername: chosenUsername,
            uid: user.uid,
          );
          await _firestore.collection('users').doc(user.uid).set({
            'username': chosenUsername,
            'usernameSearch': chosenUsername.toLowerCase(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (usernameError, usernameStack) {
        debugPrint(
            'AuthService: Username reservation note (non-fatal): $usernameError\n$usernameStack');
        print('AuthService: Username reservation note (non-fatal): $usernameError');
      }
    }

    return credential;
  }

  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (credential.user != null) {
      await syncUserUsername(credential.user!);
      await syncExistingUsersToUsernames();
    }
    return credential;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
