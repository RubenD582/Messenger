import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:client/theme/colors.dart';
import 'package:client/theme/spacing.dart';
import 'package:client/theme/typography.dart';
import 'package:client/models/message.dart';
import 'package:client/services/chat_service.dart';
import 'package:client/services/chat_service_with_storage.dart';
import 'package:client/services/api_service.dart';
import 'package:client/services/auth.dart';
import 'package:client/database/message_database.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String friendId;
  final String friendName;
  final String? friendAvatarUrl;
  final ApiService apiService;

  const ChatScreen({
    required this.conversationId,
    required this.friendId,
    required this.friendName,
    required this.apiService,
    this.friendAvatarUrl,
    super.key,
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

  @override
  void initState() {
    super.initState();
    _chatService = ChatService(widget.apiService);
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    _currentUserId = await AuthService.getUserUuid();
    _chatService.init(widget.conversationId, widget.friendId, _currentUserId!);

    // Initialize storage-backed service for local persistence
    _chatServiceWithStorage = ChatServiceWithStorage(
      chatService: _chatService,
      conversationId: widget.conversationId,
      currentUserId: _currentUserId!,
      friendId: widget.friendId,
    );

    _setupListeners();
    _loadMessages();
    _scrollController.addListener(_onScroll);
  }

  void _setupListeners() {
    // Listen for new messages
    _chatService.messageStream.listen((message) {
      setState(() {
        // Remove any temp/optimistic messages (they start with 'temp_')
        _messages.removeWhere((m) => m.messageId.startsWith('temp_'));
        // Remove duplicate if exists (by message_id)
        _messages.removeWhere((m) => m.messageId == message.messageId);
        // Add message and sort by sequence_id to maintain order
        _messages.add(message);
        _messages.sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
      });
      // Save to local DB for persistence
      _chatServiceWithStorage.handleIncomingMessage(message);
      _scrollToBottom();
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
    _chatService.readReceiptStream.listen((receipt) {
      setState(() {
        final lastReadSeq = receipt['lastReadSequenceId'];
        for (var msg in _messages) {
          if (msg.sequenceId <= lastReadSeq && msg.senderId == _currentUserId) {
            msg.isRead = true;
          }
        }
      });
    });
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load from local DB + sync from server (instant + smart sync)
      final messages = await _chatServiceWithStorage.loadMessages();

      setState(() {
        _messages = messages;
        _hasMore = messages.length >= 50;
      });

      // Scroll to bottom after messages are loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Mark messages as read
      if (_messages.isNotEmpty) {
        final lastSeq = _messages.last.sequenceId;
        await _chatServiceWithStorage.markAsRead(lastSeq);
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error loading messages: $error');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Load more messages when scrolling up
  Future<void> _loadMoreMessages() async {
    if (_isLoading || !_hasMore || _messages.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Load older messages (checks local DB first)
      final olderMessages = await _chatServiceWithStorage.loadMoreMessages(
        _messages.first.sequenceId,
      );

      setState(() {
        _messages.insertAll(0, olderMessages);
        _hasMore = olderMessages.length >= 50;
      });
    } catch (error) {
      if (kDebugMode) {
        print('Error loading more messages: $error');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels <= 100) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 20,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();

    // Create optimistic message for instant UI feedback
    final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimisticMessage = Message(
      messageId: tempMessageId,
      conversationId: widget.conversationId,
      senderId: _currentUserId!,
      receiverId: widget.friendId,
      message: text,
      sequenceId: 999999, // High number so it appears at the end
      timestamp: DateTime.now().toIso8601String(),
    );

    setState(() {
      _messages.add(optimisticMessage);
    });
    _scrollToBottom();

    // Send via storage service (will replace optimistic message when server responds)
    await _chatServiceWithStorage.sendMessage(text);
  }

  // Show confirmation dialog before deleting all messages
  Future<bool> _showDeleteConfirmation() async {
    return await showCupertinoDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return CupertinoAlertDialog(
          title: const Text('Delete All Messages'),
          content: Text('Delete all messages with ${widget.friendName} from local storage? This cannot be undone.'),
          actions: [
            CupertinoDialogAction(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              child: const Text('Delete'),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    ) ?? false;
  }

  // Delete all messages from local storage (soft delete - WhatsApp/Discord style)
  Future<void> _deleteAllMessages() async {
    final shouldDelete = await _showDeleteConfirmation();

    if (!shouldDelete) return;

    try {
      // Soft delete from local database (marks as deleted, doesn't remove)
      await MessageDatabase.deleteConversation(
        widget.conversationId,
        userId: _currentUserId,
      );

      // Clear messages from UI
      setState(() {
        _messages.clear();
      });

      if (kDebugMode) {
        print('Soft-deleted all messages for conversation: ${widget.conversationId}');
      }

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Messages deleted (recoverable for 7 days)'),
            backgroundColor: Colors.black87,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error deleting messages: $error');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete messages'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 32, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: const AssetImage('assets/noprofile.png'),
              backgroundColor: Colors.transparent,
            ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.friendName,
                style: AppTypography.body.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
              if (_isTyping)
                Text(
                  'typing...',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.primary,
                    fontStyle: FontStyle.italic,
                  ),
                ),
            ],
          ),
        ),
                  ],
                ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
              onPressed: () {
                showCupertinoModalPopup(
                  context: context,
                  builder: (BuildContext context) => CupertinoActionSheet(
                    actions: [
                      CupertinoActionSheetAction(
                        onPressed: () {
                          Navigator.pop(context);
                          _deleteAllMessages();
                        },
                        isDestructiveAction: true,
                        child: const Text(
                          'Delete Messages',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ],
                    cancelButton: CupertinoActionSheetAction(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      body: Column(
        children: [
          // Message list
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: Spacing.md, horizontal: 8),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == 0 && _isLoading) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(Spacing.md),
                              child: CircularProgressIndicator(),
                            ),
                          );
                        }

                        final messageIndex = _isLoading ? index - 1 : index;
                        final message = _messages[messageIndex];
                        final isMe = message.senderId == _currentUserId;
                        final isLastMessage = messageIndex == _messages.length - 1;

                        // Check if message is grouped with previous/next messages
                        final isFirstInGroup = messageIndex == 0 ||
                            _messages[messageIndex - 1].senderId != message.senderId;
                        final isLastInGroup = messageIndex == _messages.length - 1 ||
                            _messages[messageIndex + 1].senderId != message.senderId;

                        // Check if we need a timestamp separator (30+ minutes apart)
                        bool showTimestamp = false;
                        if (messageIndex > 0) {
                          final currentTime = DateTime.parse(message.timestamp);
                          final previousTime = DateTime.parse(_messages[messageIndex - 1].timestamp);
                          final difference = currentTime.difference(previousTime);
                          showTimestamp = difference.inMinutes >= 30;
                        }

                        return Column(
                          key: ValueKey(message.messageId),
                          children: [
                            if (showTimestamp)
                              _buildTimestampSeparator(message.timestamp),
                            _MessageBubbleWithGradient(
                              key: ValueKey('bubble_${message.messageId}'),
                              message: message,
                              isMe: isMe,
                              isLastMessage: isLastMessage,
                              isFirstInGroup: isFirstInGroup,
                              isLastInGroup: isLastInGroup,
                              scrollController: _scrollController,
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),

          // Input field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 0),
            decoration: const BoxDecoration(
              color: Colors.black,
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: AppTypography.body.copyWith(color: Colors.white),
                      cursorColor: const Color(0xFF5856D6),
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: AppTypography.body.copyWith(
                          color: AppColors.textTertiary.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w500
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
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      color: Color(0xFF5856D6),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_upward, color: Colors.white, size: 19),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
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
  final ScrollController scrollController;

  const _MessageBubbleWithGradient({
    super.key,
    required this.message,
    required this.isMe,
    required this.isLastMessage,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.scrollController,
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
    widget.scrollController.addListener(_updateColor);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateColor();
      // Force another update after a short delay to ensure positions are settled
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _updateColor();
      });
    });
  }

  @override
  void didUpdateWidget(_MessageBubbleWithGradient oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update colors when widget updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateColor();
    });
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_updateColor);
    super.dispose();
  }

  Color _calculateColorAtPosition(double relativeY, double viewportHeight) {
    final percentage = (relativeY / viewportHeight).clamp(0.0, 1.0);
    final adjustedPercentage = Curves.easeInOutCubic.transform(percentage);
    return Color.lerp(
      const Color(0xFF007AFF), // Blue at top
      const Color(0xFF5856D6), // Purple at bottom
      adjustedPercentage,
    )!;
  }

  void _updateColor() {
    if (!widget.isMe) {
      setState(() {
        _bubbleColorTop = AppColors.surfaceVariant;
        _bubbleColorBottom = AppColors.surfaceVariant;
      });
      return;
    }

    final RenderBox? renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final bubbleHeight = renderBox.size.height;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate position as percentage of viewport (0.0 at top, 1.0 at bottom)
    // Adjust for app bar height and bottom input field
    final appBarHeight = kToolbarHeight + MediaQuery.of(context).padding.top;
    final bottomInputHeight = 60.0 + MediaQuery.of(context).padding.bottom;
    final viewportHeight = screenHeight - appBarHeight - bottomInputHeight;

    // Calculate colors for top and bottom of the bubble
    final relativeYTop = (position.dy - appBarHeight).clamp(0.0, viewportHeight);
    final relativeYBottom = (position.dy + bubbleHeight - appBarHeight).clamp(0.0, viewportHeight);

    final topColor = _calculateColorAtPosition(relativeYTop, viewportHeight);
    final bottomColor = _calculateColorAtPosition(relativeYBottom, viewportHeight);

    if (mounted) {
      setState(() {
        _bubbleColorTop = topColor;
        _bubbleColorBottom = bottomColor;
      });
    }
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
        bubbleColorTop: _bubbleColorTop,
        bubbleColorBottom: _bubbleColorBottom,
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
  final Color bubbleColorTop;
  final Color bubbleColorBottom;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.isLastMessage,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.bubbleColorTop,
    required this.bubbleColorBottom,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Message bubble
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              constraints: BoxConstraints(
                minWidth: 40,
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

            // Read status below bubble (only show on last message)
            if (isMe && isLastMessage)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                child: Text(
                  _getMessageStatusWithTime(message),
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textTertiary.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  BorderRadius _getBorderRadius() {
    const fullRadius = 18.0;
    const tightRadius = 4.0;

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

  String _getRelativeTime(String timestamp) {
    try {
      final messageTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(messageTime);

      if (difference.inSeconds < 30) {
        return 'just now';
      } else if (difference.inMinutes < 1) {
        return '${difference.inSeconds}s ago';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${(difference.inDays / 7).floor()}w ago';
      }
    } catch (e) {
      return '';
    }
  }

  String _getMessageStatusWithTime(Message message) {
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
