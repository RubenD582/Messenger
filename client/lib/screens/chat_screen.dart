import 'dart:ui';
import 'dart:async';

import 'package:client/database/message_database.dart';
import 'package:client/models/message.dart';
import 'package:client/screens/user_profile.dart';
import 'package:client/services/api_service.dart';
import 'package:client/services/auth.dart';
import 'package:client/services/chat_service.dart';
import 'package:client/services/chat_service_with_storage.dart';
import 'package:client/theme/colors.dart';
import 'package:client/theme/typography.dart';
import 'package:client/theme/spacing.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pull_down_button/pull_down_button.dart';
import 'package:client/widgets/gif_picker_sheet.dart';
import 'package:client/widgets/sticker_picker_sheet.dart';
import 'package:client/services/tenor_service.dart';
import 'package:fluttertoast/fluttertoast.dart';

class ChatScreen extends StatefulWidget {
  final String friendId;
  final String friendName;
  final String? friendProfilePicture;
  final String conversationId;
  final ApiService apiService;

  const ChatScreen({
    super.key,
    required this.friendId,
    required this.friendName,
    this.friendProfilePicture,
    required this.conversationId,
    required this.apiService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final ChatService _chatService;
  late final ChatServiceWithStorage _chatServiceWithStorage;

  List<Message> _messages = [];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _isTyping = false;
  String? _currentUserId;

  // Periodic sync timer
  Timer? _syncTimer;

  // Track messages that were just dragged locally (skip animation)
  final Set<String> _justDraggedMessages = {};

  // Stable viewport height (set once, doesn't change with keyboard)
  double? _stableViewportHeight;

  // Drawing mode state
  bool _isDrawingMode = false;
  List<DrawingStroke> _drawingStrokes = [];
  DrawingStroke? _currentStroke;
  Color _selectedColor = Colors.white;
  final _colorPageController = PageController();
  int _currentColorPage = 0;
  double _extraBottomSpace = 0; // Extra space at bottom for drawing

  // Debug mode state
  bool _isDebugging = false;

  // Drag state for smooth dragging without rebuilds
  String? _draggingMessageId;
  Offset _dragOffset = Offset.zero;
  Offset _dragStartPosition = Offset.zero;
  bool _isDraggingActive = false; // Track if we're actively dragging

  // Transform state for rotation and scaling
  String? _transformingMessageId;
  double _currentRotation = 0.0;
  double _currentScale = 1.0;
  double _baseRotation = 0.0;
  double _baseScale = 1.0;

  // Multi-touch pointer tracking
  Map<int, Offset> _activePointers = {};
  int? _firstPointerId; // The anchor finger (first finger that touched)
  double _initialDistance = 0.0;
  double _initialAngle = 0.0;

  // GlobalKey for the Stack containing messages
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _drawingAreaKey = GlobalKey();

  final List<List<Color>> _colorPages = [
    // Page 1: Bright colors
    [
      Colors.white,
      const Color(0xFF0099F7),
      const Color(0xFF51C23C),
      const Color(0xFFFFC841),
      const Color(0xFFFF8500),
      const Color(0xFFFF3250),
      const Color(0xFFB100C0),
    ],
    // Page 2: Pastel colors
    [
      const Color(0xFFFFB3BA),
      const Color(0xFFFFDFBA),
      const Color(0xFFFFFABA),
      const Color(0xFFBAFFC9),
      const Color(0xFFBAE1FF),
      const Color(0xFFE0BBE4),
      const Color(0xFFFFC8DD),
    ],
    // Page 3: Grey colors
    [
      const Color(0xFFFFFFFF),
      const Color(0xFFE0E0E0),
      const Color(0xFFBDBDBD),
      const Color(0xFF9E9E9E),
      const Color(0xFF757575),
      const Color(0xFF424242),
      const Color(0xFF212121),
    ],
  ];

  @override
  void initState() {
    super.initState();

    // Initialize chat service with the existing ApiService
    _chatService = ChatService(widget.apiService);

    _loadCurrentUser();
    _loadInitialMessages();

    // Start periodic background sync every 30 seconds to catch missed messages
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_isLoading) {
        _backgroundSync();
      }
    });

    // Setup reconnection handler - sync when WebSocket reconnects
    widget.apiService.onReconnected = () {
      if (mounted && !_isLoading) {
        if (kDebugMode) {
          print('🔄 WebSocket reconnected - syncing messages...');
        }
        _loadInitialMessages();
      }
    };

    // Add scroll listener for pagination
    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 100 && _hasMore && !_isLoading) {
        _loadMoreMessages();
      }
    });

    _chatService.messageStream.listen((message) async {
      if (kDebugMode) {
        print('📨 WebSocket message received: ${message.messageId}');
        print('   Sender: ${message.senderId}');
        print('   Receiver: ${message.receiverId}');
        print('   Conversation: ${message.conversationId}');
        print('   Sequence: ${message.sequenceId}');
      }

      // Check if this is a "chat cleared" system message
      final isChatCleared = message.messageType == 'system' &&
          message.metadata?['action'] == 'chat_cleared';

      if (isChatCleared) {
        // Clear all messages from UI immediately
        if (mounted) {
          setState(() {
            _messages.clear();
            if (kDebugMode) {
              print('🗑️ Cleared all messages from UI (chat cleared by other user)');
            }
          });
        }
      }

      // CRITICAL FIX: Save incoming WebSocket messages to local database
      // This ensures messages persist when navigating away and coming back
      try {
        await MessageDatabase.insertMessage(message);
        if (kDebugMode) {
          print('✅ Saved WebSocket message to local DB: ${message.messageId}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error saving WebSocket message to DB: $e');
        }
      }

      if (mounted) {
        setState(() {
          // Find if a message with the same ID or a temp ID already exists
          final index = _messages.indexWhere((m) => m.messageId == message.messageId);

          if (index != -1) {
            // Replace existing message (e.g., update status)
            _messages[index] = message;
            if (kDebugMode) {
              print('🔄 Updated existing message in UI');
            }
          } else {
            // Add new message if it doesn't exist
            _messages.add(message);
            if (kDebugMode) {
              print('➕ Added new message to UI');
            }
          }

          // Sort messages by sequence ID to maintain order
          _messages.sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
        });
        _scrollToBottom();
      }
    });

    // Listen for typing indicators
    _chatService.typingStream.listen((typingData) {
      if (typingData['userId'] == widget.friendId) {
        setState(() {
          _isTyping = typingData['isTyping'] ?? false;
        });
      }
    });

    // Listen for read receipts
    _chatService.readReceiptStream.listen((receipt) async {
      final lastReadSeq = receipt['lastReadSequenceId'];

      // Update local database
      try {
        await MessageDatabase.markAsRead(widget.conversationId, lastReadSeq);
        if (kDebugMode) {
          print('Marked messages as read in local DB up to sequence: $lastReadSeq');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error marking messages as read in DB: $e');
        }
      }

      setState(() {
        for (var msg in _messages) {
          if (msg.sequenceId <= lastReadSeq && msg.senderId == _currentUserId) {
            msg.isRead = true;
          }
        }
      });
    });

    // Listen for position updates
    _chatService.positionUpdateStream.listen((updateData) async {
      if (kDebugMode) {
        print('🔔 Position update stream event received!');
        print('   Data: $updateData');
      }

      final messageId = updateData['messageId'];
      final message = _messages.firstWhere((m) => m.messageId == messageId, orElse: () => _messages.first);
      final index = _messages.indexOf(message);

      if (kDebugMode) {
        print('   Message found at index: $index');
      }

      if (index != -1) {
        // Convert rotation and scale to double (they might come as int from JSON)
        double? rotation;
        if (updateData['rotation'] != null) {
          rotation = (updateData['rotation'] as num).toDouble();
        }

        double? scale;
        if (updateData['scale'] != null) {
          scale = (updateData['scale'] as num).toDouble();
        }

        final updatedMessage = message.copyWith(
          positionX: updateData['positionX'],
          positionY: updateData['positionY'],
          isPositioned: updateData['isPositioned'],
          positionedBy: updateData['positionedBy'],
          positionedAt: updateData['positionedAt'],
          rotation: rotation,
          scale: scale,
        );

        if (kDebugMode) {
          print('📍 Position update received for message $messageId:');
          print('   Position: (${updateData['positionX']}, ${updateData['positionY']})');
          print('   Rotation: ${updateData['rotation']} -> $rotation');
          print('   Scale: ${updateData['scale']} -> $scale');
          print('   Updated message rotation: ${updatedMessage.rotation}');
          print('   Updated message scale: ${updatedMessage.scale}');
        }

        // Save position update to local database
        try {
          await MessageDatabase.insertMessage(updatedMessage);
          if (kDebugMode) {
            print('Saved position update to local DB for message: $messageId');
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error saving position update to DB: $e');
          }
        }

        setState(() {
          _messages[index] = updatedMessage;
        });
      }
    }, onError: (error) {
      if (kDebugMode) {
        print('❌ Error in position update stream: $error');
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    final userId = await AuthService.getUserUuid();
    setState(() {
      _currentUserId = userId;
    });
  }

  Future<void> _loadInitialMessages() async {
    if (_currentUserId == null) {
      // Wait for current user to be loaded first
      await Future.delayed(const Duration(milliseconds: 100));
      if (_currentUserId == null) return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Initialize chat service with conversation details
      _chatService.init(widget.conversationId, widget.friendId, _currentUserId!);

      // Initialize ChatServiceWithStorage
      _chatServiceWithStorage = ChatServiceWithStorage(
        chatService: _chatService,
        conversationId: widget.conversationId,
        currentUserId: _currentUserId!,
        friendId: widget.friendId,
      );

      // Load messages (handles local DB + server sync automatically)
      final messages = await _chatServiceWithStorage.loadMessages();

      setState(() {
        _messages = messages;
        _isLoading = false;
        _hasMore = messages.length >= 50; // Assume more if we got a full page
      });

      if (kDebugMode) {
        print('✅ Loaded ${messages.length} messages');
        print('📱 Current user: $_currentUserId');
        print('👥 Conversation: ${widget.conversationId}');
        print('🔌 WebSocket connected: ${widget.apiService.isConnected}');
      }

      _scrollToBottom();
    } catch (error) {
      if (kDebugMode) {
        print('❌ Error loading initial messages: $error');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Background sync to catch any missed WebSocket messages
  Future<void> _backgroundSync() async {
    if (_chatServiceWithStorage == null) return;

    try {
      if (kDebugMode) {
        print('🔄 Running background sync...');
      }

      // Get latest sequence from current messages
      final latestSeq = _messages.isNotEmpty ? _messages.last.sequenceId : 0;

      // Fetch any new messages from server
      final newMessages = await MessageDatabase.getMessagesAfter(
        conversationId: widget.conversationId,
        afterSequence: latestSeq,
      );

      if (newMessages.isNotEmpty) {
        if (kDebugMode) {
          print('✅ Background sync found ${newMessages.length} new messages');
        }

        setState(() {
          _messages.addAll(newMessages);
          _messages.sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
        });

        _scrollToBottom();
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Background sync error: $e');
      }
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final oldestSequenceId = _messages.first.sequenceId;
      final olderMessages = await _chatServiceWithStorage.loadMoreMessages(oldestSequenceId);

      setState(() {
        _messages.insertAll(0, olderMessages);
        _hasMore = olderMessages.length >= 50; // Assume more if we got a full page
        _isLoading = false;
      });

      if (kDebugMode) {
        print('Loaded ${olderMessages.length} more messages');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error loading more messages: $error');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Clear controller immediately for snappy feel
    _messageController.clear();
    FocusScope.of(context).unfocus(); // Hide keyboard after sending

    // Send message (writes to local DB optimistically)
    await _chatServiceWithStorage.sendMessage(text);

    // Reload just the new message from DB to show optimistically
    final newMessages = await MessageDatabase.getMessagesAfter(
      conversationId: widget.conversationId,
      afterSequence: _messages.isNotEmpty ? _messages.last.sequenceId : 0,
    );

    if (mounted && newMessages.isNotEmpty) {
      setState(() {
        // Add only the new messages without replacing the entire list
        for (var msg in newMessages) {
          final exists = _messages.any((m) => m.messageId == msg.messageId);
          if (!exists) {
            _messages.add(msg);
          }
        }
        // Sort to maintain order
        _messages.sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
      });
      _scrollToBottom();
    }
  }

  String _getDateTimeLabel(String timestamp) {
    try {
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final messageDate = DateTime(messageTime.year, messageTime.month, messageTime.day);

      final hour = messageTime.hour;
      final minute = messageTime.minute.toString().padLeft(2, '0');
      final timeStr = hour == 0 ? '12:$minute AM'
        : hour < 12 ? '$hour:$minute AM'
        : hour == 12 ? '12:$minute PM'
        : '${hour - 12}:$minute PM';

      if (messageDate == today) {
        return 'Today at $timeStr';
      } else if (messageDate == yesterday) {
        return 'Yesterday at $timeStr';
      } else {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${months[messageTime.month - 1]} ${messageTime.day} at $timeStr';
      }
    } catch (e) {
      return '';
    }
  }

  // Check if two messages are within 5 minutes of each other
  bool _isWithinTimeCluster(Message message1, Message message2) {
    try {
      final time1 = DateTime.parse(message1.timestamp);
      final time2 = DateTime.parse(message2.timestamp);
      final difference = time2.difference(time1).abs();
      final withinCluster = difference.inMinutes < 5;

      if (kDebugMode) {
        print('Time cluster check: ${difference.inMinutes} minutes apart, within cluster: $withinCluster');
      }

      return withinCluster;
    } catch (e) {
      return false;
    }
  }

  // Calculate distance between two points
  double _calculateDistance(Offset p1, Offset p2) {
    return (p2 - p1).distance;
  }

  // Calculate angle between two points
  double _calculateAngle(Offset p1, Offset p2) {
    return (p2 - p1).direction;
  }

  Future<void> _sendDrawing() async {
    if (_drawingStrokes.isEmpty) return;

    try {
      // Convert strokes to JSON format
      final strokesJson = _drawingStrokes.map((stroke) {
        // Convert color to hex string (ARGB format)
        final colorHex = '#${stroke.color.toARGB32().toRadixString(16).padLeft(8, '0')}';
        return {
          'points': stroke.points.map((p) => [p.dx, p.dy]).toList(),
          'color': colorHex,
          'strokeWidth': 3.0,
        };
      }).toList();

      // Calculate bounds
      double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      for (var stroke in _drawingStrokes) {
        for (var point in stroke.points) {
          if (point.dx < minX) minX = point.dx;
          if (point.dx > maxX) maxX = point.dx;
          if (point.dy < minY) minY = point.dy;
          if (point.dy > maxY) maxY = point.dy;
        }
      }

      final metadata = {
        'strokes': strokesJson,
        'bounds': {
          'minX': minX,
          'minY': minY,
          'maxX': maxX,
          'maxY': maxY,
        },
      };

      // Calculate center position for the drawing
      final centerX = (minX + maxX) / 2;
      final centerY = (minY + maxY) / 2;

      // Send as a special drawing message via ChatServiceWithStorage
      await _chatServiceWithStorage.sendDrawingMessage(
        metadata: metadata,
        positionX: centerX,
        positionY: centerY,
      );

      // Clear drawing state
      setState(() {
        _isDrawingMode = false;
        _drawingStrokes.clear();
        _currentStroke = null;
      });

      if (kDebugMode) {
        print('Drawing sent with ${strokesJson.length} strokes');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error sending drawing: $error');
      }
    }
  }

  void _showGifPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => GifPickerSheet(
        onGifSelected: (gif) => _sendGif(gif),
      ),
    );
  }

  Future<void> _sendGif(TenorGif gif) async {
    try {
      // Create metadata for the GIF
      final metadata = {
        'type': 'gif',
        'gifId': gif.id,
        'gifUrl': gif.gifUrl,
        'previewUrl': gif.previewUrl,
        'title': gif.title,
        'width': gif.width,
        'height': gif.height,
      };

      // Send as a normal message (not positioned)
      // GIF can be positioned later by long-pressing it
      await _chatServiceWithStorage.sendMessage(
        'GIF', // Use simple text instead of title
        messageType: 'gif',
        metadata: metadata,
      );

      if (kDebugMode) {
        print('GIF sent: ${gif.title}');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error sending GIF: $error');
      }
    }
  }

  void _showStickerPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StickerPickerSheet(
        onStickerSelected: (sticker) => _sendSticker(sticker),
      ),
    );
  }

  Future<void> _sendSticker(TenorSticker sticker) async {
    try {
      if (kDebugMode) {
        print('🎨 SENDING STICKER:');
        print('  ID: ${sticker.id}');
        print('  URL: ${sticker.stickerUrl}');
        print('  Title: ${sticker.title}');
      }

      // Create metadata for the sticker
      final metadata = {
        'type': 'sticker',
        'stickerId': sticker.id,
        'stickerUrl': sticker.stickerUrl,
        'previewUrl': sticker.previewUrl,
        'title': sticker.title,
        'width': sticker.width,
        'height': sticker.height,
      };

      // Send as a normal message (not positioned)
      // Sticker can be positioned later by long-pressing it
      await _chatServiceWithStorage.sendMessage(
        'Sticker', // Use simple text instead of title
        messageType: 'sticker',
        metadata: metadata,
      );

      if (kDebugMode) {
        print('✅ Sticker sent successfully');
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error sending sticker: $error');
      }
    }
  }

  Future<void> _deleteAllMessages() async {
    try {
      // Soft delete from local database
      await MessageDatabase.deleteConversation(widget.conversationId, userId: _currentUserId);

      // Clear messages from UI
      setState(() {
        _messages.clear();
      });

      if (kDebugMode) {
        print('Soft-deleted all messages for conversation: ${widget.conversationId}');
      }

      // Show success message
      if (mounted) {
        Fluttertoast.showToast(
          msg: "All messages deleted",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.TOP,
          backgroundColor: const Color(0xFF212121),
          textColor: Colors.white,
          fontSize: 14.0,
        );
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error deleting messages: $error');
      }
      if (mounted) {
        Fluttertoast.showToast(
          msg: "Failed to delete messages",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.TOP,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 14.0,
        );
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Update message position (drag and drop)
  Future<void> _updateMessagePosition(
    Message message,
    double x,
    double y,
    double viewportWidth,
    double viewportHeight,
  ) async {
    // Convert pixel position to percentage
    // Allow slight overflow since we're positioning by center
    var percentX = x / viewportWidth;
    final percentY = y / viewportHeight;

    // Mirror X when positioning other user's messages
    // Store in sender's perspective so it appears correctly on both screens
    if (message.senderId != _currentUserId) {
      percentX = 1.0 - percentX;
    }

    // Update message in state
    final updatedMessage = message.copyWith(
      positionX: percentX,
      positionY: percentY,
      isPositioned: true,
      positionedBy: _currentUserId,
      positionedAt: DateTime.now().toIso8601String(),
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.messageId == message.messageId);
      if (index != -1) {
        _messages[index] = updatedMessage;
      }

      // Mark this message as just dragged (skip animation)
      _justDraggedMessages.add(message.messageId);
    });

    // Remove from set after next frame (so animation skips for this update only)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _justDraggedMessages.remove(message.messageId);
      });
    });

    // Save to local database
    try {
      await MessageDatabase.insertMessage(updatedMessage);

      if (kDebugMode) {
        print('Updated message position: ${message.messageId} to ($percentX, $percentY)');
      }

      // Sync to server via WebSocket
      _chatService.sendMessagePositionUpdate(
        messageId: message.messageId,
        positionX: percentX,
        positionY: percentY,
        isPositioned: true,
      );
    } catch (error) {
      if (kDebugMode) {
        print('Error updating message position: $error');
      }
    }
  }

  Future<void> _updateMessageTransform(
    Message message,
    double x,
    double y,
    double viewportWidth,
    double viewportHeight,
    double rotation,
    double scale,
  ) async {
    // Convert pixel position to percentage
    var percentX = x / viewportWidth;
    final percentY = y / viewportHeight;

    // Mirror X when positioning other user's messages
    if (message.senderId != _currentUserId) {
      percentX = 1.0 - percentX;
    }

    // Update message in state with position, rotation, and scale
    final updatedMessage = message.copyWith(
      positionX: percentX,
      positionY: percentY,
      isPositioned: true,
      positionedBy: _currentUserId,
      positionedAt: DateTime.now().toIso8601String(),
      rotation: rotation,
      scale: scale,
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.messageId == message.messageId);
      if (index != -1) {
        _messages[index] = updatedMessage;
      }

      // Mark this message as just dragged (skip animation)
      _justDraggedMessages.add(message.messageId);
    });

    // Remove from set after next frame (so animation skips for this update only)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _justDraggedMessages.remove(message.messageId);
      });
    });

    // Save to local database
    try {
      await MessageDatabase.insertMessage(updatedMessage);

      if (kDebugMode) {
        print('Updated message transform: ${message.messageId} to ($percentX, $percentY), rotation: $rotation, scale: $scale');
      }

      // Sync to server via WebSocket
      _chatService.sendMessagePositionUpdate(
        messageId: message.messageId,
        positionX: percentX,
        positionY: percentY,
        isPositioned: true,
        rotation: rotation,
        scale: scale,
      );
    } catch (error) {
      if (kDebugMode) {
        print('Error updating message transform: $error');
      }
    }
  }

  Widget _buildTimestampSeparator(String timestamp) {
    final messageTime = DateTime.parse(timestamp);
    final now = DateTime.now();
    final difference = now.difference(messageTime);

    String formattedTime;
    if (difference.inDays == 0) {
      // Today
      final hour = messageTime.hour.toString().padLeft(2, '0');
      final minute = messageTime.minute.toString().padLeft(2, '0');
      formattedTime = 'Today at $hour:$minute';
    } else if (difference.inDays == 1) {
      // Yesterday
      final hour = messageTime.hour.toString().padLeft(2, '0');
      final minute = messageTime.minute.toString().padLeft(2, '0');
      formattedTime = 'Yesterday at $hour:$minute';
    } else if (difference.inDays < 7) {
      // This week - show day name
      final weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      final dayName = weekdays[messageTime.weekday - 1];
      final hour = messageTime.hour.toString().padLeft(2, '0');
      final minute = messageTime.minute.toString().padLeft(2, '0');
      formattedTime = '$dayName at $hour:$minute';
    } else {
      // Older - show date
      final month = messageTime.month.toString().padLeft(2, '0');
      final day = messageTime.day.toString().padLeft(2, '0');
      final hour = messageTime.hour.toString().padLeft(2, '0');
      final minute = messageTime.minute.toString().padLeft(2, '0');
      formattedTime = '$month/$day at $hour:$minute';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            formattedTime,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leadingWidth: 40,
        toolbarHeight: 64,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            CupertinoIcons.chevron_left,
            color: Colors.white,
            size: 22,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const UserProfileScreen(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.surface,
                  backgroundImage: widget.friendProfilePicture != null
                      ? NetworkImage(widget.friendProfilePicture!)
                      : const AssetImage('assets/noprofile.png') as ImageProvider,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.friendName,
                        style: AppTypography.h3.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_isTyping)
                        Text(
                          'typing...',
                          style: AppTypography.caption.copyWith(
                            color: const Color(0xFF5856D6),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          PullDownButton(
            position: PullDownMenuPosition.automatic,
            itemBuilder: (context) => [
              PullDownMenuItem(
                onTap: () {
                  setState(() {
                    _isDebugging = !_isDebugging;
                  });
                },
                title: 'Debugging',
                icon: _isDebugging ? Icons.check_box : Icons.check_box_outline_blank,
              ),
              PullDownMenuItem(
                onTap: () {
                  // Debug WebSocket connection
                  if (kDebugMode) {
                    print('=== WebSocket Debug Info ===');
                    print('Connected: ${widget.apiService.isConnected}');
                    print('Socket ID: ${widget.apiService.socketId}');
                    print('User UUID: ${widget.apiService.uuid}');
                    print('Conversation ID: ${widget.conversationId}');
                    print('Current User ID: $_currentUserId');
                    print('Friend ID: ${widget.friendId}');
                    print('Messages count: ${_messages.length}');
                    print('===========================');
                  }

                  // Show connection status to user
                  Fluttertoast.showToast(
                    msg: 'WebSocket: ${widget.apiService.isConnected ? "Connected ✅" : "Disconnected ❌"}',
                    toastLength: Toast.LENGTH_LONG,
                    gravity: ToastGravity.TOP,
                    backgroundColor: widget.apiService.isConnected ? Colors.green : Colors.red,
                    textColor: Colors.white,
                    fontSize: 14.0,
                  );
                },
                title: 'WebSocket Status',
                icon: Icons.wifi,
              ),
              PullDownMenuItem(
                onTap: _deleteAllMessages,
                title: 'Delete Messages',
                isDestructive: true,
              ),
            ],
            buttonBuilder: (context, showMenu) => IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onPressed: showMenu,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Message list (everything scrolls together) - Full height
          GestureDetector(
              onTap: () {
                // Dismiss keyboard when tapping on messages area
                FocusScope.of(context).unfocus();
              },
              behavior: HitTestBehavior.translucent,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Separate messages into normal and positioned
                  final normalMessages = _messages.where((m) => !m.isPositioned).toList();
                  final positionedMessages = _messages.where((m) => m.isPositioned).toList();

                  // Capture stable viewport height on first build (keyboard hidden)
                  if (_stableViewportHeight == null || constraints.maxHeight > _stableViewportHeight!) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _stableViewportHeight = constraints.maxHeight;
                        });
                      }
                    });
                  }
                  final viewportHeight = _stableViewportHeight ?? constraints.maxHeight;
                  final viewportWidth = constraints.maxWidth;

                  // Calculate total content height needed
                  // This includes space for normal messages + positioned messages
                  double maxPositionedY = 0;
                  for (var msg in positionedMessages) {
                    final msgY = (msg.positionY ?? 0.5) * viewportHeight;
                    if (msgY > maxPositionedY) maxPositionedY = msgY;
                  }

                  // Estimate height needed (will be adjusted by Stack's intrinsic size)
                  final estimatedContentHeight = maxPositionedY + 200;

                  return SingleChildScrollView(
                    controller: _scrollController,
                    physics: (_isDraggingActive || _isDrawingMode || _transformingMessageId != null) ? const NeverScrollableScrollPhysics() : const AlwaysScrollableScrollPhysics(),
                    child: Listener(
                      // Global listener to track all pointers when transforming
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (details) {
                        if (_transformingMessageId != null) {
                          setState(() {
                            _activePointers[details.pointer] = details.position;
                            if (_activePointers.length == 2) {
                              final pointers = _activePointers.values.toList();
                              _initialDistance = _calculateDistance(pointers[0], pointers[1]);
                              _initialAngle = _calculateAngle(pointers[0], pointers[1]);
                            }
                          });
                        }
                      },
                      onPointerMove: (details) {
                        if (_transformingMessageId != null) {
                          setState(() {
                            _activePointers[details.pointer] = details.position;
                          });
                        }
                      },
                      onPointerUp: (details) {
                        if (_transformingMessageId != null) {
                          // Check if this is the last pointer BEFORE removing
                          final wasLastPointer = _activePointers.length == 1;

                          setState(() {
                            _activePointers.remove(details.pointer);

                            // If local listener didn't clear transform (pointer outside widget), clear it here
                            if (wasLastPointer && _activePointers.isEmpty && _transformingMessageId != null) {
                              _transformingMessageId = null;
                              _firstPointerId = null;
                              _dragOffset = Offset.zero;
                              _currentRotation = 0.0;
                              _currentScale = 1.0;
                              _initialDistance = 0.0;
                              _initialAngle = 0.0;
                            }
                          });
                        }
                      },
                      onPointerCancel: (details) {
                        if (_transformingMessageId != null) {
                          setState(() {
                            _activePointers.remove(details.pointer);
                            if (_activePointers.isEmpty) {
                              _transformingMessageId = null;
                              _firstPointerId = null;
                              _dragOffset = Offset.zero;
                              _currentRotation = 0.0;
                              _currentScale = 1.0;
                              _initialDistance = 0.0;
                              _initialAngle = 0.0;
                            }
                          });
                        }
                      },
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Stack(
                          key: _stackKey,
                          children: [
                          // Normal messages in a Column (flows naturally)
                          // Includes spacers for positioned messages to prevent overlap
                          Padding(
                            padding: EdgeInsets.only(
                              top: Spacing.md,
                              // When keyboard is open, add 50% screen height padding so user can scroll to see latest messages
                              bottom: MediaQuery.of(context).viewInsets.bottom > 0
                                  ? MediaQuery.of(context).size.height * 0.5
                                  : 100, // Extra padding so messages aren't hidden behind controls
                              left: 8,
                              right: 8,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_isLoading)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(Spacing.md),
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                // Build combined list with spacers for positioned messages
                                ...() {
                                  final List<Widget> items = [];

                                  // Add date/time label at the very top
                                  if (_messages.isNotEmpty) {
                                    items.add(
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.only(top: 4, bottom: 4),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade900.withOpacity(0),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              _getDateTimeLabel(_messages.first.timestamp),
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.7),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  int normalIndex = 0;

                                  // Track Y ranges already covered by spacers to avoid overlaps
                                  final List<Map<String, double>> spacerRanges = [];

                                  // Track actual accumulated height (not just count * 80)
                                  double accumulatedHeight = 0;

                                  for (int i = 0; i < _messages.length; i++) {
                                    final msg = _messages[i];

                                    if (msg.isPositioned) {
                                      // Get the Y position and height of this positioned message
                                      // For spacer calculation, always use the stored position (not drag offset)
                                      // This keeps spacers stable even when dragging the message again
                                      final msgY = (msg.positionY ?? 0.5) * viewportHeight;

                                      double msgHeight;
                                      if (msg.messageType == 'gif') {
                                        // For GIF messages, calculate height based on original dimensions
                                        final metadata = msg.metadata as Map<String, dynamic>?;
                                        final gifWidth = (metadata?['width'] as num?)?.toDouble() ?? 200.0;
                                        final gifHeight = (metadata?['height'] as num?)?.toDouble() ?? 200.0;

                                        final maxDisplayWidth = viewportWidth * 0.6;
                                        final maxDisplayHeight = viewportHeight * 0.4;

                                        double displayWidth = gifWidth;
                                        double displayHeight = gifHeight;

                                        // Scale down if too large
                                        if (displayWidth > maxDisplayWidth) {
                                          final scale = maxDisplayWidth / displayWidth;
                                          displayWidth = maxDisplayWidth;
                                          displayHeight = displayHeight * scale;
                                        }

                                        if (displayHeight > maxDisplayHeight) {
                                          final scale = maxDisplayHeight / displayHeight;
                                          displayHeight = maxDisplayHeight;
                                          displayWidth = displayWidth * scale;
                                        }

                                        msgHeight = displayHeight.clamp(100.0, maxDisplayHeight);
                                      } else if (msg.messageType == 'sticker') {
                                        // For sticker messages, calculate height based on original dimensions
                                        final metadata = msg.metadata as Map<String, dynamic>?;
                                        final stickerWidth = (metadata?['width'] as num?)?.toDouble() ?? 200.0;
                                        final stickerHeight = (metadata?['height'] as num?)?.toDouble() ?? 200.0;

                                        final maxDisplayWidth = viewportWidth * 0.5;
                                        final maxDisplayHeight = viewportHeight * 0.35;

                                        double displayWidth = stickerWidth;
                                        double displayHeight = stickerHeight;

                                        // Scale down if too large
                                        if (displayWidth > maxDisplayWidth) {
                                          final scale = maxDisplayWidth / displayWidth;
                                          displayWidth = maxDisplayWidth;
                                          displayHeight = displayHeight * scale;
                                        }

                                        if (displayHeight > maxDisplayHeight) {
                                          final scale = maxDisplayHeight / displayHeight;
                                          displayHeight = maxDisplayHeight;
                                          displayWidth = displayWidth * scale;
                                        }

                                        msgHeight = displayHeight.clamp(80.0, maxDisplayHeight);
                                      } else if (msg.messageType == 'drawing') {
                                        // For drawings, use bounds from metadata
                                        final metadata = msg.metadata as Map<String, dynamic>?;
                                        if (metadata != null && metadata['bounds'] != null) {
                                          final bounds = metadata['bounds'] as Map<String, dynamic>;
                                          final minY = (bounds['minY'] as num?)?.toDouble() ?? 0.0;
                                          final maxY = (bounds['maxY'] as num?)?.toDouble() ?? 0.1;
                                          final drawingHeight = (maxY - minY) * viewportHeight;
                                          msgHeight = drawingHeight.clamp(50.0, viewportHeight).toDouble();
                                        } else {
                                          msgHeight = 80;
                                        }
                                      } else {
                                        // For text messages, estimate height based on text length
                                        // Assume max width is 75% of screen, ~45 characters per line at 15px font
                                        final textLength = msg.message.length;
                                        final estimatedLines = (textLength / 45).ceil().clamp(1, 10);
                                        // Line height is ~21px (15px font * 1.4 line height), plus padding (16px top/bottom)
                                        msgHeight = (estimatedLines * 21.0) + 16;
                                      }

                                      // Store base (unscaled) height for locked spacers
                                      final baseHeight = msgHeight;

                                      // Apply scale factor to the message height for positioning
                                      final scale = msg.scale ?? 1.0;
                                      msgHeight = msgHeight * scale;

                                      final msgTopY = msgY - (msgHeight / 2);
                                      final msgBottomY = msgY + (msgHeight / 2);

                                      // Check if this Y range is already covered by an existing spacer
                                      final isAlreadyCovered = spacerRanges.any((range) {
                                        return msgTopY >= range['top']! && msgBottomY <= range['bottom']!;
                                      });

                                      if (!isAlreadyCovered) {
                                        // Use actual accumulated height instead of items.length * 80
                                        final estimatedCurrentY = accumulatedHeight;

                                        // Create spacers for positioned messages (drawings and text)
                                        // Create spacer if message is at or near the current flow position
                                        // Use a threshold to account for estimation errors
                                        final threshold = msgHeight; // If message is within its own height of flow, create spacer
                                        if (msgBottomY >= estimatedCurrentY - threshold) {
                                          // Check if there are normal messages below this positioned message in the list
                                          final hasMessagesBelow = _messages.skip(i + 1).any((m) => !m.isPositioned);

                                          final double spacerHeight;
                                          if (hasMessagesBelow) {
                                            // LOCK spacer at fixed height - don't change at all when messages are below
                                            // Use the message's UNSCALED intrinsic height to reserve space in the flow
                                            spacerHeight = baseHeight + 45;
                                          } else {
                                            // No messages below - spacer can dynamically adjust based on message position
                                            spacerHeight = ((msgBottomY - estimatedCurrentY).clamp(0.0, double.infinity)) + 5;
                                          }

                                          if (kDebugMode) {
                                            print('Creating ${msg.messageType} spacer:');
                                            print('  Current flow Y: ${estimatedCurrentY.toStringAsFixed(0)}');
                                            print('  Message top Y: ${msgTopY.toStringAsFixed(0)}');
                                            print('  Message bottom Y: ${msgBottomY.toStringAsFixed(0)}');
                                            print('  Spacer height: ${spacerHeight.toStringAsFixed(0)}');
                                            print('  Spacer will end at: ${(estimatedCurrentY + spacerHeight).toStringAsFixed(0)}');
                                          }

                                          // Only add spacer if height would be positive
                                          if (spacerHeight > 0) {
                                            // Track this spacer's Y range
                                            spacerRanges.add({
                                              'top': msgTopY - 20,
                                              'bottom': msgBottomY + 20,
                                            });

                                            items.add(
                                              IgnorePointer(
                                                child: Container(
                                                  key: ValueKey('spacer_${msg.messageId}'),
                                                  height: spacerHeight,
                                                  decoration: _isDebugging ? BoxDecoration(
                                                    border: Border.all(color: Colors.green, width: 2),
                                                  ) : null,
                                                  child: _isDebugging ? Center(
                                                    child: Text(
                                                      'SPACER for ${msg.messageId}\nType: ${msg.messageType}\nHeight: ${spacerHeight.toStringAsFixed(0)}px\nMsg Top Y: ${msgTopY.toStringAsFixed(0)}px\nMsg Bottom Y: ${msgBottomY.toStringAsFixed(0)}px\nEst Flow Y: ${estimatedCurrentY.toStringAsFixed(0)}px',
                                                      style: TextStyle(color: Colors.green, fontSize: 10),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ) : null,
                                                ),
                                              ),
                                            );

                                            // Update accumulated height with actual spacer height
                                            accumulatedHeight += spacerHeight;
                                          }
                                        }
                                      }
                                    } else {
                                      // Add normal message
                                      final message = normalMessages[normalIndex];

                                      // Check if this is a system message (e.g., "User cleared the chat")
                                      // Always show system messages
                                      if (message.messageType == 'system') {
                                        items.add(
                                          Center(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade900.withValues(alpha: 0),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  message.message,
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                        normalIndex++;
                                        continue;
                                      }

                                      final isMe = message.senderId == _currentUserId;
                                      final isLastMessage = _messages.isNotEmpty &&
                                          _messages.last.messageId == message.messageId;

                                      final isFirstInGroup = normalIndex == 0 ||
                                          normalMessages[normalIndex - 1].senderId != message.senderId;
                                      final isLastInGroup = normalIndex == normalMessages.length - 1 ||
                                          normalMessages[normalIndex + 1].senderId != message.senderId;

                                      // Check if this is the last message in a time cluster (5 minutes)
                                      final showTimestamp = normalIndex == normalMessages.length - 1 ||
                                          normalMessages[normalIndex + 1].senderId != message.senderId ||
                                          !_isWithinTimeCluster(message, normalMessages[normalIndex + 1]);

                                      if (kDebugMode) {
                                        print('Message ${message.messageId}: showTimestamp=$showTimestamp (isLast=${normalIndex == normalMessages.length - 1}, diffSender=${normalIndex < normalMessages.length - 1 ? normalMessages[normalIndex + 1].senderId != message.senderId : 'N/A'})');
                                      }

                                      // Add centered timestamp separator if there's a 5+ minute gap from previous message
                                      if (normalIndex > 0 && !_isWithinTimeCluster(normalMessages[normalIndex - 1], message)) {
                                        items.add(
                                          Center(
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade900.withValues(alpha: 0),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  _getDateTimeLabel(message.timestamp),
                                                  style: TextStyle(
                                                    color: Colors.grey.shade400,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                        accumulatedHeight += 50; // Account for timestamp separator height
                                      }

                                      items.add(
                                        GestureDetector(
                                          key: ValueKey('gesture_${message.messageId}'),
                                          behavior: HitTestBehavior.opaque,
                                          onLongPress: isMe ? () {
                                            if (kDebugMode) {
                                              print('🟡 NORMAL message ${message.messageId} received LONG PRESS - converting to positioned');
                                            }
                                            final RenderBox? stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
                                            if (stackBox == null) return;

                                            final renderBox = context.findRenderObject() as RenderBox?;
                                            if (renderBox == null) return;

                                            final stackPosition = stackBox.localToGlobal(Offset.zero);
                                            final bubblePosition = renderBox.localToGlobal(Offset.zero);

                                            final relativeX = bubblePosition.dx - stackPosition.dx + (renderBox.size.width / 2);
                                            final relativeY = bubblePosition.dy - stackPosition.dy + (renderBox.size.height / 2);

                                            // Add scroll offset to get position in content coordinates
                                            final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                                            final contentY = relativeY + scrollOffset;

                                            final viewportWidth = stackBox.size.width;

                                            _updateMessagePosition(
                                              message,
                                              relativeX,
                                              contentY,
                                              viewportWidth,
                                              viewportHeight,
                                            );
                                          } : null,
                                          child: _MessageBubbleWithGradient(
                                            key: ValueKey('normal_${message.messageId}'),
                                            message: message,
                                            isMe: isMe,
                                            isLastMessage: isLastMessage,
                                            isFirstInGroup: isFirstInGroup,
                                            isLastInGroup: isLastInGroup,
                                            showTimestamp: showTimestamp,
                                            scrollController: _scrollController,
                                          ),
                                        ),
                                      );

                                      // Update accumulated height with estimated message height
                                      accumulatedHeight += 80; // Average message height

                                      normalIndex++;
                                    }
                                  }

                                  return items;
                                }(),
                                // Extra bottom space for drawing
                                SizedBox(height: _extraBottomSpace),
                              ],
                            ),
                          ),

                          // Drawing overlay (top layer when in drawing mode)
                          if (_isDrawingMode)
                            Positioned.fill(
                              child: GestureDetector(
                                onPanStart: (details) {
                                  final renderBox = context.findRenderObject() as RenderBox;
                                  final localPosition = renderBox.globalToLocal(details.globalPosition);

                                  // Add scroll offset to get position in content coordinates
                                  final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                                  final contentY = localPosition.dy + scrollOffset;

                                  setState(() {
                                    _currentStroke = DrawingStroke(
                                      points: [Offset(
                                        localPosition.dx / constraints.maxWidth,
                                        contentY / viewportHeight,
                                      )],
                                      color: _selectedColor,
                                    );
                                  });
                                },
                                onPanUpdate: (details) {
                                  if (_currentStroke != null) {
                                    final renderBox = context.findRenderObject() as RenderBox;
                                    final localPosition = renderBox.globalToLocal(details.globalPosition);

                                    // Add scroll offset to get position in content coordinates
                                    final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                                    final contentY = localPosition.dy + scrollOffset;

                                    setState(() {
                                      _currentStroke!.points.add(Offset(
                                        localPosition.dx / constraints.maxWidth,
                                        contentY / viewportHeight,
                                      ));
                                    });
                                  }
                                },
                                onPanEnd: (details) {
                                  if (_currentStroke != null && _currentStroke!.points.isNotEmpty) {
                                    setState(() {
                                      _drawingStrokes.add(_currentStroke!);
                                      _currentStroke = null;
                                    });
                                  }
                                },
                                child: CustomPaint(
                                  painter: _DrawingOverlayPainter(
                                    strokes: _drawingStrokes,
                                    currentStroke: _currentStroke,
                                    viewportWidth: constraints.maxWidth,
                                    viewportHeight: viewportHeight,
                                  ),
                                ),
                              ),
                            ),

                          // Positioned messages overlaid on the scrollable content
                          ...positionedMessages.map((message) {
                            final isMe = message.senderId == _currentUserId;
                            final isLastMessage = _messages.isNotEmpty &&
                                _messages.last.messageId == message.messageId;
                            final isDrawingOrGifOrSticker = message.messageType == 'drawing' || message.messageType == 'gif' || message.messageType == 'sticker';

                            // Calculate pixel position from percentage
                            // Mirror X position for messages from other users (applies to all message types)
                            final posX = message.senderId != _currentUserId
                                ? (1.0 - (message.positionX ?? 0.5))
                                : (message.positionX ?? 0.5);

                            // Mirror rotation for messages from other users (horizontal flip)
                            // Formula: -rotation (negates rotation like a mirror reflection)
                            // 45° clockwise becomes 45° counter-clockwise
                            final mirroredRotation = message.senderId != _currentUserId
                                ? (-(message.rotation ?? 0.0))
                                : (message.rotation ?? 0.0);

                            final top = (message.positionY ?? 0.5) * viewportHeight;
                            final left = posX * constraints.maxWidth;

                            final skipAnimation = _justDraggedMessages.contains(message.messageId);

                            // Build the child widget with IgnorePointer when in drawing mode
                            final Widget childWidget;

                            if (isDrawingOrGifOrSticker) {
                              // Check message type
                              final isGif = message.messageType == 'gif';
                              final isSticker = message.messageType == 'sticker';

                              final mediaWidget = isGif
                                  ? _GifMessageWidget(
                                      key: ValueKey('positioned_gif_${message.messageId}'),
                                      message: message,
                                      viewportWidth: constraints.maxWidth,
                                      viewportHeight: viewportHeight,
                                    )
                                  : isSticker
                                      ? _StickerMessageWidget(
                                          key: ValueKey('positioned_sticker_${message.messageId}'),
                                          message: message,
                                          viewportWidth: constraints.maxWidth,
                                          viewportHeight: viewportHeight,
                                        )
                                      : _DrawingMessageWidget(
                                          key: ValueKey('positioned_drawing_${message.messageId}'),
                                          message: message,
                                          viewportWidth: constraints.maxWidth,
                                          viewportHeight: viewportHeight,
                                          isDebugging: _isDebugging,
                                        );

                              // Make drawings/GIFs draggable, rotatable, and scalable if sent by current user
                              if (isMe && !_isDrawingMode) {
                                final isTransforming = _transformingMessageId == message.messageId;
                                final visualOffset = isTransforming ? _dragOffset : Offset.zero;
                                final visualRotation = isTransforming ? _currentRotation : (message.rotation ?? 0.0);
                                final visualScale = isTransforming ? _currentScale : (message.scale ?? 1.0);

                                childWidget = FractionalTranslation(
                                  translation: const Offset(-0.5, -0.5),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // Ghost preview at original position (only visible while dragging)
                                      if (isTransforming)
                                        Opacity(
                                          opacity: 0.3,
                                          child: Transform.rotate(
                                            angle: mirroredRotation,
                                            child: Transform.scale(
                                              scale: message.scale ?? 1.0,
                                              child: Container(
                                                constraints: const BoxConstraints(
                                                  minWidth: 120,
                                                  minHeight: 120,
                                                ),
                                                child: Center(child: mediaWidget),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // Actual draggable message
                                      Transform.translate(
                                        offset: visualOffset,
                                        child: Transform.rotate(
                                          angle: visualRotation,
                                          child: Transform.scale(
                                            scale: visualScale,
                                            child: Listener(
                                              behavior: HitTestBehavior.opaque,
                                              onPointerDown: (details) {
                                                HapticFeedback.selectionClick();
                                                setState(() {
                                                  _activePointers[details.pointer] = details.position;

                                                  if (_activePointers.length == 1) {
                                                    // First finger - start transform
                                                    _firstPointerId = details.pointer;
                                                    _transformingMessageId = message.messageId;
                                                    _dragStartPosition = details.position;
                                                    _dragOffset = Offset.zero;
                                                    _baseRotation = mirroredRotation;
                                                    _baseScale = message.scale ?? 1.0;
                                                    _currentRotation = _baseRotation;
                                                    _currentScale = _baseScale;
                                                  } else if (_activePointers.length == 2) {
                                                    // Second finger added - initialize rotation/scale
                                                    final pointers = _activePointers.values.toList();
                                                    _initialDistance = _calculateDistance(pointers[0], pointers[1]);
                                                    _initialAngle = _calculateAngle(pointers[0], pointers[1]);
                                                  }
                                                });
                                              },
                                              onPointerMove: (details) {
                                                if (_transformingMessageId == message.messageId) {
                                                  setState(() {
                                                    _activePointers[details.pointer] = details.position;

                                                    if (_activePointers.length == 1) {
                                                      // Single finger - drag
                                                      final pointer = _activePointers.values.first;
                                                      _dragOffset = pointer - _dragStartPosition;
                                                    } else if (_activePointers.length >= 2) {
                                                      // Two fingers - drag with first finger, rotate and scale with both
                                                      final pointers = _activePointers.values.toList();
                                                      final currentDistance = _calculateDistance(pointers[0], pointers[1]);
                                                      final currentAngle = _calculateAngle(pointers[0], pointers[1]);

                                                      // Keep message anchored to first finger (don't jump to center)
                                                      if (_firstPointerId != null && _activePointers.containsKey(_firstPointerId)) {
                                                        final firstFingerPos = _activePointers[_firstPointerId]!;
                                                        _dragOffset = firstFingerPos - _dragStartPosition;
                                                      }

                                                      // Calculate scale and rotation
                                                      final scaleDelta = currentDistance / _initialDistance;
                                                      _currentScale = (_baseScale * scaleDelta).clamp(0.3, 3.0);
                                                      _currentRotation = _baseRotation + (currentAngle - _initialAngle);
                                                    }
                                                  });
                                                }
                                              },
                                              onPointerUp: (details) {
                                                if (_transformingMessageId != message.messageId) return;

                                                // Will be last pointer after global listener removes it
                                                final willBeLastPointer = _activePointers.length == 1;
                                                final isFirstPointer = details.pointer == _firstPointerId;

                                                // Handle state transitions BEFORE global listener removes pointer
                                                if (willBeLastPointer) {
                                                  // This is the last finger - save transform
                                                  setState(() {
                                                    HapticFeedback.mediumImpact();

                                                    final newLeft = left + _dragOffset.dx;
                                                    final newTop = top + _dragOffset.dy;
                                                    final contentY = newTop;

                                                    _updateMessageTransform(
                                                      message,
                                                      newLeft,
                                                      contentY,
                                                      constraints.maxWidth,
                                                      viewportHeight,
                                                      _currentRotation,
                                                      _currentScale,
                                                    );

                                                    // Don't clear state yet - let global listener do it
                                                  });
                                                } else if (_activePointers.length == 2) {
                                                  // Going from 2 fingers to 1 finger - save current state
                                                  setState(() {
                                                    final remainingId = _activePointers.keys.firstWhere((id) => id != details.pointer);
                                                    final remainingPos = _activePointers[remainingId]!;

                                                    // Save the current transform
                                                    final newLeft = left + _dragOffset.dx;
                                                    final newTop = top + _dragOffset.dy;
                                                    final contentY = newTop;

                                                    _updateMessageTransform(
                                                      message,
                                                      newLeft,
                                                      contentY,
                                                      constraints.maxWidth,
                                                      viewportHeight,
                                                      _currentRotation,
                                                      _currentScale,
                                                    );

                                                    // If first finger was lifted, make remaining finger the new anchor
                                                    if (isFirstPointer) {
                                                      _firstPointerId = remainingId;
                                                    }

                                                    // Reset drag offset since we just saved the position
                                                    _dragStartPosition = remainingPos;
                                                    _dragOffset = Offset.zero;

                                                    // Lock in current rotation/scale as the new base
                                                    _baseRotation = _currentRotation;
                                                    _baseScale = _currentScale;

                                                    // Reset two-finger gesture state
                                                    _initialDistance = 0.0;
                                                    _initialAngle = 0.0;
                                                  });
                                                }
                                                // Global listener will handle pointer removal
                                              },
                                              onPointerCancel: (details) {
                                                setState(() {
                                                  _activePointers.remove(details.pointer);
                                                  if (_activePointers.isEmpty) {
                                                    _transformingMessageId = null;
                                                    _firstPointerId = null;
                                                    _dragOffset = Offset.zero;
                                                    _currentRotation = 0.0;
                                                    _currentScale = 1.0;
                                                  }
                                                });
                                              },
                                              // Wrap in container with minimum size for easier gestures
                                              child: Container(
                                                constraints: const BoxConstraints(
                                                  minWidth: 120,
                                                  minHeight: 120,
                                                ),
                                                child: Center(child: mediaWidget),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else {
                                // Not draggable (drawing mode or not sent by me)
                                // Animate scale changes for other user's messages
                                childWidget = IgnorePointer(
                                  child: FractionalTranslation(
                                    translation: const Offset(-0.5, -0.5),
                                    child: Transform.rotate(
                                      angle: mirroredRotation,
                                      child: TweenAnimationBuilder<double>(
                                        tween: Tween(begin: message.scale ?? 1.0, end: message.scale ?? 1.0),
                                        duration: skipAnimation ? Duration.zero : const Duration(milliseconds: 200),
                                        curve: Curves.easeOutCubic,
                                        builder: (context, scale, child) => Transform.scale(
                                          scale: scale,
                                          child: child,
                                        ),
                                        child: mediaWidget,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } else if (!isMe) {
                              // Other user's messages: wrap with IgnorePointer and FractionalTranslation
                              // Animate scale changes for other user's messages
                              childWidget = IgnorePointer(
                                ignoring: _isDrawingMode,
                                child: FractionalTranslation(
                                  translation: const Offset(-0.5, -0.5),
                                  child: Transform.rotate(
                                    angle: mirroredRotation,
                                    child: TweenAnimationBuilder<double>(
                                      tween: Tween(begin: message.scale ?? 1.0, end: message.scale ?? 1.0),
                                      duration: skipAnimation ? Duration.zero : const Duration(milliseconds: 200),
                                      curve: Curves.easeOutCubic,
                                      builder: (context, scale, child) => Transform.scale(
                                        scale: scale,
                                        child: child,
                                      ),
                                      child: _MessageBubbleWithGradient(
                                        key: ValueKey('positioned_${message.messageId}'),
                                        message: message,
                                        isMe: isMe,
                                        isLastMessage: isLastMessage,
                                        isFirstInGroup: true,
                                        isLastInGroup: true,
                                        showTimestamp: true, // Positioned messages always show timestamp
                                        scrollController: _scrollController,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            } else {
                              // My messages: Draggable with a large, centered hitbox.
                              final isDragging = _draggingMessageId == message.messageId;
                              final visualOffset = isDragging ? _dragOffset : Offset.zero;

                              // The core bubble widget that will be displayed.
                              final bubbleWidget = _MessageBubbleWithGradient(
                                key: ValueKey('positioned_${message.messageId}'),
                                message: message,
                                isMe: isMe,
                                isLastMessage: isLastMessage,
                                isFirstInGroup: true,
                                isLastInGroup: true,
                                showTimestamp: true, // Positioned messages always show timestamp
                                scrollController: _scrollController,
                              );

                              // Only add gesture detection when NOT in drawing mode
                              if (_isDrawingMode) {
                                // In drawing mode, just show the bubble, centered, with no interaction.
                                childWidget = FractionalTranslation(
                                  translation: const Offset(-0.5, -0.5),
                                  child: IgnorePointer(child: bubbleWidget),
                                );
                              } else {
                                // For interaction, create a large hitbox with Align, and wrap it in GestureDetector for transform support
                                final isTransforming = _transformingMessageId == message.messageId;
                                final visualRotation = isTransforming ? _currentRotation : (message.rotation ?? 0.0);
                                final visualScale = isTransforming ? _currentScale : (message.scale ?? 1.0);

                                final interactiveHitbox = Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    // Ghost preview at original position (only visible while dragging)
                                    if (isTransforming)
                                      Opacity(
                                        opacity: 0.3,
                                        child: Transform.rotate(
                                          angle: mirroredRotation,
                                          child: Transform.scale(
                                            scale: message.scale ?? 1.0,
                                            child: Container(
                                              constraints: const BoxConstraints(
                                                minWidth: 120,
                                                minHeight: 120,
                                              ),
                                              child: Center(child: bubbleWidget),
                                            ),
                                          ),
                                        ),
                                      ),
                                    // Actual draggable message
                                    Transform.translate(
                                      offset: isTransforming ? _dragOffset : Offset.zero,
                                      child: Listener(
                                        behavior: HitTestBehavior.opaque,
                                        onPointerDown: (details) {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            _activePointers[details.pointer] = details.position;

                                            if (_activePointers.length == 1) {
                                              // First finger - start transform
                                              _firstPointerId = details.pointer;
                                              _transformingMessageId = message.messageId;
                                              _dragStartPosition = details.position;
                                              _dragOffset = Offset.zero;
                                              _baseRotation = mirroredRotation;
                                              _baseScale = message.scale ?? 1.0;
                                              _currentRotation = _baseRotation;
                                              _currentScale = _baseScale;
                                            } else if (_activePointers.length == 2) {
                                              // Second finger added - initialize rotation/scale
                                              final pointers = _activePointers.values.toList();
                                              _initialDistance = _calculateDistance(pointers[0], pointers[1]);
                                              _initialAngle = _calculateAngle(pointers[0], pointers[1]);
                                            }
                                          });
                                        },
                                        onPointerMove: (details) {
                                          if (_transformingMessageId == message.messageId) {
                                            setState(() {
                                              _activePointers[details.pointer] = details.position;

                                              if (_activePointers.length == 1) {
                                                // Single finger - drag
                                                final pointer = _activePointers.values.first;
                                                _dragOffset = pointer - _dragStartPosition;
                                              } else if (_activePointers.length >= 2) {
                                                // Two fingers - drag with first finger, rotate and scale with both
                                                final pointers = _activePointers.values.toList();
                                                final currentDistance = _calculateDistance(pointers[0], pointers[1]);
                                                final currentAngle = _calculateAngle(pointers[0], pointers[1]);

                                                // Keep message anchored to first finger (don't jump to center)
                                                if (_firstPointerId != null && _activePointers.containsKey(_firstPointerId)) {
                                                  final firstFingerPos = _activePointers[_firstPointerId]!;
                                                  _dragOffset = firstFingerPos - _dragStartPosition;
                                                }

                                                // Calculate scale and rotation
                                                final scaleDelta = currentDistance / _initialDistance;
                                                _currentScale = (_baseScale * scaleDelta).clamp(0.3, 3.0);
                                                _currentRotation = _baseRotation + (currentAngle - _initialAngle);
                                              }
                                            });
                                          }
                                        },
                                        onPointerUp: (details) {
                                          if (_transformingMessageId != message.messageId) return;

                                          // Will be last pointer after global listener removes it
                                          final willBeLastPointer = _activePointers.length == 1;
                                          final isFirstPointer = details.pointer == _firstPointerId;

                                          // Handle state transitions BEFORE global listener removes pointer
                                          if (willBeLastPointer) {
                                            // This is the last finger - save transform
                                            setState(() {
                                              HapticFeedback.mediumImpact();

                                              final newLeft = left + _dragOffset.dx;
                                              final newTop = top + _dragOffset.dy;
                                              final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                                              final contentY = newTop + scrollOffset;

                                              _updateMessageTransform(
                                                message,
                                                newLeft,
                                                contentY,
                                                constraints.maxWidth,
                                                viewportHeight,
                                                _currentRotation,
                                                _currentScale,
                                              );

                                              // Don't clear state yet - let global listener do it
                                            });
                                          } else if (_activePointers.length == 2) {
                                            // Going from 2 fingers to 1 finger - save current state
                                            setState(() {
                                              final remainingId = _activePointers.keys.firstWhere((id) => id != details.pointer);
                                              final remainingPos = _activePointers[remainingId]!;

                                              // Save the current transform
                                              final newLeft = left + _dragOffset.dx;
                                              final newTop = top + _dragOffset.dy;
                                              final scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
                                              final contentY = newTop + scrollOffset;

                                              _updateMessageTransform(
                                                message,
                                                newLeft,
                                                contentY,
                                                constraints.maxWidth,
                                                viewportHeight,
                                                _currentRotation,
                                                _currentScale,
                                              );

                                              // If first finger was lifted, make remaining finger the new anchor
                                              if (isFirstPointer) {
                                                _firstPointerId = remainingId;
                                              }

                                              // Reset drag offset since we just saved the position
                                              _dragStartPosition = remainingPos;
                                              _dragOffset = Offset.zero;

                                              // Lock in current rotation/scale as the new base
                                              _baseRotation = _currentRotation;
                                              _baseScale = _currentScale;

                                              // Reset two-finger gesture state
                                              _initialDistance = 0.0;
                                              _initialAngle = 0.0;
                                            });
                                          }
                                          // Global listener will handle pointer removal
                                        },
                                        onPointerCancel: (details) {
                                          setState(() {
                                            _activePointers.remove(details.pointer);
                                            if (_activePointers.isEmpty) {
                                              _transformingMessageId = null;
                                              _firstPointerId = null;
                                              _dragOffset = Offset.zero;
                                              _currentRotation = 0.0;
                                              _currentScale = 1.0;
                                            }
                                          });
                                        },
                                        // The container creates a larger hitbox for easier gesture detection
                                        // Minimum 120x120 points to make small messages easy to manipulate
                                        child: Transform.rotate(
                                          angle: visualRotation,
                                          child: Transform.scale(
                                            scale: visualScale,
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                return Align(
                                                  alignment: Alignment.center,
                                                  child: Container(
                                                    constraints: const BoxConstraints(
                                                      minWidth: 120,
                                                      minHeight: 120,
                                                    ),
                                                    decoration: _isDebugging ? BoxDecoration(
                                                      border: Border.all(
                                                        color: Colors.yellow.withValues(alpha: 0.8),
                                                        width: 2,
                                                      ),
                                                      color: Colors.yellow.withValues(alpha: 0.15),
                                                    ) : null,
                                                    child: Center(child: bubbleWidget),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );

                                // Center the entire hitbox assembly
                                childWidget = FractionalTranslation(
                                  translation: const Offset(-0.5, -0.5),
                                  child: interactiveHitbox,
                                );
                              }
                            }

                            return skipAnimation
                                ? Positioned(
                                    key: ValueKey('positioned_${message.messageId}'),
                                    left: left,
                                    top: top,
                                    child: childWidget,
                                  )
                                : AnimatedPositioned(
                                    key: ValueKey('animated_positioned_${message.messageId}'),
                                    left: left,
                                    top: top,
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeOutCubic,
                                    child: childWidget,
                                  );
                          }),
                        ],
                      ),
                    ),
                  ), // Close Listener
                ); // Close SingleChildScrollView
              },
            ),
          ),

          // Input field or Drawing controls - Positioned at bottom (overlays messages)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: _isDrawingMode ? 10 : 0,
                  sigmaY: _isDrawingMode ? 10 : 0,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  decoration: BoxDecoration(
                    color: _isDrawingMode
                        ? Colors.black.withValues(alpha: 0.8)
                        : Colors.black,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 10),
                    child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: AnimatedCrossFade(
                              firstChild: _buildTextInput(),
                              secondChild: _buildDrawingControls(),
                              crossFadeState: _isDrawingMode
                                  ? CrossFadeState.showSecond
                                  : CrossFadeState.showFirst,
                              duration: const Duration(milliseconds: 250),
                              firstCurve: Curves.easeInOut,
                              secondCurve: Curves.easeInOut,
                              sizeCurve: Curves.easeInOut,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Single send button for both modes - stays at same X position
                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFF5856D6),
                              shape: BoxShape.circle,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.only(top: 3),
                              icon: SvgPicture.asset(
                                'assets/send.svg',
                                width: 15,
                                height: 15,
                                colorFilter: const ColorFilter.mode(
                                  Colors.white,
                                  BlendMode.srcIn,
                                ),
                              ),
                              onPressed: () {
                                if (_isDrawingMode) {
                                  if (_drawingStrokes.isNotEmpty) {
                                    _sendDrawing();
                                  }
                                } else {
                                  if (_messageController.text.trim().isNotEmpty) {
                                    _sendMessage();
                                  }
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return TextField(
      controller: _messageController,
      style: AppTypography.body.copyWith(color: Colors.white),
      cursorColor: const Color(0xFF5856D6),
      onChanged: (text) {
        // Trigger rebuild to update send button state
        setState(() {});
      },
      decoration: InputDecoration(
        hintText: 'Message...',
        hintStyle: AppTypography.body.copyWith(
          color: AppColors.textTertiary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w600
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide.none,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFF141414),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        isDense: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Color(0xFF5856D6),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(
                CupertinoIcons.camera_fill,
                color: Colors.white,
                size: 18,
              ),
              onPressed: () {
                // Camera action
              },
            ),
          ),
        ),
        suffixIcon: PullDownButton(
          position: PullDownMenuPosition.automatic,
          itemBuilder: (context) => [
            PullDownMenuItem(
              onTap: () {
                FocusScope.of(context).unfocus();
                setState(() {
                  _isDrawingMode = true;
                });
              },
              title: 'Draw',
              icon: CupertinoIcons.paintbrush,
            ),
            PullDownMenuItem(
              onTap: () {
                FocusScope.of(context).unfocus();
                _showGifPicker();
              },
              title: 'Gifs',
              icon: CupertinoIcons.square_grid_3x2,
            ),
            PullDownMenuItem(
              onTap: () {
                FocusScope.of(context).unfocus();
                _showStickerPicker();
              },
              title: 'Stickers',
              icon: CupertinoIcons.smiley,
            ),
          ],
          buttonBuilder: (context, showMenu) => IconButton(
            icon: Icon(
              CupertinoIcons.add,
              color: Colors.white.withValues(alpha: 0.5),
              size: 24,
            ),
            onPressed: () {
              FocusScope.of(context).unfocus();
              showMenu();
            },
          ),
        ),
      ),
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
    );
  }

  Widget _buildDrawingControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Close button with background
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF2C2C2E),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.close, color: Colors.white, size: 20),
              onPressed: () {
                // Keep keyboard hidden when switching back
                FocusScope.of(context).unfocus();
                setState(() {
                  _isDrawingMode = false;
                  _drawingStrokes.clear();
                  _currentStroke = null;
                });
              },
            ),
          ),
          const SizedBox(width: 8),
          // Undo button with background
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0xFF2C2C2E),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(
                CupertinoIcons.arrow_uturn_left,
                color: _drawingStrokes.isEmpty ? Colors.white38 : Colors.white,
                size: 20,
              ),
              onPressed: _drawingStrokes.isEmpty ? null : () {
                setState(() {
                  if (_drawingStrokes.isNotEmpty) {
                    _drawingStrokes.removeLast();
                  }
                });
              },
            ),
          ),
          const SizedBox(width: 12),
          // Color picker with page view
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Add space button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _extraBottomSpace += 200;
                    });
                    // Scroll to bottom to show new space
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (_scrollController.hasClients) {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Text(
                        'Add Space',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Color circles
                SizedBox(
                  height: 24,
                  child: PageView.builder(
                    controller: _colorPageController,
                    onPageChanged: (page) {
                      setState(() {
                        _currentColorPage = page;
                      });
                    },
                    itemCount: _colorPages.length,
                    itemBuilder: (context, pageIndex) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: _colorPages[pageIndex].map((color) {
                          final isSelected = color == _selectedColor;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedColor = color;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: isSelected ? 3 : 1.5,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Page indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_colorPages.length, (index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentColorPage == index ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentColorPage == index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _colorPageController.dispose();
    _syncTimer?.cancel();
    _chatService.dispose();
    super.dispose();
  }
}

// Wrapper to calculate bubble position and apply gradient
class _MessageBubbleWithGradient extends StatefulWidget {
  final Message message;
  final bool isMe;
  final bool isLastMessage;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showTimestamp;
  final ScrollController scrollController;
  final GlobalKey? bubbleKey; // Key for the actual bubble Container

  const _MessageBubbleWithGradient({
    super.key,
    required this.message,
    required this.isMe,
    required this.isLastMessage,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.showTimestamp,
    required this.scrollController,
    this.bubbleKey,
  });

  @override
  State<_MessageBubbleWithGradient> createState() => _MessageBubbleWithGradientState();
}

class _MessageBubbleWithGradientState extends State<_MessageBubbleWithGradient> {
  final GlobalKey _key = GlobalKey();
  Color _bubbleColorTop = AppColors.surfaceVariant;
  Color _bubbleColorBottom = AppColors.surfaceVariant;

  @override
  void initState() {
    super.initState();
    _updateGradient();
  }

  @override
  void didUpdateWidget(_MessageBubbleWithGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.isPositioned != widget.message.isPositioned ||
        oldWidget.message.positionY != widget.message.positionY) {
      _updateGradient();
    }
  }

  void _updateGradient() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      try {
        final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) return;

        final scrollBox = widget.scrollController.position.context.storageContext.findRenderObject() as RenderBox?;
        if (scrollBox == null) return;

        final bubblePosition = renderBox.localToGlobal(Offset.zero);
        final scrollPosition = scrollBox.localToGlobal(Offset.zero);
        final relativeY = bubblePosition.dy - scrollPosition.dy;
        final scrollExtent = widget.scrollController.position.viewportDimension;

        final progress = (relativeY / scrollExtent).clamp(0.0, 1.0);

        setState(() {
          if (widget.isMe) {
            _bubbleColorTop = Color.lerp(
              const Color(0xFF5856D6),
              const Color(0xFF7B68EE),
              progress,
            )!;
            _bubbleColorBottom = Color.lerp(
              const Color(0xFF4834D4),
              const Color(0xFF5856D6),
              progress,
            )!;
          } else {
            _bubbleColorTop = AppColors.surfaceVariant;
            _bubbleColorBottom = AppColors.surfaceVariant;
          }
        });
      } catch (e) {
        // Silently handle errors during gradient calculation
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _key,
      child: _MessageBubble(
        message: widget.message,
        isMe: widget.isMe,
        isLastMessage: widget.isLastMessage,
        isFirstInGroup: widget.isFirstInGroup,
        isLastInGroup: widget.isLastInGroup,
        showTimestamp: widget.showTimestamp,
        bubbleColorTop: _bubbleColorTop,
        bubbleColorBottom: _bubbleColorBottom,
        bubbleKey: widget.bubbleKey, // Pass the key for position tracking
      ),
    );
  }
}

// Message bubble widget - Modern design with compact size
class _MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isLastMessage;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showTimestamp;
  final Color bubbleColorTop;
  final Color bubbleColorBottom;
  final GlobalKey? bubbleKey;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.isLastMessage,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.showTimestamp,
    required this.bubbleColorTop,
    required this.bubbleColorBottom,
    this.bubbleKey,
  });

  @override
  Widget build(BuildContext context) {
    // Special handling for GIF messages - render at message width without bubble
    if (message.messageType == 'gif' && message.metadata != null && message.metadata!['gifUrl'] != null) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.5,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  message.metadata!['gifUrl'],
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      color: Colors.grey.shade900,
                      child: const Center(
                        child: CupertinoActivityIndicator(
                          color: Colors.white,
                          radius: 14,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: Colors.grey.shade900,
                      child: const Center(
                        child: Icon(
                          Icons.error_outline,
                          color: Colors.grey,
                          size: 40,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Only show timestamp if this is the last in time cluster
              if (showTimestamp && !message.isPositioned) ...[
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Special handling for sticker messages - render without bubble, smaller than GIFs
    if (message.messageType == 'sticker' && message.metadata != null && message.metadata!['stickerUrl'] != null) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.4,
          ),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                message.metadata!['stickerUrl'],
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 150,
                    color: Colors.transparent,
                    child: const Center(
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 14,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 150,
                    color: Colors.transparent,
                    child: const Center(
                      child: Icon(
                        Icons.error_outline,
                        color: Colors.grey,
                        size: 40,
                      ),
                    ),
                  );
                },
              ),
              // Only show timestamp if this is the last in time cluster
              if (showTimestamp && !message.isPositioned) ...[
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Regular text message with bubble
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Message bubble
            IntrinsicWidth(
              child: Container(
                key: bubbleKey, // Use the provided key for position tracking
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                constraints: BoxConstraints(
                  minWidth: 30,
                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                ),
                decoration: BoxDecoration(
                  gradient: isMe
                      ? LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [bubbleColorTop, bubbleColorBottom],
                        )
                      : null,
                  color: isMe ? null : bubbleColorTop,
                  borderRadius: _getBorderRadius(),
                ),
                child: Text(
                  message.message,
                  style: AppTypography.body.copyWith(
                    color: isMe ? Colors.white : AppColors.textPrimary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            // Timestamp below bubble (only show if this is the last in time cluster)
            if (showTimestamp && !message.isPositioned) ...[
              const SizedBox(height: 4),
              Text(
                _formatTime(message.timestamp),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],

            // Read status below bubble (only show on last message)
            // Positioned absolutely so it doesn't affect bubble width
            // if (isMe && isLastMessage)
            //   Positioned(
            //     top: null,
            //     bottom: -20,
            //     right: 4,
            //     child: Text(
            //       _getMessageStatusWithTime(),
            //       style: AppTypography.caption.copyWith(
            //         color: AppColors.textTertiary.withValues(alpha: 0.7),
            //         fontSize: 11,
            //         fontWeight: FontWeight.w600,
            //       ),
            //       overflow: TextOverflow.fade,
            //       softWrap: false,
            //       maxLines: 1,
            //     ),
            //   ),
          ],
        ),
      ),
    );
  }

  BorderRadius _getBorderRadius() {
    const fullRadius = 18.0;
    const tightRadius = 4.0;

    // Positioned messages are always fully rounded
    if (message.isPositioned) {
      return BorderRadius.circular(fullRadius);
    }

    // Single message (not grouped)
    if (isFirstInGroup && isLastInGroup) {
      return BorderRadius.circular(fullRadius);
    }

    // First message in group
    if (isFirstInGroup && !isLastInGroup) {
      return BorderRadius.only(
        topLeft: const Radius.circular(fullRadius),
        topRight: const Radius.circular(fullRadius),
        bottomLeft: Radius.circular(isMe ? fullRadius : tightRadius),
        bottomRight: Radius.circular(isMe ? tightRadius : fullRadius),
      );
    }

    // Last message in group
    if (!isFirstInGroup && isLastInGroup) {
      return BorderRadius.only(
        topLeft: Radius.circular(isMe ? fullRadius : tightRadius),
        topRight: Radius.circular(isMe ? tightRadius : fullRadius),
        bottomLeft: const Radius.circular(fullRadius),
        bottomRight: const Radius.circular(fullRadius),
      );
    }

    // Middle message in group
    return BorderRadius.only(
      topLeft: Radius.circular(isMe ? fullRadius : tightRadius),
      topRight: Radius.circular(isMe ? tightRadius : fullRadius),
      bottomLeft: Radius.circular(isMe ? fullRadius : tightRadius),
      bottomRight: Radius.circular(isMe ? tightRadius : fullRadius),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final messageTime = DateTime.parse(timestamp);
      final hour = messageTime.hour;
      final minute = messageTime.minute.toString().padLeft(2, '0');

      // Format as 12-hour time
      if (hour == 0) {
        return '12:$minute AM';
      } else if (hour < 12) {
        return '$hour:$minute AM';
      } else if (hour == 12) {
        return '12:$minute PM';
      } else {
        return '${hour - 12}:$minute PM';
      }
    } catch (e) {
      return '';
    }
  }

  String _getRelativeTime(String timestamp) {
    try {
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(messageTime);

      if (difference.inSeconds < 60) {
        return 'just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return '';
    }
  }

  String _getMessageStatusWithTime() {
    final relativeTime = _getRelativeTime(message.timestamp);

    if (message.isRead) {
      return 'Seen $relativeTime';
    } else if (message.deliveredAt != null && message.deliveredAt!.isNotEmpty) {
      return 'Delivered $relativeTime';
    } else {
      return 'Sent $relativeTime';
    }
  }
}

// Drawing stroke data class (stores normalized coordinates 0.0-1.0)
class DrawingStroke {
  final List<Offset> points; // Normalized coordinates (0.0 to 1.0)
  final Color color;

  DrawingStroke({
    required this.points,
    required this.color,
  });
}

// Widget to render a drawing message
class _DrawingMessageWidget extends StatelessWidget {
  final Message message;
  final double viewportWidth;
  final double viewportHeight;
  final bool isDebugging;

  const _DrawingMessageWidget({
    super.key,
    required this.message,
    required this.viewportWidth,
    required this.viewportHeight,
    this.isDebugging = false,
  });

  @override
  Widget build(BuildContext context) {
    // Parse strokes from metadata
    final metadata = message.metadata as Map<String, dynamic>?;
    if (metadata == null || metadata['strokes'] == null) {
      return const SizedBox.shrink();
    }

    final strokesData = metadata['strokes'] as List;
    final strokes = strokesData.map((strokeJson) {
      final points = (strokeJson['points'] as List).map((p) {
        final coords = p as List;
        // Handle both int and double from JSON
        return Offset((coords[0] as num).toDouble(), (coords[1] as num).toDouble());
      }).toList();

      // Parse color from hex string
      final colorHex = strokeJson['color'] as String;
      final colorInt = int.parse(colorHex.substring(1), radix: 16);
      final color = Color(colorInt);

      return DrawingStroke(points: points, color: color);
    }).toList();

    // Calculate bounds from metadata
    final bounds = metadata['bounds'] as Map<String, dynamic>?;
    final minX = (bounds?['minX'] as num?)?.toDouble() ?? 0.0;
    final minY = (bounds?['minY'] as num?)?.toDouble() ?? 0.0;
    final maxX = (bounds?['maxX'] as num?)?.toDouble() ?? 1.0;
    final maxY = (bounds?['maxY'] as num?)?.toDouble() ?? 1.0;

    // Calculate size of the drawing in pixels
    final width = (maxX - minX) * viewportWidth;
    final height = (maxY - minY) * viewportHeight;

    return Container(
      width: width.clamp(50.0, viewportWidth),
      height: height.clamp(50.0, viewportHeight),
      decoration: isDebugging ? BoxDecoration(
        border: Border.all(color: Colors.red, width: 2),
      ) : null,
      child: CustomPaint(
        painter: _SavedDrawingPainter(
          strokes: strokes,
          bounds: bounds!,
          viewportWidth: viewportWidth,
          viewportHeight: viewportHeight,
        ),
      ),
    );
  }
}

// Painter for saved drawing messages
class _SavedDrawingPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final Map<String, dynamic> bounds;
  final double viewportWidth;
  final double viewportHeight;

  _SavedDrawingPainter({
    required this.strokes,
    required this.bounds,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final minX = (bounds['minX'] as num).toDouble();
    final minY = (bounds['minY'] as num).toDouble();

    for (var stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < stroke.points.length - 1; i++) {
        // Convert normalized coordinates to pixels, relative to drawing bounds
        final p1 = Offset(
          (stroke.points[i].dx - minX) * viewportWidth,
          (stroke.points[i].dy - minY) * viewportHeight,
        );
        final p2 = Offset(
          (stroke.points[i + 1].dx - minX) * viewportWidth,
          (stroke.points[i + 1].dy - minY) * viewportHeight,
        );
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_SavedDrawingPainter oldDelegate) => false;
}

// Widget for rendering GIF messages
class _GifMessageWidget extends StatelessWidget {
  final Message message;
  final double viewportWidth;
  final double viewportHeight;

  const _GifMessageWidget({
    super.key,
    required this.message,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Parse GIF data from metadata
    final metadata = message.metadata as Map<String, dynamic>?;
    if (metadata == null || metadata['gifUrl'] == null) {
      return const SizedBox.shrink();
    }

    final gifUrl = metadata['gifUrl'] as String;
    final gifWidth = (metadata['width'] as num?)?.toDouble() ?? 200.0;
    final gifHeight = (metadata['height'] as num?)?.toDouble() ?? 200.0;

    // Calculate display size - maintain aspect ratio but limit to reasonable size
    final maxDisplayWidth = viewportWidth * 0.6; // Max 60% of screen width
    final maxDisplayHeight = viewportHeight * 0.4; // Max 40% of screen height

    double displayWidth = gifWidth;
    double displayHeight = gifHeight;

    // Scale down if too large
    if (displayWidth > maxDisplayWidth) {
      final scale = maxDisplayWidth / displayWidth;
      displayWidth = maxDisplayWidth;
      displayHeight = displayHeight * scale;
    }

    if (displayHeight > maxDisplayHeight) {
      final scale = maxDisplayHeight / displayHeight;
      displayHeight = maxDisplayHeight;
      displayWidth = displayWidth * scale;
    }

    // Ensure minimum size
    displayWidth = displayWidth.clamp(100.0, maxDisplayWidth);
    displayHeight = displayHeight.clamp(100.0, maxDisplayHeight);

    return Container(
      width: displayWidth,
      height: displayHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          gifUrl,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              color: Colors.grey.shade900,
              child: Center(
                child: CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Container(
              color: Colors.grey.shade900,
              child: const Center(
                child: Icon(
                  Icons.error_outline,
                  color: Colors.grey,
                  size: 40,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Widget for rendering sticker messages
class _StickerMessageWidget extends StatelessWidget {
  final Message message;
  final double viewportWidth;
  final double viewportHeight;

  const _StickerMessageWidget({
    super.key,
    required this.message,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  @override
  Widget build(BuildContext context) {
    // Parse sticker data from metadata
    final metadata = message.metadata as Map<String, dynamic>?;
    if (metadata == null || metadata['stickerUrl'] == null) {
      return const SizedBox.shrink();
    }

    final stickerUrl = metadata['stickerUrl'] as String;
    final stickerWidth = (metadata['width'] as num?)?.toDouble() ?? 200.0;
    final stickerHeight = (metadata['height'] as num?)?.toDouble() ?? 200.0;

    // Calculate display size - maintain aspect ratio but limit to reasonable size
    final maxDisplayWidth = viewportWidth * 0.5; // Max 50% of screen width (smaller than GIFs)
    final maxDisplayHeight = viewportHeight * 0.35; // Max 35% of screen height

    double displayWidth = stickerWidth;
    double displayHeight = stickerHeight;

    // Scale down if too large
    if (displayWidth > maxDisplayWidth) {
      final scale = maxDisplayWidth / displayWidth;
      displayWidth = maxDisplayWidth;
      displayHeight = displayHeight * scale;
    }

    if (displayHeight > maxDisplayHeight) {
      final scale = maxDisplayHeight / displayHeight;
      displayHeight = maxDisplayHeight;
      displayWidth = displayWidth * scale;
    }

    // Ensure minimum size
    displayWidth = displayWidth.clamp(80.0, maxDisplayWidth);
    displayHeight = displayHeight.clamp(80.0, maxDisplayHeight);

    return Container(
      width: displayWidth,
      height: displayHeight,
      child: Image.network(
        stickerUrl,
        fit: BoxFit.contain, // Use contain for stickers to preserve transparency
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.transparent,
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.transparent,
            child: const Center(
              child: Icon(
                Icons.error_outline,
                color: Colors.grey,
                size: 40,
              ),
            ),
          );
        },
      ),
    );
  }
}

// Custom painter for drawing overlay (uses normalized coordinates)
class _DrawingOverlayPainter extends CustomPainter {
  final List<DrawingStroke> strokes;
  final DrawingStroke? currentStroke;
  final double viewportWidth;
  final double viewportHeight;

  _DrawingOverlayPainter({
    required this.strokes,
    required this.currentStroke,
    required this.viewportWidth,
    required this.viewportHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw completed strokes (convert from normalized to pixel coordinates)
    for (var stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < stroke.points.length - 1; i++) {
        final p1 = Offset(
          stroke.points[i].dx * viewportWidth,
          stroke.points[i].dy * viewportHeight,
        );
        final p2 = Offset(
          stroke.points[i + 1].dx * viewportWidth,
          stroke.points[i + 1].dy * viewportHeight,
        );
        canvas.drawLine(p1, p2, paint);
      }
    }

    // Draw current stroke being drawn
    if (currentStroke != null && currentStroke!.points.isNotEmpty) {
      final paint = Paint()
        ..color = currentStroke!.color
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < currentStroke!.points.length - 1; i++) {
        final p1 = Offset(
          currentStroke!.points[i].dx * viewportWidth,
          currentStroke!.points[i].dy * viewportHeight,
        );
        final p2 = Offset(
          currentStroke!.points[i + 1].dx * viewportWidth,
          currentStroke!.points[i + 1].dy * viewportHeight,
        );
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DrawingOverlayPainter oldDelegate) => true;
}
