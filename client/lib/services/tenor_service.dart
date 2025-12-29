import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/tenor_config.dart';

class TenorGif {
  final String id;
  final String title;
  final String previewUrl; // Small preview
  final String gifUrl; // Full size GIF
  final int width;
  final int height;

  TenorGif({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.gifUrl,
    required this.width,
    required this.height,
  });

  factory TenorGif.fromJson(Map<String, dynamic> json) {
    final mediaFormats = json['media_formats'] as Map<String, dynamic>;

    // Use tinygif for preview (smaller, faster loading)
    final tinygif = mediaFormats['tinygif'] as Map<String, dynamic>?;
    final gif = mediaFormats['gif'] as Map<String, dynamic>;

    return TenorGif(
      id: json['id'] as String,
      title: json['title'] as String? ?? json['content_description'] as String? ?? 'GIF',
      previewUrl: tinygif?['url'] as String? ?? gif['url'] as String,
      gifUrl: gif['url'] as String,
      width: (gif['dims'][0] as num).toInt(),
      height: (gif['dims'][1] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'previewUrl': previewUrl,
      'gifUrl': gifUrl,
      'width': width,
      'height': height,
    };
  }
}

class TenorSticker {
  final String id;
  final String title;
  final String previewUrl; // Small preview
  final String stickerUrl; // Full size sticker
  final int width;
  final int height;

  TenorSticker({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.stickerUrl,
    required this.width,
    required this.height,
  });

  factory TenorSticker.fromJson(Map<String, dynamic> json) {
    final mediaFormats = json['media_formats'] as Map<String, dynamic>;

    // Try various transparent formats for stickers (in order of preference)
    final webpTransparent = mediaFormats['webp_transparent'] as Map<String, dynamic>?;
    final tinywebpTransparent = mediaFormats['tinywebp_transparent'] as Map<String, dynamic>?;
    final mediumwebpTransparent = mediaFormats['mediumwebp_transparent'] as Map<String, dynamic>?;
    final webp = mediaFormats['webp'] as Map<String, dynamic>?;
    final tinywebp = mediaFormats['tinywebp'] as Map<String, dynamic>?;
    final gif = mediaFormats['gif'] as Map<String, dynamic>?;
    final tinygif = mediaFormats['tinygif'] as Map<String, dynamic>?;

    // Debug: Print available formats
    if (kDebugMode) {
      print('🎨 STICKER FORMATS for ${json['id']}: ${mediaFormats.keys.toList()}');
    }

    // Use the best available transparent format
    final mainFormat = webpTransparent ??
                       mediumwebpTransparent ??
                       tinywebpTransparent ??
                       webp ??
                       tinywebp ??
                       gif ??
                       mediaFormats['gif'] as Map<String, dynamic>;
    final previewFormat = tinywebpTransparent ??
                          tinywebp ??
                          tinygif ??
                          webpTransparent ??
                          webp ??
                          gif ??
                          mainFormat;

    return TenorSticker(
      id: json['id'] as String,
      title: json['title'] as String? ?? json['content_description'] as String? ?? 'Sticker',
      previewUrl: previewFormat['url'] as String,
      stickerUrl: mainFormat['url'] as String,
      width: (mainFormat['dims'][0] as num).toInt(),
      height: (mainFormat['dims'][1] as num).toInt(),
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

class TenorService {
  static Future<List<TenorGif>> searchGifs(String query, {int limit = 20}) async {
    try {
      final url = Uri.parse('${TenorConfig.baseUrl}${TenorConfig.searchEndpoint}').replace(
        queryParameters: {
          'key': TenorConfig.apiKey,
          'q': query,
          'limit': limit.toString(),
          'media_filter': TenorConfig.defaultMediaFilter,
          'locale': TenorConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((json) => TenorGif.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search GIFs: ${response.statusCode}');
      }
    } catch (e) {
      print('Error searching GIFs: $e');
      return [];
    }
  }

  static Future<List<TenorGif>> getTrendingGifs({int limit = 20}) async {
    try {
      final url = Uri.parse('${TenorConfig.baseUrl}${TenorConfig.trendingEndpoint}').replace(
        queryParameters: {
          'key': TenorConfig.apiKey,
          'limit': limit.toString(),
          'media_filter': TenorConfig.defaultMediaFilter,
          'locale': TenorConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((json) => TenorGif.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get trending GIFs: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting trending GIFs: $e');
      return [];
    }
  }

  static Future<List<TenorSticker>> searchStickers(String query, {int limit = 20}) async {
    try {
      final url = Uri.parse('${TenorConfig.baseUrl}${TenorConfig.searchEndpoint}').replace(
        queryParameters: {
          'key': TenorConfig.apiKey,
          'q': query,
          'limit': limit.toString(),
          'searchfilter': 'sticker',
          'media_filter': TenorConfig.defaultMediaFilter,
          'locale': TenorConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((json) => TenorSticker.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search stickers: ${response.statusCode}');
      }
    } catch (e) {
      print('Error searching stickers: $e');
      return [];
    }
  }

  static Future<List<TenorSticker>> getTrendingStickers({int limit = 20}) async {
    try {
      final url = Uri.parse('${TenorConfig.baseUrl}${TenorConfig.trendingEndpoint}').replace(
        queryParameters: {
          'key': TenorConfig.apiKey,
          'limit': limit.toString(),
          'searchfilter': 'sticker',
          'media_filter': TenorConfig.defaultMediaFilter,
          'locale': TenorConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((json) => TenorSticker.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get trending stickers: ${response.statusCode}');
      }
    } catch (e) {
      print('Error getting trending stickers: $e');
      return [];
    }
  }
}
