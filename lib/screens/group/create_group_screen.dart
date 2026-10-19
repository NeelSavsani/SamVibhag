import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_theme.dart';
import '../../models/group_model.dart';
import '../../models/group_activity_model.dart';
import '../../services/activity_service.dart';
import '../../services/fcm_sender_service.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _memberInputController = TextEditingController();

  File? _selectedImage;
  bool _isLoading = false;
  bool _isSearchingUser = false;

  // Track members: display names, uids, emails, usernames
  final List<String> _members = [];
  final List<String> _memberUids = [];
  final List<String> _memberEmails = [];
  final List<String> _memberUsernames = [];

  User? get _currentUser => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    // Seed creator as initial member
    if (_currentUser != null) {
      final name = _currentUser!.displayName?.trim().isNotEmpty == true
          ? _currentUser!.displayName!
          : (_currentUser!.email?.split('@').first ?? 'You');
      _members.add(name);
      _memberUids.add(_currentUser!.uid);
      if (_currentUser!.email != null) _memberEmails.add(_currentUser!.email!.toLowerCase());
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _memberInputController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _searchAndAddMember() async {
    final rawInput = _memberInputController.text.trim();
    if (rawInput.isEmpty) return;

    final cleanInput = rawInput.replaceAll('@', '').toLowerCase();
    setState(() => _isSearchingUser = true);

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      if (cleanInput.contains('.')) {
        // Search by email
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: cleanInput)
            .limit(1)
            .get();
      } else {
        // Search by username
        snapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('usernameSearch', isEqualTo: cleanInput)
            .limit(1)
            .get();
      }

      if (!mounted) return;

      if (snapshot.docs.isNotEmpty) {
        final userData = snapshot.docs.first.data();
        final uid = snapshot.docs.first.id;
        final name = (userData['displayName'] as String?)?.trim().isNotEmpty == true
            ? userData['displayName'] as String
            : (userData['username'] ?? cleanInput);
        final email = (userData['email'] as String?)?.toLowerCase() ?? '';
        final username = userData['username'] as String? ?? cleanInput;

        if (_memberUids.contains(uid)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('@$username is already added.')),
          );
          return;
        }

        setState(() {
          _members.add(name);
          _memberUids.add(uid);
          if (email.isNotEmpty) _memberEmails.add(email);
          _memberUsernames.add(username);
          _memberInputController.clear();
        });
      } else {
        // Fallback option to add as offline member
        final addOffline = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("User Not Found"),
            content: Text(
              "No registered user found for '$rawInput'. Would you like to add them as an offline member?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("Add Offline"),
              ),
            ],
          ),
        );

        if (addOffline == true && mounted) {
          setState(() {
            _members.add(rawInput);
            _memberInputController.clear();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingUser = false);
    }
  }

  void _removeMember(int index) {
    if (index == 0 && _memberUids.contains(_currentUser?.uid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You cannot remove yourself from the group.")),
      );
      return;
    }
    setState(() {
      final name = _members.removeAt(index);
      if (index < _memberUids.length) _memberUids.removeAt(index);
      if (index < _memberEmails.length) _memberEmails.removeAt(index);
      if (index < _memberUsernames.length) _memberUsernames.removeAt(index);
    });
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;
    if (_members.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one other member.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final groupDoc = FirebaseFirestore.instance.collection('groups').doc();
      final currentUserName = _currentUser?.displayName?.trim().isNotEmpty == true
          ? _currentUser!.displayName!
          : (_currentUser?.email?.split('@').first ?? 'Admin');

      final groupName = _nameController.text.trim();

      final groupData = {
        'id': groupDoc.id,
        'name': groupName,
        'description': _descController.text.trim(),
        'avatarPath': _selectedImage?.path ?? '',
        'members': _members,
        'memberUids': _memberUids,
        'memberEmails': _memberEmails,
        'memberUsernames': _memberUsernames,
        'createdBy': _currentUser?.uid ?? '',
        'lastUpdatedBy': _currentUser?.uid ?? '',
        'lastUpdatedByName': currentUserName,
        'expenses': [],
        'recordedSettlements': [],
        'createdAt': FieldValue.serverTimestamp(),
      };

      await groupDoc.set(groupData);

      // Log Group Created Activity
      await ActivityService.instance.logGroupActivity(
        groupId: groupDoc.id,
        type: GroupActivity.typeGroupCreated,
        message: '$currentUserName created group "$groupName"',
        metadata: {
          'initialMembers': _members,
          'groupType': _descController.text.trim().isNotEmpty ? _descController.text.trim() : 'General',
        },
      );

      // Free Spark Tier: Dispatch FCM notifications directly to other members via FCM HTTP v1
      final recipientUids = _memberUids.where((id) => id != _currentUser?.uid).toList();

      if (recipientUids.isNotEmpty) {
        try {
          final usersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: recipientUids)
              .get();

          final List<String> fcmTokens = [];
          for (final doc in usersSnapshot.docs) {
            final tokens = List<String>.from(doc.data()['fcmTokens'] ?? []);
            fcmTokens.addAll(tokens);
          }

          if (fcmTokens.isNotEmpty) {
            await FcmSenderService.instance.sendGroupInviteNotification(
              targetTokens: fcmTokens,
              groupName: groupName,
              groupId: groupDoc.id,
              inviterName: currentUserName,
            );
          }
        } catch (fcmError) {
          debugPrint('FCM direct dispatch warning: $fcmError');
        }
      }

      final newGroup = GroupModel(
        id: groupDoc.id,
        groupName: groupName,
        description: _descController.text.trim(),
        avatarPath: _selectedImage?.path ?? '',
        members: List<String>.from(_members),
        memberUids: List<String>.from(_memberUids),
        memberEmails: List<String>.from(_memberEmails),
        memberUsernames: List<String>.from(_memberUsernames),
        createdAt: DateTime.now(),
        expenses: [],
        recordedSettlements: [],
      );

      if (mounted) {
        Navigator.pop(context, newGroup);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final tileBg = isDark ? theme.cardColor : const Color(0xFFF4F3F9);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          "Create Group",
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        leading: const BackButton(),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _isLoading ? null : _createGroup,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                "Create Group",
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar selector
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 46,
                        backgroundColor: tileBg,
                        backgroundImage:
                        _selectedImage != null ? FileImage(_selectedImage!) : null,
                        child: _selectedImage == null
                            ? Icon(Icons.group_add_rounded, size: 40, color: AppTheme.primary)
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppTheme.primary,
                          child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Group Name Field
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: "Group Name",
                  hintText: "e.g., Goa Trip, Flat 402",
                  filled: true,
                  fillColor: tileBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? "Group name required" : null,
              ),
              const SizedBox(height: 16),

              // Description Field
              TextFormField(
                controller: _descController,
                decoration: InputDecoration(
                  labelText: "Category / Description (Optional)",
                  hintText: "e.g., Trip, Home, Office",
                  filled: true,
                  fillColor: tileBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Members Section Header
              Text(
                "Add Members by @Username or Email",
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 10),

              // Member Lookup Input
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _memberInputController,
                      decoration: InputDecoration(
                        hintText: "Search username or email...",
                        prefixText: "@ ",
                        prefixStyle: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        filled: true,
                        fillColor: tileBg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _searchAndAddMember(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: _isSearchingUser ? null : _searchAndAddMember,
                      child: _isSearchingUser
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                          : const Icon(Icons.add),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Member List Chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_members.length, (index) {
                  final isMe = index == 0 && _memberUids.contains(_currentUser?.uid);
                  return Chip(
                    backgroundColor: tileBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    label: Text(
                      isMe ? "${_members[index]} (You)" : _members[index],
                      style: TextStyle(
                        color: textColor,
                        fontWeight: isMe ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    deleteIcon: isMe ? null : const Icon(Icons.close, size: 16),
                    onDeleted: isMe ? null : () => _removeMember(index),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}