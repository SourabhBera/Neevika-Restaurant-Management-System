import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:Neevika/main.dart';
import 'package:Neevika/screens/Authentication/login_screen.dart';

/// Singleton service that maintains a Socket.IO connection for the
/// currently logged-in user. It listens for the `force_logout` event
/// emitted by the admin as a secondary mechanism (primary is FCM).
class SocketService {
  // ── Singleton ──────────────────────────────────────────────────────────
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;

  /// Connect to the Socket.IO server and join the user-specific room.
  /// Should be called after a successful login or when resuming a session.
  void connect(dynamic userId) {
    if (_isConnected && _socket != null) {
      debugPrint('SocketService: already connected, skipping');
      return;
    }

    final serverUrl = dotenv.env['API_URL_1'] ?? dotenv.env['API_URL'] ?? '';
    if (serverUrl.isEmpty) {
      debugPrint('SocketService: no API_URL found in .env');
      return;
    }

    debugPrint('SocketService: connecting to $serverUrl for userId=$userId');

    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    _socket!.on('connect', (_) {
      _isConnected = true;
      debugPrint('SocketService: ✅ connected (${_socket!.id})');

      // Join the user-specific room so we receive force_logout events
      _socket!.emit('join_user_room', userId);
      debugPrint('SocketService: joined room user_$userId');
    });

    _socket!.on('force_logout', (_) {
      debugPrint('SocketService: 🔴 force_logout received via socket');
      _handleForceLogout();
    });

    _socket!.on('disconnect', (_) {
      _isConnected = false;
      debugPrint('SocketService: ❌ disconnected');
    });
  }

  /// Disconnect from the Socket.IO server.
  /// Call this when the user manually logs out.
  void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _isConnected = false;
      debugPrint('SocketService: disconnected and disposed');
    }
  }

  /// Handle the force-logout event from socket:
  /// 1. Clear stored credentials
  /// 2. Disconnect socket
  /// 3. Show popup dialog
  /// 4. Navigate to login screen
  Future<void> _handleForceLogout() async {
    // Clear local credentials
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwtToken');
    await prefs.remove('userId');

    // Disconnect socket
    disconnect();

    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
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
