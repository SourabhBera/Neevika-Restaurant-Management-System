// services/token_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

class TokenService {
  Future<void> sendToken(String token, int userId) async {
    final response = await http.post(
      Uri.parse('${dotenv.env['API_URL']}/save-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': token, 'userId': userId}),
    );

    if (response.statusCode == 200) {
      print("\n\nToken saved successfully  ----> $token\n\n  ");
    } else {
      print("Failed to save token: ${response.body}");
    }
  }
}
