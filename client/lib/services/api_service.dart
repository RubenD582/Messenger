// ignore_for_file: library_prefixes

import 'dart:async';
import 'dart:convert';
import 'package:client/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'auth.dart';

class ApiService {
  final String baseUrl = 'http://localhost:3000';
  IO.Socket? _socket;
  String? uuid;

  final StreamController<int> _pendingFriendRequestsController = StreamController<int>.broadcast();


  Future<void> init(String? uuid) async {
    this.uuid = uuid;

    connectWebSocket(this.uuid);
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////
  //
  // CONNECT WEB SOCKETS
  //
  //////////////////////////////////////////////////////////////////////////////////////////////////

  Stream<int> get pendingRequestsStream => _pendingFriendRequestsController.stream;
  
  void connectWebSocket(String? uuid) async {
    final token = await AuthService.getToken();
    if (token == null) {
      // TODO: Handle token retrieval failure
      return;
    }

    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'extraHeaders': {'Authorization': 'Bearer $token'},
    });

    _socket!.connect();

    _socket!.onConnect((_) {
      if (uuid != null) {
        _socket!.emit("register", uuid);
      }
    });

    _socket!.on("newFriendRequest", (data) {
      int friendRequestCount = int.tryParse(data['requestCount'].toString()) ?? 0;

      NotificationService.showNotification(
        title: 'Friend Request',
        body: '${data['senderName']} has sent you a friend request.'
      );
      
      // Add the updated count to the StreamController
      _pendingFriendRequestsController.add(friendRequestCount);
    });
    
    _socket!.on("friendRequestAccepted", (data) {
      // If friendId is your uuid, then the other person accepted your friend request
      if (data['friendId'] == uuid) {
        NotificationService.showNotification(
          title: 'New friend',
          body: '${data['friendName']} accepted your friend request!'
        );
      } else {
        int friendRequestCount = int.tryParse(data['requestCount'].toString()) ?? 0;

        // Add the updated count to the StreamController
        _pendingFriendRequestsController.add(friendRequestCount);
      }
    });


    _socket!.onDisconnect((_) {
      // Handle disconnection
    });
  }

  void disconnectWebSocket() {
    _socket?.disconnect();
  }

  Future<List<Map<String, dynamic>>> fetchPendingFriendRequests() async {
    final String apiUrl = '$baseUrl/friends/pending-requests';
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['pendingRequests']);
    } else if (response.statusCode == 404) {
      return [];
    } else {
      throw Exception('Failed to load pending requests');
    }
  }

  Future<List<Map<String, dynamic>>> fetchFriends() async {
    String? lastFetchedTimestamp = await _getLastFetchedTimestamp();

    final String apiUrl = '$baseUrl/friends/list?lastFetched=$lastFetchedTimestamp';
    final token = await AuthService.getToken();

    final response = await http.get(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {      
      final data = json.decode(response.body);
      if (data['serverTimestamp'] != null) {
        await _saveLastFetchedTimestamp(data['serverTimestamp']);
      }
      
      return List<Map<String, dynamic>>.from(data['friends']);
    } else if (response.statusCode == 404) {
      return [];
    } else {
      throw Exception('Failed to load pending requests');
    }
  }

  Future<void> acceptFriendRequest(String friendId) async {
    final String apiUrl = '$baseUrl/friends/accept-request';
    final token = await AuthService.getToken();

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'friendId': friendId}),
    );

    if (response.statusCode != 200) {
      final responseBody = json.decode(response.body);
      throw Exception(responseBody['message'] ?? 'Failed to accept friend request');
    }
  }

  Future<int> getRequestCount() async {
    final String baseUrl = 'http://localhost:3000';
    final Uri url = Uri.parse('$baseUrl/friends/pending-requests/count');
    final token = await AuthService.getToken();

    try {
      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', 
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data['pendingCount'];
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error fetching pending requests: $error');
      }
    }

    return 0;
  }

  Future<void> _saveLastFetchedTimestamp(String timestamp) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${uuid}_lastFetchedTimestamp', timestamp);
  }

  Future<String?> _getLastFetchedTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('${uuid}_lastFetchedTimestamp');
  }

  void dispose() {
    _pendingFriendRequestsController.close();
  }
}
