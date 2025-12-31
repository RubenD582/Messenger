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

class KlipyClip {
  final String id;
  final String title;
  final String previewUrl;
  final String videoUrl; // Assuming videoUrl for clips
  final int width;
  final int height;

  KlipyClip({
    required this.id,
    required this.title,
    required this.previewUrl,
    required this.videoUrl,
    required this.width,
    required this.height,
  });

  factory KlipyClip.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      print('📖 KlipyClip.fromJson: Raw JSON input: $json');
    }

    final file = json['file'] as Map<String, dynamic>?;

    String? videoUrl;
    String? previewUrl;
    int width = 200;
    int height = 200;

    if (file != null) {
      final hd = file['hd'] as Map<String, dynamic>?;
      final md = file['md'] as Map<String, dynamic>?;

      if (hd != null) {
        // Assuming MP4 is the primary video format
        final mp4 = hd['mp4'] as Map<String, dynamic>?;

        if (mp4 != null) {
          videoUrl = mp4['url'] as String?;
          width = (mp4['width'] as num?)?.toInt() ?? 200;
          height = (mp4['height'] as num?)?.toInt() ?? 200;
        }
      }

      if (md != null) {
        final webp = md['webp'] as Map<String, dynamic>?; // Look for webp image preview
        final gif = md['gif'] as Map<String, dynamic>?;   // Look for gif image preview

        final previewFormat = webp ?? gif; // Prioritize webp

        if (previewFormat != null) {
          previewUrl = previewFormat['url'] as String?;
        }
      }
    }

    final parsedClip = KlipyClip(
      id: json['id']?.toString() ?? '',
      title: json['title'] as String? ?? 'Clip',
      previewUrl: previewUrl ?? videoUrl ?? '',
      videoUrl: videoUrl ?? '',
      width: width,
      height: height,
    );

    if (kDebugMode) {
      print('✨ KlipyClip.fromJson: Parsed Clip - ID: ${parsedClip.id}, Title: ${parsedClip.title}');
      print('   Preview URL: ${parsedClip.previewUrl}');
      print('   Video URL: ${parsedClip.videoUrl}');
      print('   Width: ${parsedClip.width}, Height: ${parsedClip.height}');
    }

    return parsedClip;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'previewUrl': previewUrl,
      'videoUrl': videoUrl,
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

  static Future<List<KlipyClip>> searchClips(String query, {int limit = 20}) async {
    try {
      final url = Uri.parse('${KlipyConfig.baseUrl}/${KlipyConfig.apiKey}${KlipyConfig.clipsSearchEndpoint}').replace(
        queryParameters: {
          'q': query,
          'per_page': limit.toString(),
          'locale': KlipyConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (kDebugMode) {
        print('✉️ KlipyService: Search clips response status: ${response.statusCode}');
        print('📄 KlipyService: Search clips response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == true && data['data'] != null) {
          final results = data['data']['data'] as List? ?? [];
          if (kDebugMode) {
            print('✅ KlipyService: Found ${results.length} clips.');
          }
          return results.map((json) => KlipyClip.fromJson(json)).toList();
        }
        if (kDebugMode) {
            print('⚠️ KlipyService: Search clips - API response "result" is not true or "data" is null.');
        }
        return [];
      } else {
        if (kDebugMode) {
            print('❌ KlipyService: Failed to search clips with status: ${response.statusCode}');
        }
        throw Exception('Failed to search clips: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ KlipyService: Error searching KLIPY clips: $e');
      }
      return [];
    }
  }

  static Future<List<KlipyClip>> getTrendingClips({int limit = 20}) async {
    try {
      final url = Uri.parse('${KlipyConfig.baseUrl}/${KlipyConfig.apiKey}${KlipyConfig.clipsTrendingEndpoint}').replace(
        queryParameters: {
          'per_page': limit.toString(),
          'locale': KlipyConfig.defaultLocale,
        },
      );

      final response = await http.get(url);

      if (kDebugMode) {
        print('✉️ KlipyService: Trending clips response status: ${response.statusCode}');
        print('📄 KlipyService: Trending clips response body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['result'] == true && data['data'] != null) {
          final results = data['data']['data'] as List? ?? [];
          if (kDebugMode) {
            print('✅ KlipyService: Found ${results.length} trending clips.');
          }
          return results.map((json) => KlipyClip.fromJson(json)).toList();
        }
        if (kDebugMode) {
            print('⚠️ KlipyService: Get trending clips - API response "result" is not true or "data" is null.');
        }
        return [];
      } else {
        if (kDebugMode) {
            print('❌ KlipyService: Failed to get trending clips with status: ${response.statusCode}');
        }
        throw Exception('Failed to get trending clips: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ KlipyService: Error getting trending KLIPY clips: $e');
      }
      return [];
    }
  }
}
