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
  final StreamController<Map<String, dynamic>> _newMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _typingIndicatorController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _readReceiptController = StreamController<Map<String, dynamic>>.broadcast();


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
  Stream<Map<String, dynamic>> get newMessageStream => _newMessageController.stream;
  Stream<Map<String, dynamic>> get typingIndicatorStream => _typingIndicatorController.stream;
  Stream<Map<String, dynamic>> get readReceiptStream => _readReceiptController.stream;
  
  void connectWebSocket(String? uuid) async {
    final token = await AuthService.getToken();
    if (token == null) {
      print('WebSocket: No token available, cannot connect');
      return;
    }

    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'auth': {'token': token}, // Use auth field for JWT
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
    });

    _socket!.connect();

    _socket!.onConnect((_) {
      print('WebSocket: Connected successfully');
      // No need to manually register - backend auto-registers with JWT userId
    });

    // Listen for registration confirmation
    _socket!.on("registered", (data) {
      print('WebSocket: Registered - ${data['success']}');
      if (data['queuedNotifications'] != null && data['queuedNotifications'] > 0) {
        print('WebSocket: Received ${data['queuedNotifications']} queued notifications');
      }
    });

    // Listen for chat registration confirmation
    _socket!.on("chatRegistered", (data) {
      print('WebSocket: Chat Registered - ${data['success']}');
      if (data['queuedMessages'] != null && data['queuedMessages'] > 0) {
        print('WebSocket: Received ${data['queuedMessages']} queued messages');
      }
    });

    // Listen for new messages
    _socket!.on("newMessage", (data) {
      if (kDebugMode) {
        print('WebSocket: New message received - ${data['messageId']}');
      }
      _newMessageController.add(Map<String, dynamic>.from(data));
    });

    // Listen for typing indicators
    _socket!.on("typingIndicator", (data) {
      if (kDebugMode) {
        print('WebSocket: Typing indicator - ${data['userId']} is ${data['isTyping'] ? 'typing' : 'not typing'}');
      }
      _typingIndicatorController.add(Map<String, dynamic>.from(data));
    });

    // Listen for read receipts
    _socket!.on("readReceipt", (data) {
      if (kDebugMode) {
        print('WebSocket: Read receipt - Conversation ${data['conversationId']} read up to ${data['lastReadSequenceId']}');
      }
      _readReceiptController.add(Map<String, dynamic>.from(data));
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

    _socket!.onReconnect((data) {
      print('WebSocket: Reconnected after ${data} attempts');
    });

    _socket!.onDisconnect((_) {
      print('WebSocket: Disconnected');
    });

    _socket!.onConnectError((error) {
      print('WebSocket: Connection error - $error');
    });
  }

  void disconnectWebSocket() {
    _socket?.disconnect();
  }

  // Send typing indicator via socket
  void sendTypingIndicator(String conversationId, bool isTyping) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('typing', {
        'conversationId': conversationId,
        'isTyping': isTyping,
      });
    }
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

  Future<List<Map<String, dynamic>>> fetchFriends({status = 'accepted'}) async {
    // Skip lastFetched to always get full friend list
    final String apiUrl = '$baseUrl/friends/list?status=$status';
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

  Future<dynamic> searchUsers(String query) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/friends/search?q=$query'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return json.decode(response.body)['users'];
      }

      return [];
    } catch (error) {
      if (kDebugMode) {
        print('Error fetching pending requests: $error');
      }
    }
  }

  void sendFriendRequest(String friendId, String uuid) async {
    final url = Uri.parse('$baseUrl/friends/send-request');

    final body = json.encode({
      'friendId': friendId,
      'userId': uuid
    });

    try {
      final token = await AuthService.getToken();
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );

      if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        if (kDebugMode) {
          print("${errorData['message']}");
        }
      } else {
        if (kDebugMode) {
          print("${response.statusCode}, ${response.body}");
        }
      }
    } catch (error) {
      if (kDebugMode) {
        print("Error sending friend request: $error");
      }
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
    _newMessageController.close();
    _typingIndicatorController.close();
    _readReceiptController.close();
  }
}
