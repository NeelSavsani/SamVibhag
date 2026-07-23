import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../models/group_model.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  bool _isLoading = false;

  String _selectedType = "Trip";

  final List<Map<String, dynamic>> _categories = [
    {"name": "Trip", "icon": Icons.flight_takeoff_rounded},
    {"name": "Home", "icon": Icons.home_rounded},
    {"name": "Couple", "icon": Icons.favorite_rounded},
    {"name": "Other", "icon": Icons.category_rounded},
  ];

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  // FIXED: Writes the newly populated model fields directly into Cloud Firestore 
  Future<void> _submitGroup() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Authentication required to create cloud groups.")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final generatedId = const Uuid().v4();
      final rawDisplayName = user.displayName?.trim() ?? "Neel Savsani";

      // Build member variations (e.g., "Neel B Savsani" and "Neel Savsani") to avoid naming mismatches
      final Set<String> initialMembers = {rawDisplayName};
      final nameParts = rawDisplayName.split(' ');
      if (nameParts.length > 2) {
        // First and Last name combined without middle initial/name
        initialMembers.add('${nameParts.first} ${nameParts.last}');
      }

      final newGroup = GroupModel(
        id: generatedId,
        groupName: _groupNameController.text.trim(),
        description: "A $_selectedType group split.",
        avatarPath: "",
        // Seed initial members list with name variations
        members: initialMembers.toList(),
        expenses: [],
        createdAt: DateTime.now(),
      );

      // Save directly into your central cloud firebase reference collection
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(generatedId)
          .set({
            ...newGroup.toMap(),
            'createdBy': user.uid, // Track creator UID explicitly for security & query matching
          });

      if (!mounted) return;
      Navigator.pop(context, newGroup);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Firebase Database Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface),
        ),
        title: Text(
          "Create Group",
          style: GoogleFonts.poppins(
            fontSize: 19,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start a shared space',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Name your group and choose what it is for.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withValues(alpha: .62),
                        ),
                      ),
                      const SizedBox(height: 24),
                      /// Avatar + Name Card
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: const Color(0xFF83F4EB).withValues(alpha: .2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: () {},
                                child: Container(
                                  width: 74,
                                  height: 74,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF83F4EB).withValues(alpha: isDark ? .16 : .25),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    color: AppTheme.primary,
                                    size: 32,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: TextFormField(
                                  controller: _groupNameController,
                                  textCapitalization: TextCapitalization.words,
                                  style: GoogleFonts.poppins(fontSize: 14),
                                  decoration: InputDecoration(
                                    labelText: "Group Name",
                                    hintText: "Eg. Goa Trip",
                                    labelStyle: GoogleFonts.poppins(fontSize: 13),
                                    hintStyle: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurface.withValues(alpha: .45),
                                    ),
                                    prefixIcon: const Icon(Icons.groups_rounded, color: Color(0xFF0284C7)),
                                    filled: true,
                                    fillColor: theme.colorScheme.surface,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(color: Color(0xFF83F4EB), width: 1.5),
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return "Please enter a group name";
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        "Choose Group Type",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 88,
                        child: Row(
                          children: _categories.map((category) {
                            final selected = _selectedType == category["name"];

                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () {
                                    setState(() {
                                      _selectedType = category["name"];
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    decoration: BoxDecoration(
                                      color: selected ? null : theme.cardColor,
                                      gradient: selected
                                          ? const LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                                            )
                                          : null,
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: selected ? AppTheme.primary : theme.dividerColor,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          category["icon"],
                                          size: 30,
                                          color: selected ? Colors.white : AppTheme.primary,
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          category["name"],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: selected ? Colors.white : theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 30),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(color: const Color(0xFF83F4EB).withValues(alpha: .18)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: AppTheme.primary,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  "You can add members after creating the group. "
                                  "Expenses, settlements and reports will be available once members are added.",
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface.withValues(alpha: .7),
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0284C7).withValues(alpha: .26),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: FilledButton.icon(
                          onPressed: _submitGroup,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.group_add_rounded),
                          label: Text(
                            "Create Group",
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}