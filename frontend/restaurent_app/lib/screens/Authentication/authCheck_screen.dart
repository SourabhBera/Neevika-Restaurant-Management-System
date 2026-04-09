import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:Neevika/routes/routes.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});

  @override
  _AuthCheckState createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final prefs = await SharedPreferences.getInstance();
    final jwtToken = prefs.getString('jwtToken');

    if (jwtToken == null) {
      // Navigate after widget is mounted
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, '/login');
      });
    } else {
      // You can decode and validate token here if needed
      Future.microtask(() {
        Navigator.pushReplacementNamed(context, '/home'); // or wherever
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a temporary loading screen
    return Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
