// remix_service.dart - API service for daily remix feature
import 'dart:convert';
import 'dart:io';
import 'package:client/config/api_config.dart';
import 'package:client/models/remix.dart';
import 'package:client/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class RemixService {
  final String baseUrl = ApiConfig.baseUrl;

  // ============================================
  // GROUPS
  // ============================================

  /// Create a new remix group
  Future<RemixGroup> createGroup({
    required String name,
    required List<String> memberIds,
  }) async {
    final token = await AuthService.getToken();

    final response = await http.post(
      Uri.parse('$baseUrl/remixes/groups'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'name': name,
        'memberIds': memberIds,
      }),
    );

    if (response.statusCode == 201) {
      final data = json.decode(response.body);
      return RemixGroup.fromJson(data['group']);
    } else {
      throw Exception('Failed to create group: ${response.statusCode}');
    }
  }

  /// Get user's remix groups
  Future<List<RemixGroup>> getGroups() async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/remixes/groups'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List groups = data['groups'];
      return groups.map((g) => RemixGroup.fromJson(g)).toList();
    } else {
      throw Exception('Failed to fetch groups');
    }
  }

  /// Get group members
  Future<List<GroupMember>> getGroupMembers(String groupId) async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/remixes/groups/$groupId/members'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List members = data['members'];
      return members.map((m) => GroupMember.fromJson(m)).toList();
    } else {
      throw Exception('Failed to fetch members');
    }
  }

  // ============================================
  // POSTS
  // ============================================

  /// Create a new remix post with image
  Future<RemixPost> createPost({
    required String groupId,
    required File imageFile,
    String? theme,
  }) async {
    final token = await AuthService.getToken();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/remixes/posts'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    // Add image file
    final imageBytes = await imageFile.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'remix_image.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    // Add fields
    request.fields['groupId'] = groupId;
    if (theme != null) {
      request.fields['theme'] = theme;
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 201) {
      final data = json.decode(responseBody);
      return RemixPost.fromJson(data['post']);
    } else {
      throw Exception('Failed to create post: ${response.statusCode}');
    }
  }

  /// Get today's post for a group
  Future<RemixPost?> getTodayPost(String groupId) async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/remixes/posts/$groupId/today'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['post'] == null) return null;
      return RemixPost.fromJson(data['post']);
    } else {
      throw Exception('Failed to fetch today\'s post');
    }
  }

  /// Get post history for a group
  Future<List<RemixPost>> getPostHistory({
    required String groupId,
    int limit = 7,
    int offset = 0,
  }) async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse(
        '$baseUrl/remixes/posts/$groupId/history?limit=$limit&offset=$offset',
      ),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List posts = data['posts'];
      return posts.map((p) => RemixPost.fromJson(p)).toList();
    } else {
      throw Exception('Failed to fetch history');
    }
  }

  // ============================================
  // LAYERS
  // ============================================

  /// Add a photo layer to a post (merges and returns updated post)
  Future<RemixPost> addPhotoLayer({
    required String postId,
    required File imageFile,
    double positionX = 0.5,
    double positionY = 0.5,
    double scale = 1.0,
    double rotation = 0.0,
  }) async {
    final token = await AuthService.getToken();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/remixes/layers'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    // Add image file
    final imageBytes = await imageFile.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: 'layer_image.jpg',
        contentType: MediaType('image', 'jpeg'),
      ),
    );

    // Add fields
    request.fields['postId'] = postId;
    request.fields['layerType'] = 'photo';
    request.fields['positionX'] = positionX.toString();
    request.fields['positionY'] = positionY.toString();
    request.fields['scale'] = scale.toString();
    request.fields['rotation'] = rotation.toString();

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 201) {
      final data = json.decode(responseBody);
      return RemixPost.fromJson(data['post']);
    } else {
      throw Exception('Failed to add layer: ${response.statusCode}');
    }
  }

  /// Get all layers for a post
  Future<List<RemixLayer>> getLayers(String postId) async {
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse('$baseUrl/remixes/layers/$postId'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List layers = data['layers'];
      return layers.map((l) => RemixLayer.fromJson(l)).toList();
    } else {
      throw Exception('Failed to fetch layers');
    }
  }

  /// Delete a layer
  Future<void> deleteLayer(String layerId) async {
    final token = await AuthService.getToken();

    final response = await http.delete(
      Uri.parse('$baseUrl/remixes/layers/$layerId'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete layer');
    }
  }
}
