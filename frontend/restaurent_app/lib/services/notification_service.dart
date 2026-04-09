// lib/services/notification_service.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:another_flushbar/flushbar.dart';
import 'dart:convert';

class NotificationHelper {
  /// Displays a flushbar-style top notification
  static void showTopNotification(
    BuildContext context,
    String title,
    String message, {
    Color backgroundColor = Colors.green,
    IconData icon = Icons.notifications,
  }) {
    Flushbar(
      title: title,
      message: message,
      duration: const Duration(seconds: 6),
      flushbarPosition: FlushbarPosition.TOP,
      backgroundColor: backgroundColor,
      margin: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),
      icon: Icon(icon, color: Colors.white),
    ).show(context);
  }

  /// Sends a notification to the backend
  static Future<void> sendNotification({
    String? userId,
    List<String>? userIds,
    String? role,
    List<String>? roles,
    required String title,
    required String message,
    BuildContext? context,
    bool showVisualFeedback = false,
  }) async {
    // Guard: No recipient provided
    if (userId == null &&
        (userIds == null || userIds.isEmpty) &&
        role == null &&
        (roles == null || roles.isEmpty)) {
      debugPrint('⚠️ No target specified for the notification.');
      return;
    }

    try {
      final url = Uri.parse('${dotenv.env['API_URL']}/notify-user');

      // Use Map<String, dynamic> to support both String and List<String>
      final Map<String, dynamic> body = {
        'title': title,
        'message': message,
      };

      if (userId != null) body['userId'] = userId;
      if (userIds != null) body['userIds'] = userIds;
      if (role != null) body['role'] = role;
      if (roles != null) body['roles'] = roles;

      debugPrint('📤 Sending notification with body: ${json.encode(body)}');

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      final resBody = json.decode(response.body);

      if (response.statusCode == 200) {
        debugPrint('✅ Notification sent successfully: ${resBody['message']}');

        if (context != null && showVisualFeedback) {
          showTopNotification(context, "Notification Sent", "Successfully delivered");
        }
      } else {
        debugPrint('❌ Failed to send notification: ${resBody['message']}');
      }
    } catch (e) {
      debugPrint('❌ Error sending notification: $e');
    }
  }
}
