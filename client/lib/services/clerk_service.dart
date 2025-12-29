import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/clerk_config.dart';

/// Clerk Authentication Service
///
/// Handles all Clerk authentication operations including:
/// - Sign in with email/password
/// - Sign up with email/password
/// - Two-factor authentication (2FA) via email PIN
/// - Email verification
/// - Session management
/// - Sign out
class ClerkService {
  static final ClerkService _instance = ClerkService._internal();
  factory ClerkService() => _instance;
  ClerkService._internal();

  // Note: Clerk Flutter SDK does not have a stable API yet
  // We'll use HTTP requests directly to Clerk's API endpoints
  bool _initialized = false;

  /// Initialize service
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }

  /// Sign in with email and password
  ///
  /// Returns a Map with:
  /// - 'success': bool
  /// - 'requires2FA': bool (if true, call verify2FACode next)
  /// - 'sessionToken': String? (if success and no 2FA required)
  /// - 'signInId': String? (for 2FA flow)
  /// - 'error': String? (if failed)
  Future<Map<String, dynamic>> signInWithEmailPassword(String email, String password) async {
    try {
      await initialize();

      // Call Clerk API to create sign-in
      final response = await http.post(
        Uri.parse('${ClerkConfig.clerkFrontendApi}/v1/client/sign_ins'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'identifier': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final signInData = data['response'] ?? data;

        // Check if 2FA is required
        if (signInData['status'] == 'needs_second_factor') {
          // Prepare email code for 2FA
          final prepareResponse = await http.post(
            Uri.parse('${ClerkConfig.clerkFrontendApi}/v1/client/sign_ins/${signInData['id']}/prepare_second_factor'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'strategy': 'email_code'}),
          );

          if (prepareResponse.statusCode == 200) {
            return {
              'success': false,
              'requires2FA': true,
              'signInId': signInData['id'],
              'message': '2FA code sent to your email',
            };
          }
        }

        // Check if sign-in is complete
        if (signInData['status'] == 'complete') {
          final sessionToken = signInData['last_active_session_id'];

          if (sessionToken == null) {
            return {'success': false, 'error': 'Failed to get session token'};
          }

          await _saveSessionToken(sessionToken);
          await _fetchAndSaveUserData(sessionToken);

          return {
            'success': true,
            'requires2FA': false,
            'sessionToken': sessionToken,
          };
        }

        return {'success': false, 'error': 'Sign-in incomplete'};
      }

      return {'success': false, 'error': 'Invalid credentials'};
    } catch (e) {
      if (kDebugMode) print('Sign in error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Verify 2FA code
  ///
  /// Call this after signInWithEmailPassword returns requires2FA: true
  Future<Map<String, dynamic>> verify2FACode(String signInId, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ClerkConfig.clerkFrontendApi}/v1/client/sign_ins/$signInId/attempt_second_factor'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'strategy': 'email_code',
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final signInData = data['response'] ?? data;

        if (signInData['status'] == 'complete') {
          final sessionToken = signInData['last_active_session_id'];

          if (sessionToken == null) {
            return {'success': false, 'error': 'Failed to get session token'};
          }

          await _saveSessionToken(sessionToken);
          await _fetchAndSaveUserData(sessionToken);

          return {
            'success': true,
            'sessionToken': sessionToken,
          };
        }
      }

      return {'success': false, 'error': 'Invalid verification code'};
    } catch (e) {
      if (kDebugMode) print('2FA verification error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign up with email and password
  ///
  /// Returns a Map with:
  /// - 'success': bool
  /// - 'userId': String? (Clerk user ID)
  /// - 'error': String? (if failed)
  Future<Map<String, dynamic>> signUpWithEmailPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      await initialize();

      // Call backend endpoint to create user in Clerk
      final response = await http.post(
        Uri.parse('${ClerkConfig.backendUrl}/auth/clerk-signup'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
        }),
      );

      if (kDebugMode) {
        print('Sign up response status: ${response.statusCode}');
        print('Sign up response body: ${response.body}');
      }

      if (response.statusCode == 201) {
        final data = json.decode(response.body);

        return {
          'success': true,
          'userId': data['userId'],
          'message': data['message'],
        };
      } else {
        final error = json.decode(response.body);
        return {
          'success': false,
          'error': error['message'] ?? 'Sign up failed',
        };
      }
    } catch (e) {
      if (kDebugMode) print('Sign up error: $e');
      return {'success': false, 'error': 'Network error: ${e.toString()}'};
    }
  }

  /// Verify email with code
  ///
  /// Call this after signUpWithEmailPassword
  Future<Map<String, dynamic>> verifyEmail(String signUpId, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ClerkConfig.clerkFrontendApi}/v1/client/sign_ups/$signUpId/attempt_verification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'strategy': 'email_code',
          'code': code,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final signUpData = data['response'] ?? data;

        if (signUpData['status'] == 'complete') {
          final sessionToken = signUpData['created_session_id'];

          if (sessionToken == null) {
            return {'success': false, 'error': 'Failed to get session token'};
          }

          await _saveSessionToken(sessionToken);
          await _fetchAndSaveUserData(sessionToken);

          return {
            'success': true,
            'sessionToken': sessionToken,
          };
        }
      }

      return {'success': false, 'error': 'Invalid verification code'};
    } catch (e) {
      if (kDebugMode) print('Email verification error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign out
  ///
  /// Revokes session with Clerk and clears local storage
  Future<bool> signOut() async {
    try {
      await initialize();

      final sessionToken = await getSessionToken();

      // Call backend to revoke session
      if (sessionToken != null) {
        try {
          await http.post(
            Uri.parse('${ClerkConfig.backendUrl}${ClerkConfig.clerkLogoutEndpoint}'),
            headers: {
              'Authorization': 'Bearer $sessionToken',
              'Content-Type': 'application/json',
            },
          );
        } catch (e) {
          if (kDebugMode) print('Failed to revoke session on backend: $e');
        }
      }

      // Clear local storage
      await _clearSession();

      return true;
    } catch (e) {
      if (kDebugMode) print('Sign out error: $e');
      return false;
    }
  }

  /// Get current session token from local storage
  Future<String?> getSessionToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(ClerkConfig.sessionTokenKey);
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getSessionToken();
    if (token == null) return false;

    // Optionally verify token with backend
    try {
      final response = await http.get(
        Uri.parse('${ClerkConfig.backendUrl}${ClerkConfig.authMeEndpoint}'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Get current user data from local storage
  Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataJson = prefs.getString(ClerkConfig.userDataKey);

    if (userDataJson == null) return null;

    return json.decode(userDataJson) as Map<String, dynamic>;
  }

  // ===================
  // PRIVATE HELPERS
  // ===================

  /// Save session token to local storage
  Future<void> _saveSessionToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(ClerkConfig.sessionTokenKey, token);
  }

  /// Fetch user data from backend and save to local storage
  Future<void> _fetchAndSaveUserData(String sessionToken) async {
    try {
      final response = await http.get(
        Uri.parse('${ClerkConfig.backendUrl}${ClerkConfig.authMeEndpoint}'),
        headers: {
          'Authorization': 'Bearer $sessionToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final userData = data['user'];

        // Save to local storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(ClerkConfig.userDataKey, json.encode(userData));
      }
    } catch (e) {
      if (kDebugMode) print('Failed to fetch user data: $e');
    }
  }

  /// Clear session data from local storage
  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(ClerkConfig.sessionTokenKey);
    await prefs.remove(ClerkConfig.userDataKey);
  }
}
