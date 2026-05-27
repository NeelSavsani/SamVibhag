import 'package:flutter/material.dart';

import '../models/group_model.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final TextEditingController groupNameController = TextEditingController();

  final TextEditingController memberController = TextEditingController();

  List<String> members = [];

  void addMember() {
    if (memberController.text.trim().isNotEmpty) {
      setState(() {
        members.add(memberController.text.trim());
      });

      memberController.clear();
    }
  }

  @override
  void dispose() {
    groupNameController.dispose();
    memberController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF2563EB),

        title: const Text(
          "Create Group",
          style: TextStyle(color: Colors.white),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            /// GROUP NAME
            TextField(
              controller: groupNameController,

              decoration: InputDecoration(
                labelText: "Group Name",

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
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

                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                ElevatedButton(
                  onPressed: addMember,

                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),

                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 18,
                    ),
                  ),

                  child: const Text(
                    "Add",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 25),

            /// MEMBERS TITLE
            const Text(
              "Members",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 15),

            /// MEMBERS LIST
            Expanded(
              child: members.isEmpty
                  ? const Center(child: Text("No Members Added"))
                  : ListView.builder(
                      itemCount: members.length,

                      itemBuilder: (context, index) {
                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFF2563EB),

                              child: Icon(Icons.person, color: Colors.white),
                            ),

                            title: Text(members[index]),

                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),

                              onPressed: () {
                                setState(() {
                                  members.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),

            /// CREATE BUTTON
            SizedBox(
              width: double.infinity,

              child: ElevatedButton(
                onPressed: () {
                  if (groupNameController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please Enter Group Name")),
                    );

                    return;
                  }

                  if (members.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Please Add At Least One Member"),
                      ),
                    );

                    return;
                  }

                  final group = GroupModel(
                    groupName: groupNameController.text.trim(),
                    members: List<String>.from(members),
                  );

                  Navigator.pop(context, group);
                },

                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),

                  padding: const EdgeInsets.symmetric(vertical: 18),

                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),

                child: const Text(
                  "Create Group",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
