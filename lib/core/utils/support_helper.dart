import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportHelper {
  static Future<void> openSupportEmail(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;

    // 1. Fetch live user details from Firebase Auth
    final String userEmail = user?.email ?? 'Not logged in';
    final String userId = user?.uid ?? 'N/A';

    // 2. Fetch runtime environment details
    final String userOs = Platform.operatingSystem; // android, ios, windows, web, etc.
    final String userDevice = Platform.isAndroid 
        ? 'Android Device' 
        : (Platform.isIOS ? 'iOS Device' : 'Desktop/Web');
    const String appVersion = '1.0.0';

    // 3. Define target recipient & subject
    const String supportEmail = 'neelsavsani7@gmail.com';
    const String subject = 'SamVibhag';

    // 4. Construct the required body format
    final String body = '''
[footer]
email: $userEmail
support code: $userId
Device: $userDevice
Operating System: $userOs
app version: $appVersion
''';

    // 5. Build the mailto URI
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    // 6. Launch the device's native email client
    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        // Fallback for external app handling (e.g. browser/web mail)
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open mail app: $e')),
        );
      }
    }
  }
}