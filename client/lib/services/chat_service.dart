import 'dart:async';
import 'dart:convert';
import 'package:client/config/api_config.dart';
import 'package:client/database/message_database.dart';
import 'package:client/models/message.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/api_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ChatService {
  final String baseUrl = ApiConfig.baseUrl;
  final ApiService _apiService;

  String? _conversationId;
  String? _friendId;
  String? _currentUserId;

  final StreamController<Message> _messageController = StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _readReceiptController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _positionUpdateController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get readReceiptStream => _readReceiptController.stream;
  Stream<Map<String, dynamic>> get positionUpdateStream => _positionUpdateController.stream;

  Timer? _typingTimer;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _readReceiptSubscription;
  StreamSubscription? _positionUpdateSubscription;

  ChatService(this._apiService);

  void init(String conversationId, String friendId, String currentUserId) {
    _conversationId = conversationId;
    _friendId = friendId;
    _currentUserId = currentUserId;

    // Subscribe to global message streams and filter by conversation
    _messageSubscription = _apiService.newMessageStream.listen((data) {
      if (data['conversationId'] == _conversationId) {
        handleNewMessage(data);
      }
    });

    _typingSubscription = _apiService.typingIndicatorStream.listen((data) {
      if (data['conversationId'] == _conversationId) {
        handleTypingIndicator(data);
      }
    });

    _readReceiptSubscription = _apiService.readReceiptStream.listen((data) {
      if (data['conversationId'] == _conversationId) {
        handleReadReceipt(data);
      }
    });

    _positionUpdateSubscription = _apiService.positionUpdateStream.listen((data) {
      if (data['conversationId'] == _conversationId) {
        handlePositionUpdate(data);
      }
    });
  }

  // Send a message via REST API
  Future<Map<String, dynamic>> sendMessage(String text, {String? messageType, Map<String, dynamic>? metadata}) async {
    final token = await AuthService.getToken();

    try {
      final Map<String, dynamic> body = {
        'receiverId': _friendId,
        'message': text,
        'messageType': messageType ?? 'text',
      };

      // Add metadata if provided
      if (metadata != null) {
        body['metadata'] = metadata;
      }

      final response = await http.post(
        Uri.parse('$baseUrl/messages/send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode(body),
      );

      if (response.statusCode == 202) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (error) {
      print('Error sending message: $error');
      rethrow;
    }
  }

  // Send a drawing message via REST API
  Future<Map<String, dynamic>> sendDrawingMessage({
    required String receiverId,
    required Map<String, dynamic> metadata,
    required double positionX,
    required double positionY,
  }) async {
    final token = await AuthService.getToken();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'receiverId': receiverId,
          'message': 'Drawing',
          'messageType': 'drawing',
          'metadata': metadata,
          'positionX': positionX,
          'positionY': positionY,
          'isPositioned': true,
        }),
      );

      if (response.statusCode == 202) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to send drawing: ${response.statusCode}');
      }
    } catch (error) {
      print('Error sending drawing: $error');
      rethrow;
    }
  }

  // Fetch message history with pagination
  Future<Map<String, dynamic>> fetchHistory({int? beforeSequence, int limit = 50}) async {
    final token = await AuthService.getToken();

    try {
      String url = '$baseUrl/messages/history/$_conversationId?limit=$limit';
      if (beforeSequence != null) {
        url += '&beforeSequence=$beforeSequence';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final messages = (data['messages'] as List)
            .map((m) => Message.fromJson(m))
            .toList();

        return {
          'messages': messages,
          'hasMore': data['hasMore'] ?? false,
        };
      } else {
        throw Exception('Failed to fetch messages: ${response.statusCode}');
      }
    } catch (error) {
      print('Error fetching messages: $error');
      rethrow;
    }
  }

  // Mark messages as read
  Future<void> markAsRead(int lastSequenceId) async {
    final token = await AuthService.getToken();

    try {
      await http.post(
        Uri.parse('$baseUrl/messages/mark-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'conversationId': _conversationId,
          'lastReadSequenceId': lastSequenceId,
        }),
      );
    } catch (error) {
      print('Error marking as read: $error');
    }
  }

  // Get unread message count
  Future<int> getUnreadCount() async {
    final token = await AuthService.getToken();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/messages/unread-count'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['unreadCount'] ?? 0;
      } else {
        return 0;
      }
    } catch (error) {
      print('Error getting unread count: $error');
      return 0;
    }
  }

  // Handle incoming message from WebSocket
  void handleNewMessage(Map<String, dynamic> data) async {
    try {
      final message = Message.fromJson(data);

      // If this is a "chat cleared" system message, delete all local messages first
      if (message.messageType == 'system' &&
          message.metadata?['action'] == 'chat_cleared') {
        // Clear all local messages for this conversation
        // IMPORTANT: Skip server call to avoid infinite loop
        await MessageDatabase.deleteConversation(
          _conversationId!,
          skipServerCall: true,
        );
        print('🗑️ Conversation cleared locally due to system message');
      }

      _messageController.add(message);
    } catch (error) {
      print('Error handling new message: $error');
    }
  }

  // Handle typing indicator from WebSocket
  void handleTypingIndicator(Map<String, dynamic> data) {
    _typingController.add(data);
  }

  // Handle read receipt from WebSocket
  void handleReadReceipt(Map<String, dynamic> data) {
    _readReceiptController.add(data);
  }

  // Handle position update from WebSocket
  void handlePositionUpdate(Map<String, dynamic> data) {
    _positionUpdateController.add(data);
  }

  // Send typing indicator via socket
  void sendTypingIndicator(bool isTyping) {
    if (_conversationId != null) {
      _apiService.sendTypingIndicator(_conversationId!, isTyping);

      // Auto-stop typing after 3 seconds of inactivity
      _typingTimer?.cancel();
      if (isTyping) {
        _typingTimer = Timer(const Duration(seconds: 3), () {
          _apiService.sendTypingIndicator(_conversationId!, false);
        });
      }
    }
  }

  // Send message position update via socket
  void sendMessagePositionUpdate({
    required String messageId,
    required double positionX,
    required double positionY,
    required bool isPositioned,
    double? rotation,
    double? scale,
  }) {
    if (_conversationId != null) {
      _apiService.sendMessagePositionUpdate(
        messageId: messageId,
        conversationId: _conversationId!,
        positionX: positionX,
        positionY: positionY,
        isPositioned: isPositioned,
        rotation: rotation,
        scale: scale,
      );
    }
  }

  void dispose() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _positionUpdateSubscription?.cancel();
    _messageController.close();
    _typingController.close();
    _readReceiptController.close();
    _positionUpdateController.close();
    _typingTimer?.cancel();
  }
}
