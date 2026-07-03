import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/group_model.dart';
import '../theme/app_theme.dart';

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

  final ImagePicker picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    groupNameController = TextEditingController(text: widget.group.groupName);

    descriptionController = TextEditingController(
      text: widget.group.description,
    );

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

                if (name.isEmpty) {
                  return;
                }

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
          content: Text(
            "Can't remove $member because they are included in an expense",
          ),
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

  void saveGroup() {
    if (groupNameController.text.trim().isEmpty) {
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

    widget.group.groupName = groupNameController.text.trim();

    widget.group.description = descriptionController.text.trim();

    widget.group.avatarPath = avatarPath;

    widget.group.members = List<String>.from(members);

    Navigator.pop(context, widget.group);
  }

  String get createdDate {
    return DateFormat("dd MMM yyyy, hh:mm a").format(widget.group.createdAt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Group Information",
          style: TextStyle(color: Colors.white),
        ),

        actions: [
          IconButton(
            onPressed: saveGroup,

            icon: const Icon(Icons.check, color: Colors.white),
          ),

          const NightModeButton(),
        ],
      ),

      body: SingleChildScrollView(
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

                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),

                    backgroundImage: avatarPath.isEmpty
                        ? null
                        : FileImage(File(avatarPath)),

                    child: avatarPath.isEmpty
                        ? const Icon(
                            Icons.groups,
                            size: 60,
                            color: AppTheme.primary,
                          )
                        : null,
                  ),

                  CircleAvatar(
                    radius: 18,

                    backgroundColor: AppTheme.primary,

                    child: const Icon(
                      Icons.camera_alt,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            TextField(
              controller: groupNameController,

              decoration: InputDecoration(
                labelText: "Group Name",

                prefixIcon: const Icon(Icons.groups),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 18),

            TextField(
              controller: descriptionController,

              maxLines: 3,

              decoration: InputDecoration(
                labelText: "Description",

                prefixIcon: const Icon(Icons.info_outline),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 20),

            Card(
              elevation: 0,

              child: ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: AppTheme.primary,
                ),

                title: const Text("Created"),

                subtitle: Text(createdDate),
              ),
            ),

            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Members",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
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
                      color: Theme.of(context).cardColor,

                      borderRadius: BorderRadius.circular(16),
                    ),

                    child: const Center(
                      child: Text("No Members", style: TextStyle(fontSize: 16)),
                    ),
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
                        ),

                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primary.withValues(
                              alpha: 0.15,
                            ),

                            child: const Icon(
                              Icons.person,
                              color: AppTheme.primary,
                            ),
                          ),

                          title: Text(members[index]),

                          subtitle: Text("Member ${index + 1}"),

                          trailing: IconButton(
                            tooltip: "Remove Member",

                            onPressed: () => removeMember(index),

                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.red,
                            ),
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

                icon: const Icon(Icons.save),

                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),

                  child: Text("Save Changes", style: TextStyle(fontSize: 17)),
                ),
              ),
            ),

            const SizedBox(height: 16),

            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },

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
    );
  }
}
