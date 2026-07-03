import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/group_model.dart';
import '../theme/app_theme.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController groupNameController =
      TextEditingController();

  final TextEditingController memberController =
      TextEditingController();

  final TextEditingController descriptionController =
      TextEditingController();

  final List<String> members = [];

  final uuid = const Uuid();

  void addMember() {
    final member = memberController.text.trim();

    if (member.isEmpty) return;

    if (members.contains(member)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Member already exists."),
        ),
      );
      return;
    }

    setState(() {
      members.add(member);
    });

    memberController.clear();
  }

  @override
  void dispose() {
    groupNameController.dispose();
    memberController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        title: const Text(
          "Create Group",
          style: TextStyle(color: Colors.white),
        ),
        actions: const [
          NightModeButton(),
        ],
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            /// GROUP NAME
            TextField(
              controller: groupNameController,

              decoration: InputDecoration(
                labelText: "Group Name",

                prefixIcon:
                    const Icon(Icons.groups),

                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 16),

            /// DESCRIPTION
            TextField(
              controller: descriptionController,
              maxLines: 2,

              decoration: InputDecoration(
                labelText: "Group Description (Optional)",

                prefixIcon:
                    const Icon(Icons.info_outline),

                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 20),

            /// MEMBER FIELD
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: memberController,

                    decoration: InputDecoration(
                      labelText: "Member Name",

                      prefixIcon:
                          const Icon(Icons.person_add),

                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                                14),
                      ),
                    ),

                    onSubmitted: (_) => addMember(),
                  ),
                ),

                const SizedBox(width: 10),

                ElevatedButton(
                  onPressed: addMember,

                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),

                  child: const Text(
                    "Add",
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,

              children: [
                const Text(
                  "Members",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                Chip(
                  label: Text(
                    "${members.length}",
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Expanded(
              child: members.isEmpty
                  ? const Center(
                      child: Text(
                        "No Members Added",
                      ),
                    )
                  : ListView.builder(
                      itemCount: members.length,

                      itemBuilder:
                          (context, index) {
                        return Card(
                          child: ListTile(
                            leading:
                                const CircleAvatar(
                              backgroundColor:
                                  AppTheme.primary,

                              child: Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                            ),

                            title:
                                Text(members[index]),

                            trailing:
                                IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color:
                                    AppTheme.warning,
                              ),

                              onPressed: () {
                                setState(() {
                                  members.removeAt(
                                      index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(
                icon:
                    const Icon(Icons.check_circle),

                label: const Text(
                  "Create Group",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white,
                  ),
                ),

                onPressed: () {
                  if (groupNameController.text
                      .trim()
                      .isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Please Enter Group Name",
                        ),
                      ),
                    );
                    return;
                  }

                  if (members.isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Please Add At Least One Member",
                        ),
                      ),
                    );
                    return;
                  }

                  final group = GroupModel(
                    id: uuid.v4(),

                    groupName:
                        groupNameController.text
                            .trim(),

                    description:
                        descriptionController.text
                            .trim(),

                    avatarPath: "",

                    createdAt:
                        DateTime.now(),

                    members:
                        List<String>.from(
                      members,
                    ),

                    expenses: [],
                  );

                  Navigator.pop(
                    context,
                    group,
                  );
                },

                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 18,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                            14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}