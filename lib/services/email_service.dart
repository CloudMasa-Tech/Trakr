import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;

class EmailService {
  static const String _vercelUrl =
      'https://trakr-six.vercel.app/api/sendCredentialEmail';

  static Future<void> sendAccountCredentials({
    required String recipientEmail,
    required String password,
    required String roleLabel,
    String? recipientName,
  }) async {
    final name = recipientName?.trim();
    final userName = name == null || name.isEmpty ? 'User' : name;
    final normalizedEmail = recipientEmail.trim().toLowerCase();

    try {
      final response = await http.post(
        Uri.parse(_vercelUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'recipientEmail': normalizedEmail,
          'recipientName': userName,
          'roleLabel': roleLabel,
          'password': password,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(response.body);
      }
      debugPrint('Automated email sent successfully to $normalizedEmail');
    } catch (e) {
      throw Exception('Failed to send credential email automatically: $e');
    }
  }

  static Future<void> sendManagerCredentials({
    required String recipientEmail,
    required String password,
  }) {
    return sendAccountCredentials(
      recipientEmail: recipientEmail,
      password: password,
      roleLabel: 'manager',
    );
  }
}
