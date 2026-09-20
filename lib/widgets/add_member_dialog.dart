import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/group_activity_model.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/activity_service.dart';
import '../services/user_service.dart';

class AddedMemberResult {
  final String displayName;
  final String? uid;
  final String? email;
  final String? username;
  final bool isOffline;

  const AddedMemberResult({
    required this.displayName,
    this.uid,
    this.email,
    this.username,
    this.isOffline = false,
  });
}

class AddMemberDialog extends StatefulWidget {
  final GroupModel group;

  const AddMemberDialog({super.key, required this.group});

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();

  bool _isSearching = false;
  bool _isAdding = false;
  bool _hasSearched = false;
  String _lastSearchedQuery = '';
  Map<String, dynamic>? _foundUser;
  String? _errorMessage;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final input = _searchController.text.trim();
    if (input.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _lastSearchedQuery = input;
      _foundUser = null;
      _errorMessage = null;
    });

    try {
      final cleanInput = input.replaceAll('@', '').trim().toLowerCase();
      final bool looksLikeEmail = input.contains('@') && input.contains('.');
      Map<String, dynamic>? matchedUser;

      if (looksLikeEmail || cleanInput.contains('.')) {
        // Query by email
        final emailQuery = looksLikeEmail ? input.trim().toLowerCase() : cleanInput;
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: emailQuery)
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          matchedUser = Map<String, dynamic>.from(snap.docs.first.data());
          matchedUser['uid'] = (matchedUser['uid'] as String?) ?? snap.docs.first.id;
        }
      }

      // If email query didn't return a match, search by username
      if (matchedUser == null && cleanInput.isNotEmpty) {
        matchedUser = await _userService.getUserByUsername(cleanInput);

        if (matchedUser == null) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .where('usernameSearch', isEqualTo: cleanInput)
              .limit(1)
              .get();

          if (snap.docs.isNotEmpty) {
            matchedUser = Map<String, dynamic>.from(snap.docs.first.data());
            matchedUser['uid'] = (matchedUser['uid'] as String?) ?? snap.docs.first.id;
          }
        }
      }

      // Secondary fallback if input contained an @ and username query didn't find anything
      if (matchedUser == null && input.contains('@')) {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: input.trim().toLowerCase())
            .limit(1)
            .get();

        if (snap.docs.isNotEmpty) {
          matchedUser = Map<String, dynamic>.from(snap.docs.first.data());
          matchedUser['uid'] = (matchedUser['uid'] as String?) ?? snap.docs.first.id;
        }
      }

      if (mounted) {
        setState(() {
          _foundUser = matchedUser;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Search failed: $e";
          _isSearching = false;
        });
      }
    }
  }

  bool _isUserAlreadyMember(Map<String, dynamic> user) {
    final uid = (user['uid'] as String?) ?? '';
    final email = (user['email'] as String? ?? '').toLowerCase().trim();
    final displayName = (user['displayName'] as String?) ?? (user['fullName'] as String?) ?? '';
    final username = (user['username'] as String?)?.toLowerCase().trim() ??
        (user['usernameSearch'] as String?)?.toLowerCase().trim();

    if (uid.isNotEmpty && widget.group.memberUids.contains(uid)) return true;
    if (email.isNotEmpty && widget.group.memberEmails.map((e) => e.toLowerCase()).contains(email)) return true;
    if (displayName.isNotEmpty && widget.group.members.map((m) => m.toLowerCase()).contains(displayName.toLowerCase())) return true;
    if (username != null && username.isNotEmpty && widget.group.memberUsernames.map((u) => u.toLowerCase()).contains(username)) return true;

    return false;
  }

  bool _isOfflineNameAlreadyMember(String name) {
    return widget.group.members.any((m) => m.trim().toLowerCase() == name.trim().toLowerCase());
  }

  Future<void> _confirmAddMember({
    required String displayName,
    String? uid,
    String? email,
    String? username,
    bool isOffline = false,
  }) async {
    setState(() => _isAdding = true);

    try {
      final updates = <String, dynamic>{
        'members': FieldValue.arrayUnion([displayName]),
      };

      if (email != null && email.trim().isNotEmpty) {
        updates['memberEmails'] = FieldValue.arrayUnion([email.trim().toLowerCase()]);
      }
      if (uid != null && uid.trim().isNotEmpty) {
        updates['memberUids'] = FieldValue.arrayUnion([uid.trim()]);
      }
      if (username != null && username.trim().isNotEmpty) {
        updates['memberUsernames'] = FieldValue.arrayUnion([UserModel.normalizeUsername(username)]);
      }

      // 1. Atomic Firestore mutation
      await FirebaseFirestore.instance.collection('groups').doc(widget.group.id).update(updates);

      // 2. Activity history logging
      final currentUser = FirebaseAuth.instance.currentUser;
      final performerName = (currentUser?.displayName != null && currentUser!.displayName!.trim().isNotEmpty)
          ? currentUser.displayName!.trim()
          : (currentUser?.email != null && currentUser!.email!.isNotEmpty
              ? currentUser.email!.split('@').first
              : 'Admin');

      await ActivityService.instance.logGroupActivity(
        groupId: widget.group.id,
        type: GroupActivity.typeMemberAdded,
        message: '$performerName added $displayName to the group',
        performedByUid: currentUser?.uid,
        performedByName: performerName,
        metadata: {
          'newMember': displayName,
          if (uid != null && uid.isNotEmpty) 'newMemberUid': uid,
          if (email != null && email.isNotEmpty) 'newMemberEmail': email,
          if (username != null && username.isNotEmpty) 'newMemberUsername': username,
          'isOffline': isOffline,
        },
      );

      if (!mounted) return;

      final result = AddedMemberResult(
        displayName: displayName,
        uid: uid,
        email: email,
        username: username,
        isOffline: isOffline,
      );

      Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        setState(() => _isAdding = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to add member: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cleanQuery = _lastSearchedQuery.replaceAll('@', '').trim();
    final offlineFallbackName = _lastSearchedQuery.startsWith('@')
        ? _lastSearchedQuery.substring(1).trim()
        : _lastSearchedQuery.trim();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: theme.scaffoldBackgroundColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.person_add_rounded, color: Color(0xFF0284C7), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Add Group Member",
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          "Search by @username or email address",
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    tooltip: "Close",
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Search Input Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: GoogleFonts.poppins(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "e.g. @neel_07 or friend@email.com",
                        hintStyle: GoogleFonts.poppins(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                        prefixIcon: const Icon(
                          Icons.alternate_email_rounded,
                          color: Color(0xFF0284C7),
                          size: 20,
                        ),
                        filled: true,
                        fillColor: theme.cardColor,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF0284C7),
                            width: 1.8,
                          ),
                        ),
                      ),
                      onFieldSubmitted: (_) => _performSearch(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 50,
                    width: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                      ),
                    ),
                    child: IconButton(
                      onPressed: _isSearching || _isAdding ? null : _performSearch,
                      icon: _isSearching
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                ],
              ),

              // Error Message
              if (_errorMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _errorMessage!,
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.redAccent),
                ),
              ],

              // Results / Status Area
              const SizedBox(height: 18),

              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Searching directory...",
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_hasSearched && _foundUser != null) ...[
                // MATCHED USER PREVIEW CARD
                Builder(
                  builder: (context) {
                    final user = _foundUser!;
                    final uid = (user['uid'] as String?) ?? '';
                    final email = (user['email'] as String? ?? '').trim();
                    final displayName = (user['displayName'] as String?) ??
                        (user['fullName'] as String?) ??
                        'User';
                    final username = (user['username'] as String?)?.trim() ??
                        (user['usernameSearch'] as String?)?.trim();
                    final avatarUrl = (user['photoUrl'] as String?) ?? (user['avatarPath'] as String?);
                    final isAlreadyMember = _isUserAlreadyMember(user);

                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isAlreadyMember
                              ? Colors.amber.withValues(alpha: 0.4)
                              : const Color(0xFF0284C7).withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                backgroundImage: (avatarUrl != null && avatarUrl.startsWith('http'))
                                    ? NetworkImage(avatarUrl)
                                    : null,
                                child: (avatarUrl == null || !avatarUrl.startsWith('http'))
                                    ? Text(
                                        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                                        style: GoogleFonts.poppins(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 18,
                                          color: const Color(0xFF0284C7),
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayName,
                                      style: GoogleFonts.poppins(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    if (username != null && username.isNotEmpty)
                                      Text(
                                        "@$username",
                                        style: GoogleFonts.poppins(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: const Color(0xFF0284C7),
                                        ),
                                      ),
                                    if (email.isNotEmpty)
                                      Text(
                                        email,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (isAlreadyMember)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Already a member of this group",
                                    style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.amber[300] : Colors.amber[800],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _isAdding
                                    ? null
                                    : () => _confirmAddMember(
                                          displayName: displayName,
                                          uid: uid,
                                          email: email,
                                          username: username,
                                          isOffline: false,
                                        ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: _isAdding
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                                label: Text(
                                  _isAdding ? "Adding..." : "Add to Group",
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ] else if (_hasSearched && _foundUser == null) ...[
                // NOT FOUND NOTICE & OFFLINE MEMBER FALLBACK
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.person_off_rounded,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              cleanQuery.isNotEmpty
                                  ? "No user found with @$cleanQuery"
                                  : "No registered user found.",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        "You can still add them as an offline member so expenses and splits can be tracked together.",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_isOfflineNameAlreadyMember(offlineFallbackName))
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              "\"$offlineFallbackName\" is already in this group",
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.amber[300] : Colors.amber[800],
                              ),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _isAdding
                                ? null
                                : () => _confirmAddMember(
                                      displayName: offlineFallbackName,
                                      isOffline: true,
                                    ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Color(0xFF0284C7)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: _isAdding
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF0284C7),
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.person_add_outlined, color: Color(0xFF0284C7)),
                            label: Text(
                              _isAdding
                                  ? "Adding..."
                                  : "Add \"$offlineFallbackName\" as offline member",
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: const Color(0xFF0284C7),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
