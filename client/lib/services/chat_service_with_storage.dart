import 'dart:async';
import 'package:client/database/message_database.dart';
import 'package:client/models/message.dart';
import 'package:client/services/chat_service.dart';
import 'package:flutter/foundation.dart';

/// Smart chat service that combines local storage with server sync
/// Provides WhatsApp-style instant message loading
class ChatServiceWithStorage {
  final ChatService _chatService;
  final String conversationId;
  final String currentUserId;
  final String friendId;

  ChatServiceWithStorage({
    required ChatService chatService,
    required this.conversationId,
    required this.currentUserId,
    required this.friendId,
  }) : _chatService = chatService;

  /// Load messages with smart sync strategy
  /// 1. Load from local DB (instant)
  /// 2. Fetch new messages from server in background (unless deleted locally)
  /// 3. Merge and display
  Future<List<Message>> loadMessages() async {
    try {
      // Check if conversation was deleted locally
      final isDeletedLocally = await MessageDatabase.isConversationDeletedLocally(conversationId);

      // Step 1: Load from local database first (instant, no network)
      List<Message> localMessages = await MessageDatabase.getMessages(
        conversationId: conversationId,
        limit: 50,
      );

      if (kDebugMode) {
        print('Loaded ${localMessages.length} messages from local DB');
      }

      // Skip server sync if user deleted messages locally
      if (isDeletedLocally) {
        if (kDebugMode) {
          print('Skipping server sync - conversation deleted locally');
        }
        return localMessages;
      }

      // Step 2: Get latest sequence ID from local DB
      int? latestLocalSeq = await MessageDatabase.getLatestSequenceId(conversationId);

      // Step 3: Fetch new messages from server (only what's missing)
      try {
        final serverResponse = await _chatService.fetchHistory(
          beforeSequence: null, // Get latest messages
          limit: 100,
        );

        List<Message> serverMessages = serverResponse['messages'] as List<Message>;

        if (kDebugMode) {
          print('Fetched ${serverMessages.length} messages from server');
        }

        // Filter out messages we already have
        List<Message> newMessages = [];
        if (latestLocalSeq != null) {
          newMessages = serverMessages
              .where((msg) => msg.sequenceId > latestLocalSeq)
              .toList();
        } else {
          newMessages = serverMessages;
        }

        // Step 4: Save new messages to local DB
        if (newMessages.isNotEmpty) {
          await MessageDatabase.insertMessages(newMessages);

          if (kDebugMode) {
            print('Saved ${newMessages.length} new messages to local DB');
          }

          // Merge with local messages
          localMessages.addAll(newMessages);
          localMessages.sort((a, b) => a.sequenceId.compareTo(b.sequenceId));
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error syncing from server: $e');
        }
        // Still return local messages even if server fails (offline mode)
      }

      return localMessages;
    } catch (e) {
      if (kDebugMode) {
        print('Error loading messages: $e');
      }
      return [];
    }
  }

  /// Load more messages (pagination when scrolling up)
  /// Checks local DB first, then fetches from server if needed
  Future<List<Message>> loadMoreMessages(int beforeSequence) async {
    try {
      // Step 1: Check local DB for older messages
      List<Message> localMessages = await MessageDatabase.getMessages(
        conversationId: conversationId,
        beforeSequence: beforeSequence,
        limit: 50,
      );

      // If we have local messages, return them (instant)
      if (localMessages.isNotEmpty) {
        if (kDebugMode) {
          print('Loaded ${localMessages.length} older messages from local DB');
        }
        return localMessages;
      }

      // Step 2: If no local messages, fetch from server
      try {
        final serverResponse = await _chatService.fetchHistory(
          beforeSequence: beforeSequence,
          limit: 50,
        );

        List<Message> messages = serverResponse['messages'] as List<Message>;

        if (kDebugMode) {
          print('Fetched ${messages.length} older messages from server');
        }

        // Step 3: Cache them locally for future instant access
        if (messages.isNotEmpty) {
          await MessageDatabase.insertMessages(messages);
        }

        return messages;
      } catch (e) {
        if (kDebugMode) {
          print('Error loading more messages: $e');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in loadMoreMessages: $e');
      }
      return [];
    }
  }

  /// Send message with optimistic UI update
  /// Message appears instantly in local DB, then syncs to server
  Future<void> sendMessage(String text) async {
    try {
      // Reset deleted_locally flag (user is chatting again)
      await MessageDatabase.resetDeletedLocally(conversationId);

      // Create optimistic message (temporary, will be replaced by server response)
      final tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      final tempMessage = Message(
        messageId: tempMessageId,
        conversationId: conversationId,
        senderId: currentUserId,
        receiverId: friendId,
        message: text,
        sequenceId: 999999, // High number so it appears at the end while pending
        timestamp: DateTime.now().toIso8601String(),
      );

      // Save locally immediately for instant UI update
      await MessageDatabase.insertMessage(tempMessage);

      if (kDebugMode) {
        print('Saved message to local DB (optimistic)');
      }

      // Send to server
      try {
        final response = await _chatService.sendMessage(text);

        if (kDebugMode) {
          print('Message sent to server: ${response['messageId']}');
        }

        // Delete the temporary message
        await MessageDatabase.deleteMessage(tempMessageId);

        // Insert the real message from server
        final serverMessage = Message(
          messageId: response['messageId'],
          conversationId: conversationId,
          senderId: currentUserId,
          receiverId: friendId,
          message: text,
          sequenceId: _parseSequenceId(response['sequenceId']),
          timestamp: DateTime.now().toIso8601String(),
        );

        await MessageDatabase.insertMessage(serverMessage);

        if (kDebugMode) {
          print('Updated message in local DB with server data');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error sending message to server: $e');
        }
        // Message stays in local DB, can retry later
        // Could implement a retry queue here
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in sendMessage: $e');
      }
      rethrow;
    }
  }

  /// Mark messages as read
  /// Updates local DB immediately, syncs to server in background
  Future<void> markAsRead(int lastSequenceId) async {
    try {
      // Update local DB immediately
      await MessageDatabase.markAsRead(conversationId, lastSequenceId);

      if (kDebugMode) {
        print('Marked messages as read in local DB up to sequence $lastSequenceId');
      }

      // Sync to server in background
      try {
        await _chatService.markAsRead(lastSequenceId);

        if (kDebugMode) {
          print('Synced read status to server');
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error syncing read status to server: $e');
        }
        // Local DB already updated, server sync can be retried later
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in markAsRead: $e');
      }
    }
  }

  /// Get unread message count
  Future<int> getUnreadCount() async {
    try {
      return await MessageDatabase.getUnreadCount(conversationId);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting unread count: $e');
      }
      return 0;
    }
  }

  /// Handle incoming message from WebSocket
  /// Saves to local DB for instant access on next open
  Future<void> handleIncomingMessage(Message message) async {
    try {
      await MessageDatabase.insertMessage(message);

      if (kDebugMode) {
        print('Saved incoming message to local DB: ${message.messageId}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error handling incoming message: $e');
      }
    }
  }

  /// Dispose resources
  void dispose() {
    // No cleanup needed, database stays open for app lifetime
  }

  /// Helper to parse sequence ID (handles both int and string from server)
  static int _parseSequenceId(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}
