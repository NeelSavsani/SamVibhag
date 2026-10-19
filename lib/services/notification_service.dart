import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/group/group_details_screen.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Handled automatically by system tray in background/terminated states
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<void> initialize() async {
    // 1. Background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (iOS / Android 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
    }

    // 3. Local notification setup for foreground banners
    if (!kIsWeb) {
      const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings);

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          if (response.payload != null) {
            try {
              final data = jsonDecode(response.payload!);
              _navigateByPayload(data);
            } catch (e) {
              debugPrint('Error parsing notification response payload: $e');
            }
          }
        },
      );

      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'group_notifications',
        'Group Alerts',
        description: 'Notifications for group invites and activities',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    // 4. Foreground push banner listener (excludes self-dispatched events)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      final senderUid = message.data['senderUid'];

      // Suppress banner if the push originated from the current user
      if (currentUserId != null && senderUid != null && currentUserId == senderUid) {
        return;
      }

      final notification = message.notification;
      if (notification != null && !kIsWeb) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'group_notifications',
              'Group Alerts',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });

    // 5. Handle click when app is brought to foreground from background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _navigateByPayload(message.data);
    });

    // 6. Handle click when app launches from a terminated cold start
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _navigateByPayload(initialMessage.data);
    }

    // 7. Sync FCM token with Firestore
    await saveDeviceToken();
    _fcm.onTokenRefresh.listen((token) => saveDeviceToken(token));
  }

  Future<void> saveDeviceToken([String? token]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final fcmToken = token ?? await _fcm.getToken();
    if (fcmToken != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmTokens': FieldValue.arrayUnion([fcmToken]),
        'lastActive': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  void _navigateByPayload(Map<String, dynamic> data) {
    if (data['type'] == 'group_invite' && data['groupId'] != null) {
      final groupId = data['groupId'].toString();
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => GroupDetailsScreen(groupId: groupId),
        ),
      );
    }
  }
}