import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

    try {
      await FirebaseFirestore.instance
          .collection('groups')
          .doc(widget.group.id)
          .update({
            'groupName': trimmedName,
            'description': trimmedDesc,
            'avatarPath': avatarPath,
            'members': members,
          });

      widget.group.groupName = trimmedName;
      widget.group.description = trimmedDesc;
      widget.group.avatarPath = avatarPath;
      widget.group.members = List<String>.from(members);

      if (!mounted) return;
      Navigator.pop(context, widget.group);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update cloud record: $e")),
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
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
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
                    GestureDetector(
                      onTap: pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundColor: AppTheme.primary.withOpacity(0.15),
                            backgroundImage: avatarPath.isEmpty ? null : FileImage(File(avatarPath)),
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
                    const SizedBox(height: 30),
                    TextField(
                      controller: groupNameController,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Group Name",
                        prefixIcon: const Icon(Icons.groups),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: descriptionController,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: TextStyle(color: theme.colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: "Description",
                        prefixIcon: const Icon(Icons.info_outline),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Card(
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.calendar_today, color: AppTheme.primary),
                        title: const Text("Created"),
                        subtitle: Text(createdDate),
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
                        const Text("Members", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
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
                            child: const Center(child: Text("No Members", style: TextStyle(fontSize: 16))),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: members.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                                    child: const Icon(Icons.person, color: AppTheme.primary),
                                  ),
                                  title: Text(members[index]),
                                  subtitle: Text("Member ${index + 1}"),
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
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: saveGroup,
                        style: FilledButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: AppTheme.primary,
                        ),
                        icon: const Icon(Icons.save),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Text("Save Changes", style: TextStyle(fontSize: 17)),
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