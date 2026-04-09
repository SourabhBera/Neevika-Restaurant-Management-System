import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:Neevika/screens/Authentication/login_screen.dart';
import 'package:Neevika/services/socket_service.dart';
import 'dart:convert';

class LogoutScreen extends StatefulWidget {
  const LogoutScreen({super.key});

  @override
  State<LogoutScreen> createState() => _LogoutScreenState();
}

class _LogoutScreenState extends State<LogoutScreen> {
  @override
  void initState() {
    super.initState();
    _logout();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwtToken');

    if (token == null) {
      print('No token found. User might not be logged in.');
      return;
    }
    final decodedToken = JwtDecoder.decode(token);
    final userId = decodedToken['id'];

    if (userId != null) {
      try {
        final response = await http.post(
          Uri.parse('${dotenv.env['API_URL']}/auth/logout/$userId'), // Replace with your actual API
          headers: {
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          print('Logout successful: ${response.body}');
        } else {
          print('Logout failed: ${response.statusCode} ${response.body}');
        }
      } catch (e) {
        print('Error sending logout request: $e');
      }
    }

    // Disconnect socket before clearing local storage (prevents force_logout firing)
    SocketService().disconnect();

    // Clear local storage
    await prefs.remove('jwtToken');
    await prefs.remove('userId');

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (Route<dynamic> route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
