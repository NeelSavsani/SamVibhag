import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class FcmSenderService {
  static final FcmSenderService instance = FcmSenderService._internal();
  FcmSenderService._internal();

  static const String _projectId = 'samvibhag-a2299';
  static const String _scopes = 'https://www.googleapis.com/auth/firebase.messaging';

  String? _cachedToken;
  DateTime? _tokenExpiry;

  Future<String?> _getAccessToken() async {
    if (_cachedToken != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedToken;
    }

    try {
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final accountCredentials = ServiceAccountCredentials.fromJson(json.decode(jsonString));
      final client = await clientViaServiceAccount(accountCredentials, [_scopes]);

      _cachedToken = client.credentials.accessToken.data;
      _tokenExpiry = client.credentials.accessToken.expiry;
      client.close();

      return _cachedToken;
    } catch (e) {
      return null;
    }
  }

  /// Sends a push notification directly via Google's FCM v1 endpoint
  Future<void> sendGroupInviteNotification({
    required List<String> targetTokens,
    required String groupName,
    required String groupId,
    required String inviterName,
  }) async {
    final accessToken = await _getAccessToken();
    if (accessToken == null || targetTokens.isEmpty) return;

    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');

    for (final token in targetTokens) {
      final payload = {
        'message': {
          'token': token,
          'notification': {
            'title': 'New Group Invite',
            'body': '$inviterName added you to "$groupName"',
          },
          'data': {
            'type': 'group_invite',
            'groupId': groupId,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'group_notifications',
              'sound': 'default',
            },
          },
        },
      };

      try {
        await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode(payload),
        );
      } catch (_) {
        // Individual token delivery failure ignored
      }
    }
  }
}