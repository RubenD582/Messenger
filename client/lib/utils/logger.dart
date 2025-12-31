import 'package:flutter/foundation.dart';

/// Production-safe logger that only logs in debug mode
/// and sanitizes sensitive data
class Logger {
  static void log(String message, {String? tag}) {
    if (kDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      print('$prefix$message');
    }
  }

  static void error(String message, {String? tag, Object? error}) {
    if (kDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      print('ERROR: $prefix$message');
      if (error != null) {
        print('Error details: $error');
      }
    }
  }

  static void warning(String message, {String? tag}) {
    if (kDebugMode) {
      final prefix = tag != null ? '[$tag] ' : '';
      print('WARNING: $prefix$message');
    }
  }

  /// Sanitize sensitive data for logging
  /// Shows only first/last 4 characters of tokens
  static String sanitizeToken(String? token) {
    if (token == null || token.isEmpty) return '[no token]';
    if (token.length <= 8) return '[token]';
    return '${token.substring(0, 4)}...${token.substring(token.length - 4)}';
  }
}
