import 'dart:async';
import 'dart:convert';
import 'package:client/models/message.dart';
import 'package:client/services/auth.dart';
import 'package:client/services/api_service.dart';
import 'package:http/http.dart' as http;

class ChatService {
  final String baseUrl = 'http://localhost:3000';
  final ApiService _apiService;

  String? _conversationId;
  String? _friendId;
  String? _currentUserId;

  final StreamController<Message> _messageController = StreamController<Message>.broadcast();
  final StreamController<Map<String, dynamic>> _typingController = StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _readReceiptController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Message> get messageStream => _messageController.stream;
  Stream<Map<String, dynamic>> get typingStream => _typingController.stream;
  Stream<Map<String, dynamic>> get readReceiptStream => _readReceiptController.stream;

  Timer? _typingTimer;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _readReceiptSubscription;

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
  }

  // Send a message via REST API
  Future<Map<String, dynamic>> sendMessage(String text) async {
    final token = await AuthService.getToken();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages/send'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'receiverId': _friendId,
          'message': text,
          'messageType': 'text',
        }),
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
  void handleNewMessage(Map<String, dynamic> data) {
    try {
      final message = Message.fromJson(data);
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

  void dispose() {
    _messageSubscription?.cancel();
    _typingSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _messageController.close();
    _typingController.close();
    _readReceiptController.close();
    _typingTimer?.cancel();
  }
}
