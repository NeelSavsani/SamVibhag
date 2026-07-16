import 'dart:convert'; // REQUIRED: To parse the JSON response from Cloudinary
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http; // REQUIRED: For the HTTP network request
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/group_model.dart';
import '../../core/theme/app_theme.dart';
import '../report_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({super.key, required this.group});

  final GroupModel group;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late TextEditingController groupNameController;
  late TextEditingController descriptionController;
  late List<String> members;
  String avatarPath = "";
  bool _isLoading = false;

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    groupNameController = TextEditingController(text: widget.group.groupName);
    descriptionController = TextEditingController(text: widget.group.description);
    members = List<String>.from(widget.group.members);
    avatarPath = widget.group.avatarPath.trim();
  }

  @override
  void dispose() {
    groupNameController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image == null) return;

    setState(() {
      avatarPath = image.path;
    });
  }

  void addMember() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Member"),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: "Member Name"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isEmpty) return;

                if (members.contains(name)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Member already exists")),
                  );
                  return;
                }

                setState(() {
                  members.add(name);
                });
                Navigator.pop(context);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  void removeMember(int index) {
    final member = members[index];

    final isUsedByExpense = widget.group.expenses.any(
      (expense) =>
          expense.paidBy == member ||
          expense.splitBetween.contains(member) ||
          expense.customSplits.containsKey(member),
    );

    if (isUsedByExpense) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Can't remove $member because they are included in an expense"),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Remove Member"),
          content: Text("Remove $member?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                setState(() {
                  members.remove(member);
                });
                Navigator.pop(context);
              },
              child: const Text("Remove"),
            ),
          ],
        );
      },
    );
  }

  Future<void> saveGroup() async {
    final trimmedName = groupNameController.text.trim();
    final trimmedDesc = descriptionController.text.trim();

    if (trimmedName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Group name cannot be empty")),
      );
      return;
    }

    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("A group must have at least one member")),
      );
      return;
    }

    setState(() => _isLoading = true);

    String finalAvatarUrl = avatarPath;

    try {
      // Upload directly to Cloudinary if avatarPath is an un-uploaded local file path string
      if (avatarPath.isNotEmpty && !avatarPath.startsWith('http')) {
        final File file = File(avatarPath);

        if (await file.exists()) {
          // Cloud name and unsigned upload preset are safe to keep in client code
          const String cloudName = "kgtyxboo";
          const String uploadPreset = "samvibhag_preset";

          final request = http.MultipartRequest(
            'POST',
            Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload'),
          );
          request.fields['upload_preset'] = uploadPreset;
          request.files.add(await http.MultipartFile.fromPath('file', file.path));

          final response = await request.send();
          final responseBody = await response.stream.bytesToString();

          if (response.statusCode == 200) {
            final jsonResponse = jsonDecode(responseBody);

            // Extract the direct permanent clean network URL string layout
            finalAvatarUrl = jsonResponse['secure_url'];
          } else {
            // Surface Cloudinary's actual error message instead of just the status code
            String reason = responseBody;
            try {
              final parsed = jsonDecode(responseBody);
              reason = parsed['error']?['message']?.toString() ?? responseBody;
            } catch (_) {
              // response wasn't JSON — fall back to raw body
            }
            throw Exception(
              "Cloudinary upload failed (${response.statusCode}): $reason",
            );
          }
        }
      }

      // Update Firestore database using the public Cloudinary image URL link channel
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .update({
            'groupName': trimmedName,
            'description': trimmedDesc,
            'avatarPath': finalAvatarUrl,
            'members': members,
          });

      // Synchronize changes back to the active tracking instance model
      widget.group.groupName = trimmedName;
      widget.group.description = trimmedDesc;
      widget.group.avatarPath = finalAvatarUrl;
      widget.group.members = List<String>.from(members);

      if (!mounted) return;
      // Pass the updated model back to GroupDetailsScreen so the cover updates dynamically
      Navigator.pop(context, widget.group);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to save changes: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> openReport() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReportScreen(group: widget.group)),
    );
  }

  String get createdDate {
    return DateFormat("dd MMM yyyy, hh:mm a").format(widget.group.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121214) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          "Group Information",
          style: GoogleFonts.poppins(
            fontSize: 19,
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Manage your group',
                        style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Update the profile and manage members.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    GestureDetector(
                      onTap: pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: AppTheme.primary.withOpacity(0.15),
                            backgroundImage: avatarPath.isEmpty
                                ? null
                                : (avatarPath.startsWith('http')
                                    ? NetworkImage(avatarPath)
                                    : FileImage(File(avatarPath)) as ImageProvider),
                            child: avatarPath.isEmpty
                                ? const Icon(Icons.groups, size: 60, color: AppTheme.primary)
                                : null,
                          ),
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppTheme.primary,
                            child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: groupNameController,
                      style: GoogleFonts.poppins(color: theme.colorScheme.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: "Group Name",
                        labelStyle: GoogleFonts.poppins(fontSize: 13),
                        prefixIcon: const Icon(Icons.groups, color: Color(0xFF0284C7)),
                        filled: true,
                        fillColor: theme.cardColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF83F4EB), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: descriptionController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: GoogleFonts.poppins(color: theme.colorScheme.onSurface, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: "Description",
                        labelStyle: GoogleFonts.poppins(fontSize: 13),
                        prefixIcon: const Icon(Icons.info_outline, color: Color(0xFF0284C7)),
                        filled: true,
                        fillColor: theme.cardColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: Color(0xFF83F4EB), width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: const Color(0xFF83F4EB).withOpacity(0.16)),
                      ),
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today, color: AppTheme.primary),
                        title: Text("Created", style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(createdDate, style: GoogleFonts.poppins(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: openReport,
                        child: const ListTile(
                          leading: Icon(Icons.picture_as_pdf, color: Colors.red),
                          title: Text("Export PDF Report", style: TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text("Generate and download expense balance statements"),
                          trailing: Icon(Icons.chevron_right_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Members",
                          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700),
                        ),
                        FilledButton.icon(
                          onPressed: addMember,
                          icon: const Icon(Icons.person_add),
                          label: const Text("Add"),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    members.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              color: theme.cardColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: const Center(child: Text("No Members", style: TextStyle(fontSize: 14))),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: members.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: const Color(0xFF83F4EB).withOpacity(0.14)),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                                    child: const Icon(Icons.person, color: AppTheme.primary),
                                  ),
                                  title: Text(
                                    members[index],
                                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text("Member ${index + 1}", style: GoogleFonts.poppins(fontSize: 12)),
                                  trailing: IconButton(
                                    tooltip: "Remove Member",
                                    onPressed: () => removeMember(index),
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  ),
                                ),
                              );
                            },
                          ),
                    const SizedBox(height: 30),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0284C7).withOpacity(0.24),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: FilledButton.icon(
                        onPressed: saveGroup,
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                        ),
                        icon: const Icon(Icons.save),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            "Save Changes",
                            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Text("Back"),
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
      ),
    );
  }
}
