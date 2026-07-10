import 'package:flutter/material.dart';
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

  void _submitGroup() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final newGroup = GroupModel(
      id: const Uuid().v4(),

      groupName: _groupNameController.text.trim(),

      description: "A $_selectedType group.",

      avatarPath: "",

      members: [],

      expenses: [],

      createdAt: DateTime.now(),
    );

    Navigator.pop(context, newGroup);
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// Avatar + Name Card
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
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
                              color: AppTheme.primary.withValues(alpha: .12),

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

                            decoration: InputDecoration(
                              labelText: "Group Name",

                              hintText: "Eg. Goa Trip",

                              prefixIcon: const Icon(Icons.groups_rounded),

                              filled: true,

                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
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

                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
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
                                color: selected
                                    ? AppTheme.primary
                                    : theme.cardColor,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? AppTheme.primary
                                      : theme.dividerColor,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    category["icon"],
                                    size: 30,
                                    color: selected
                                        ? Colors.white
                                        : AppTheme.primary,
                                  ),

                                  const SizedBox(height: 10),

                                  Text(
                                    category["name"],
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: selected
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
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
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _submitGroup,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text(
                      "Create Group",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
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
