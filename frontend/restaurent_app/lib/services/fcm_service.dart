import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:Neevika/main.dart';
import 'package:Neevika/screens/Authentication/login_screen.dart';
import 'package:Neevika/services/socket_service.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

class FCMService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize(Function(String?) onTokenReceived) async {
    try {
      // Request permissions (for iOS)
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Notification permission granted');

        // Get and return token
        String? token = await _messaging.getToken();
        if (token != null) {
          print('✅ FCM Token: $token');
          onTokenReceived(token);
        } else {
          print('⚠️ FCM token is null');
        }

        // Foreground message handling
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Notification clicked (background)
        FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageClick);

        // Notification clicked (terminated state)
        RemoteMessage? initialMessage =
            await FirebaseMessaging.instance.getInitialMessage();
        if (initialMessage != null) {
          _handleMessageClick(initialMessage);
        }
      } else {
        print('❌ Notification permission denied');
      }
    } catch (e) {
      print('❌ FCM initialization error: $e');
    }
  }

  static Future<void> showTopNotification(
    BuildContext context,
    String title,
    String message, {
    Color backgroundColor = Colors.green,
    IconData icon = Icons.notifications,
  }) async {
    // Create instance
    final ringtonePlayer = FlutterRingtonePlayer();

    // Play default system notification sound
    ringtonePlayer.play(
      android: AndroidSounds.notification,
      ios: IosSounds.triTone,
      looping: false,
      volume: 1.0,
    );

    // Show visual notification
    Flushbar(
      title: title,
      message: message,
      duration: const Duration(seconds: 3),
      flushbarPosition: FlushbarPosition.TOP,
      backgroundColor: backgroundColor,
      margin: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),
      icon: Icon(icon, color: Colors.white),
    ).show(context);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    // Check if this is a force-logout notification
    if (message.data['type'] == 'force_logout') {
      print('🔴 Force-logout FCM received in foreground');
      _handleForceLogout();
      return;
    }

    final ctx = navigatorKey.currentContext;
    if (ctx != null) {
      final notification = message.notification;
      final title = notification?.title ?? 'Notification';
      final body = notification?.body ?? 'You have a new message';

      showTopNotification(ctx, title, body);
      print('🔔 Foreground message received: $title - $body');
    } else {
      print('⚠️ Context is null. Cannot show foreground message');
    }
  }

  void _handleMessageClick(RemoteMessage message) {
    print('📬 Notification clicked: ${message.messageId}');

    // Check if this is a force-logout notification
    if (message.data['type'] == 'force_logout') {
      print('🔴 Force-logout FCM received from notification click');
      _handleForceLogout();
      return;
    }
  }

  /// Show a popup dialog informing the user they've been logged out
  /// by admin, then redirect to the login screen.
  static Future<void> _handleForceLogout() async {
    // Disconnect socket
    SocketService().disconnect();

    // Clear stored credentials
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwtToken');
    await prefs.remove('userId');

    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      // No context available — just navigate directly
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }

    // Show popup dialog
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        // Auto-redirect after 5 seconds if user doesn't tap OK
        Future.delayed(const Duration(seconds: 5), () {
          try {
            // Safely pop the dialog using the navigator state
            if (navigatorKey.currentState?.canPop() ?? false) {
              navigatorKey.currentState?.pop();
            }
            // Navigate to login screen
            navigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
            );
          } catch (e) {
            debugPrint('Error during auto-redirect: $e');
          }
        });

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(
            Icons.logout_rounded,
            color: Colors.red,
            size: 48,
          ),
          title: const Text(
            'Session Ended',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            'Admin has logged you out.\nPlease login again to continue.\n\nRedirecting in 5 seconds...',
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                navigatorKey.currentState?.pop();
                navigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text('OK', style: TextStyle(fontSize: 16)),
            ),
          ],
        );
      },
    );
  }
}
