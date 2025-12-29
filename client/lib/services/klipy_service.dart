import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/klipy_config.dart';

class KlipySticker {
  final String id;
  final String title;
  final String previewUrl;
  final String stickerUrl;
  final int width;
  final int height;

  KlipySticker({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.stickerUrl,
    required this.width,
    required this.height,
  });

  factory KlipySticker.fromJson(Map<String, dynamic> json) {
    // KLIPY structure: { id, title, file: { hd: { gif, webp, webm, png }, md: {...} } }
    final file = json['file'] as Map<String, dynamic>?;

    String? stickerUrl;
    String? previewUrl;
    int width = 200;
    int height = 200;

    if (file != null) {
      // Use HD quality for main sticker
      final hd = file['hd'] as Map<String, dynamic>?;
      // Use MD quality for preview (smaller/faster)
      final md = file['md'] as Map<String, dynamic>?;

      if (hd != null) {
        // Prefer WebP (better compression & transparency), then GIF
        final webp = hd['webp'] as Map<String, dynamic>?;
        final gif = hd['gif'] as Map<String, dynamic>?;

        final mainFormat = webp ?? gif;

        if (mainFormat != null) {
          stickerUrl = mainFormat['url'] as String?;
          width = (mainFormat['width'] as num?)?.toInt() ?? 200;
          height = (mainFormat['height'] as num?)?.toInt() ?? 200;
        }
      }

      // Use MD quality for preview
      if (md != null) {
        final webp = md['webp'] as Map<String, dynamic>?;
        final gif = md['gif'] as Map<String, dynamic>?;

        final previewFormat = webp ?? gif;
        if (previewFormat != null) {
          previewUrl = previewFormat['url'] as String?;
        }
      }
    }

    return KlipySticker(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? 'Sticker',
      previewUrl: previewUrl ?? stickerUrl ?? '',
      stickerUrl: stickerUrl ?? '',
      width: width,
      height: height,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'previewUrl': previewUrl,
      'stickerUrl': stickerUrl,
      'width': width,
      'height': height,
    };
  }
}

class KlipyService {
  static Future<List<KlipySticker>> searchStickers(String query, {int limit = 20}) async {
    try {
      final url = Uri.parse('${KlipyConfig.baseUrl}/${KlipyConfig.apiKey}${KlipyConfig.searchEndpoint}').replace(
        queryParameters: {
          'q': query,
          'per_page': limit.toString(),
          'locale': KlipyConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // KLIPY returns: { "result": true, "data": {"data": [...], "current_page": 1, ...} }
        if (data['result'] == true && data['data'] != null) {
          final results = data['data']['data'] as List? ?? [];
          return results.map((json) => KlipySticker.fromJson(json)).toList();
        }
        return [];
      } else {
        throw Exception('Failed to search stickers: ${response.statusCode}');
      }
    } catch (e) {
      return [];
    }
  }

  static Future<List<KlipySticker>> getTrendingStickers({int limit = 20}) async {
    try {
      final url = Uri.parse('${KlipyConfig.baseUrl}/${KlipyConfig.apiKey}${KlipyConfig.trendingEndpoint}').replace(
        queryParameters: {
          'per_page': limit.toString(),
          'locale': KlipyConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // KLIPY returns: { "result": true, "data": {"data": [...], "current_page": 1, ...} }
        if (data['result'] == true && data['data'] != null) {
          final results = data['data']['data'] as List? ?? [];
          return results.map((json) => KlipySticker.fromJson(json)).toList();
        }
        return [];
      } else {
        throw Exception('Failed to get trending stickers: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting trending KLIPY stickers: $e');
      }
      return [];
    }
  }
}
