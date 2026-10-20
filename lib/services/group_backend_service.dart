import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

class GroupBackendService {
  GroupBackendService._();

  static final String _baseUrl =
      'https://us-central1-${DefaultFirebaseOptions.currentPlatform.projectId}.cloudfunctions.net';

  static Future<void> manageSettlement(Map<String, dynamic> data) async {
    await _call('manageSettlement', data);
  }

  static Future<void> deleteGroup(String groupId) async {
    await _call('deleteGroup', {'groupId': groupId});
  }

  static Future<void> addGroupMember({
    required String groupId,
    required String displayName,
    String? uid,
    String? email,
    String? username,
  }) async {
    await _call('addGroupMember', {
      'groupId': groupId,
      'displayName': displayName,
      if (uid != null) 'uid': uid,
      if (email != null) 'email': email,
      if (username != null) 'username': username,
    });
  }

  static Future<bool> migrateGroupMemberIdentities(String groupId) async {
    final result = await _call('migrateGroupMemberIdentities', {'groupId': groupId});
    return result['migrated'] == true;
  }

  static Future<Map<String, dynamic>> _call(
    String functionName,
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in is required.');
    final token = await user.getIdToken();
    if (token == null || token.isEmpty) {
      throw StateError('Could not authenticate the request.');
    }

    final response = await http.post(
      Uri.parse('$_baseUrl/$functionName'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'data': data}),
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body.containsKey('error')) {
      final error = body['error'];
      final message = error is Map<String, dynamic>
          ? error['message']?.toString()
          : null;
      throw Exception(
        message ?? 'Backend request failed (${response.statusCode}).',
      );
    }
    return (body['result'] as Map<String, dynamic>?) ?? <String, dynamic>{};
  }
}
