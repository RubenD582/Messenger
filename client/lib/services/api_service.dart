// ignore_for_file: library_prefixes

import 'dart:async';
import 'dart:convert';
import 'package:client/config/api_config.dart';
import 'package:client/services/notification_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:http/http.dart' as http;
import 'auth.dart';

class ApiService {
  final String baseUrl = ApiConfig.baseUrl;
  IO.Socket? _socket;
  String? uuid;

  final StreamController<int> _pendingFriendRequestsController = StreamController<int>.broadcast();
  final StreamController<Map<String, dynamic>> _newMessageController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _typingIndicatorController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _readReceiptController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _positionUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  // Callback for when WebSocket reconnects
  Function()? onReconnected;

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
  Stream<Map<String, dynamic>> get positionUpdateStream => _positionUpdateController.stream;
  
  void connectWebSocket(String? uuid) async {
    _socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      // Use callback function to get fresh token on each connection attempt
      'auth': (callback) async {
        final token = await AuthService.getToken();
        if (token == null || token.isEmpty) {
          print('WebSocket: No token available, cannot connect');
          callback({'token': ''});
          return;
        }
        if (kDebugMode) {
          print('WebSocket: Using fresh token for authentication');
        }
        callback({'token': token});
      },
      'reconnection': true,
      'reconnectionAttempts': 10,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
    });

    _socket!.connect();

    _socket!.onConnect((_) {
      if (kDebugMode) {
        print('🟢 WebSocket: Connected successfully');
        print('   Socket ID: ${_socket!.id}');
        print('   User UUID: $uuid');
      }
      // No need to manually register - backend auto-registers with JWT userId
    });

    // Listen for registration confirmation
    _socket!.on("registered", (data) {
      if (kDebugMode) {
        print('✅ WebSocket: Friend socket registered - ${data['success']}');
        if (data['queuedNotifications'] != null && data['queuedNotifications'] > 0) {
          print('   📬 Received ${data['queuedNotifications']} queued notifications');
        }
      }
    });

    // Listen for chat registration confirmation
    _socket!.on("chatRegistered", (data) {
      if (kDebugMode) {
        print('✅ WebSocket: Chat registered - ${data['success']}');
        if (data['queuedMessages'] != null && data['queuedMessages'] > 0) {
          print('   📬 Received ${data['queuedMessages']} queued messages');
        }
      }
    });

    // Listen for new messages
    _socket!.on("newMessage", (data) {
      if (kDebugMode) {
        print('📨 WebSocket: New message received');
        print('   Message ID: ${data['messageId']}');
        print('   Conversation ID: ${data['conversationId']}');
        print('   Sender ID: ${data['senderId']}');
        print('   Receiver ID: ${data['receiverId']}');
        print('   Sequence ID: ${data['sequenceId']}');
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

    // Listen for message position updates
    _socket!.on("messagePositionUpdate", (data) {
      if (kDebugMode) {
        print('WebSocket: Position update - Message ${data['messageId']} moved to (${data['positionX']}, ${data['positionY']})');
      }
      _positionUpdateController.add(Map<String, dynamic>.from(data));
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
      if (kDebugMode) {
        print('🔄 WebSocket: Reconnected after $data attempts');
      }
      // Trigger reconnection callback if set
      onReconnected?.call();
    });

    _socket!.onReconnectAttempt((attemptNumber) {
      if (kDebugMode) {
        print('🔄 WebSocket: Reconnection attempt #$attemptNumber');
      }
    });

    _socket!.onReconnectError((error) {
      if (kDebugMode) {
        print('❌ WebSocket: Reconnection error - $error');
      }
    });

    _socket!.onReconnectFailed((_) {
      if (kDebugMode) {
        print('❌ WebSocket: Reconnection failed after max attempts');
      }
    });

    _socket!.onDisconnect((_) {
      if (kDebugMode) {
        print('🔴 WebSocket: Disconnected');
      }
    });

    _socket!.onConnectError((error) {
      if (kDebugMode) {
        print('❌ WebSocket: Connection error - $error');
      }

      // Check if error is related to JWT expiration
      if (error.toString().contains('jwt expired') || error.toString().contains('authentication failed')) {
        if (kDebugMode) {
          print('🔐 WebSocket: JWT token expired - user needs to re-login');
        }
        // You could emit an event here to trigger a re-login UI
      }
    });

    _socket!.onError((error) {
      if (kDebugMode) {
        print('❌ WebSocket: Socket error - $error');
      }
    });
  }

  // Get connection status
  bool get isConnected => _socket?.connected ?? false;

  // Get socket ID for debugging
  String? get socketId => _socket?.id;

  // Manual reconnect
  void reconnect() {
    if (kDebugMode) {
      print('🔄 Manually reconnecting WebSocket...');
    }
    _socket?.disconnect();
    _socket?.connect();
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

  // Send message position update via socket
  void sendMessagePositionUpdate({
    required String messageId,
    required String conversationId,
    required double positionX,
    required double positionY,
    required bool isPositioned,
    double? rotation,
    double? scale,
  }) {
    if (_socket != null && _socket!.connected) {
      final data = {
        'messageId': messageId,
        'conversationId': conversationId,
        'positionX': positionX,
        'positionY': positionY,
        'isPositioned': isPositioned,
      };

      // Add rotation and scale if provided
      if (rotation != null) data['rotation'] = rotation;
      if (scale != null) data['scale'] = scale;

      _socket!.emit('updateMessagePosition', data);

      if (kDebugMode) {
        print('WebSocket: Sent position update for message $messageId to ($positionX, $positionY), rotation: $rotation, scale: $scale');
      }
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
    _positionUpdateController.close();
  }
}
