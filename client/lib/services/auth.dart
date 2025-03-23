import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http_cookie_store/http_cookie_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "http://localhost:3000";
  static final CookieClient client = CookieClient();
  static final storage = FlutterSecureStorage();  // Make storage static
  static late SharedPreferences prefs;

  // Static login function
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/auth/login');
    final body = {
      'username': username,
      'password': password,
    };

    try {
      final response = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        prefs = await SharedPreferences.getInstance();
        await prefs.setString('userUuid', responseData['uuid']);

        return {'success': true, 'username': responseData['username']};
      } else {
        final errorData = json.decode(response.body);
        return {'success': false, 'message': errorData['message']};
      }
    } catch (error) {
      return {'success': false, 'message': error.toString()};
    }
  }

  static Future<String?> getToken() async {
    final cookies = client.store.cookies;

    final tokenCookie = cookies.firstWhere(
      (cookie) => cookie.name == 'access_token', 
      orElse: () => Cookie("access_token", ""),
    );

    return tokenCookie.value;
  }

  static Future<String?> getUserUuid() async {
    prefs = await SharedPreferences.getInstance();
    return prefs.getString('userUuid');
  }

  // Method to clear cookies (optional)
  static Future<void> clearCookies() async {
    client.close();
  }
}
