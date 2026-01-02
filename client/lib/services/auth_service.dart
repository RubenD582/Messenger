import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class AuthService {
  static const String baseUrl = '${ApiConfig.baseUrl}/auth';
  static const _secureStorage = FlutterSecureStorage();

  Future<Map<String, dynamic>> registerWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String username,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register-with-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
          'username': username,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
          'email': data['email'],
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Registration failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        await _saveToken(data['token']);
        await _saveUserData(data['user']);
        return {
          'success': true,
          'message': data['message'],
          'user': data['user'],
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Verification failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> loginWithEmail({
    required String email,
    required String password,
    bool use2FA = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login-with-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'use2FA': use2FA,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (data['requires2FA'] == true) {
          return {
            'success': true,
            'requires2FA': true,
            'message': data['message'],
            'email': data['email'],
          };
        } else {
          // Save both access and refresh tokens
          await _saveToken(data['accessToken']);
          await _saveRefreshToken(data['refreshToken']);
          await _saveUserData(data['user']);
          return {
            'success': true,
            'requires2FA': false,
            'user': data['user'],
          };
        }
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Login failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> verify2FA({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-2fa'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        await _saveToken(data['token']);
        await _saveUserData(data['user']);
        return {
          'success': true,
          'message': data['message'],
          'user': data['user'],
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? '2FA verification failed',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<void> _saveToken(String token) async {
    // Use secure storage for token (encrypted)
    await _secureStorage.write(key: 'auth_token', value: token);
    if (kDebugMode) {
      print('AUTSERVICE: Access token saved securely');
    }
  }

  Future<void> _saveRefreshToken(String refreshToken) async {
    await _secureStorage.write(key: 'refresh_token', value: refreshToken);
    if (kDebugMode) {
      print('AUTSERVICE: Refresh token saved securely');
    }
  }

  Future<void> _saveUserData(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', jsonEncode(user));
  }

  static Future<String?> getToken() async {
    // Retrieve token from secure storage
    final token = await _secureStorage.read(key: 'auth_token');
    if (kDebugMode && token != null) {
      print('AUTSERVICE: Access token retrieved from secure storage');
    }
    return token;
  }

  static Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: 'refresh_token');
  }

  /// Refresh access token using refresh token
  static Future<Map<String, dynamic>> refreshAccessToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) {
        return {'success': false, 'error': 'No refresh token available'};
      }

      final response = await http.post(
        Uri.parse('$baseUrl/refresh-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Save new tokens
        await _secureStorage.write(key: 'auth_token', value: data['accessToken']);
        await _secureStorage.write(key: 'refresh_token', value: data['refreshToken']);

        if (kDebugMode) {
          print('AUTSERVICE: Tokens refreshed successfully');
        }

        return {'success': true, 'accessToken': data['accessToken']};
      } else {
        return {'success': false, 'error': data['message'] ?? 'Token refresh failed'};
      }
    } catch (e) {
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }


  Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      return jsonDecode(userDataString);
    }
    return null;
  }

  static Future<String?> getUserUuid() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataString = prefs.getString('user_data');
    if (userDataString != null) {
      final userData = jsonDecode(userDataString);
      return userData['id'];
    }
    return null;
  }

  Future<void> logout() async {
    // Clear tokens from secure storage
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'refresh_token');

    // Clear user data from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');

    if (kDebugMode) {
      print('AUTSERVICE: Logged out successfully');
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<Map<String, dynamic>> sendPasswordResetEmail({
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Failed to send reset email',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'newPassword': newPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'message': data['message'],
        };
      } else {
        return {
          'success': false,
          'error': data['message'] ?? 'Failed to reset password',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error: ${e.toString()}',
      };
    }
  }
}
