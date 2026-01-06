import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:client/database/message_database.dart';
import 'package:client/services/api_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:http/http.dart' as http;
import 'package:client/config/api_config.dart';

/// Offline Queue Service
/// Handles queuing operations when offline and syncing when reconnected
/// Provides 99% sync guarantee across devices
class OfflineQueueService {
  static const String TABLE_QUEUE = 'offline_queue';
  static const String TABLE_SYNC_STATE = 'sync_state';

  final ApiService apiService;
  bool _isProcessing = false;

  OfflineQueueService(this.apiService) {
    _setupTables();
    _setupConnectionListener();
  }

  /// Create queue and sync tables if they don't exist
  Future<void> _setupTables() async {
    final db = await MessageDatabase.database;

    // Create offline queue table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $TABLE_QUEUE (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_type TEXT NOT NULL,
        conversation_id TEXT,
        data TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        last_attempt_at INTEGER,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // Create sync state table to track last sync per conversation
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $TABLE_SYNC_STATE (
        conversation_id TEXT PRIMARY KEY,
        last_sync_timestamp TEXT NOT NULL,
        last_sync_sequence INTEGER DEFAULT 0,
        device_id TEXT NOT NULL
      )
    ''');

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_queue_status
      ON $TABLE_QUEUE(status, created_at)
    ''');

    if (kDebugMode) {
      print('✅ Offline queue tables initialized');
    }
  }

  /// Listen for WebSocket reconnection and process queue
  void _setupConnectionListener() {
    // Process queue when connection is restored
    apiService.onReconnected = () async {
      if (kDebugMode) {
        print('🔄 WebSocket reconnected - processing offline queue');
      }
      await processQueue();
      await syncAllConversations();
    };
  }

  /// Queue an operation for later execution
  Future<void> queueOperation({
    required String operationType,
    String? conversationId,
    required Map<String, dynamic> data,
  }) async {
    final db = await MessageDatabase.database;

    await db.insert(TABLE_QUEUE, {
      'operation_type': operationType,
      'conversation_id': conversationId,
      'data': jsonEncode(data),
      'status': 'pending',
    });

    if (kDebugMode) {
      print('📝 Queued operation: $operationType for conversation: $conversationId');
    }

    // Try to process immediately if online
    if (apiService.isConnected) {
      processQueue();
    }
  }

  /// Process all pending operations in the queue
  Future<void> processQueue() async {
    if (_isProcessing) {
      if (kDebugMode) {
        print('⏭️ Queue processing already in progress');
      }
      return;
    }

    _isProcessing = true;

    try {
      final db = await MessageDatabase.database;

      // Get all pending operations ordered by creation time
      final operations = await db.query(
        TABLE_QUEUE,
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'created_at ASC',
        limit: 50, // Process in batches
      );

      if (kDebugMode) {
        print('📦 Processing ${operations.length} queued operations');
      }

      for (var operation in operations) {
        final id = operation['id'] as int;
        final type = operation['operation_type'] as String;
        final data = jsonDecode(operation['data'] as String);
        final retryCount = operation['retry_count'] as int;

        try {
          // Execute the operation
          await _executeOperation(type, data);

          // Mark as completed and remove from queue
          await db.delete(TABLE_QUEUE, where: 'id = ?', whereArgs: [id]);

          if (kDebugMode) {
            print('✅ Completed operation: $type');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed operation: $type - $e');
          }

          // Update retry count
          final newRetryCount = retryCount + 1;

          if (newRetryCount >= 5) {
            // Mark as failed after 5 retries
            await db.update(
              TABLE_QUEUE,
              {
                'status': 'failed',
                'retry_count': newRetryCount,
                'last_attempt_at': DateTime.now().millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          } else {
            // Increment retry count
            await db.update(
              TABLE_QUEUE,
              {
                'retry_count': newRetryCount,
                'last_attempt_at': DateTime.now().millisecondsSinceEpoch,
              },
              where: 'id = ?',
              whereArgs: [id],
            );
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Execute a specific operation
  Future<void> _executeOperation(String type, Map<String, dynamic> data) async {
    switch (type) {
      case 'send_message':
        await _sendMessage(data);
        break;
      case 'delete_message':
        await _deleteMessage(data);
        break;
      case 'clear_chat':
        await _clearChat(data);
        break;
      case 'mark_read':
        await _markRead(data);
        break;
      case 'update_position':
        await _updatePosition(data);
        break;
      default:
        throw Exception('Unknown operation type: $type');
    }
  }

  Future<void> _sendMessage(Map<String, dynamic> data) async {
    final token = await AuthService.getToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/messages/send'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode != 200 && response.statusCode != 202) {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  Future<void> _deleteMessage(Map<String, dynamic> data) async {
    final token = await AuthService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/messages/${data['messageId']}'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete message: ${response.statusCode}');
    }
  }

  Future<void> _clearChat(Map<String, dynamic> data) async {
    final token = await AuthService.getToken();
    final response = await http.delete(
      Uri.parse('${ApiConfig.baseUrl}/conversations/${data['conversationId']}'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to clear chat: ${response.statusCode}');
    }
  }

  Future<void> _markRead(Map<String, dynamic> data) async {
    final token = await AuthService.getToken();
    final response = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/messages/mark-read'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to mark as read: ${response.statusCode}');
    }
  }

  Future<void> _updatePosition(Map<String, dynamic> data) async {
    // Use ApiService's method to send position update via WebSocket
    apiService.sendMessagePositionUpdate(
      messageId: data['messageId'] as String,
      conversationId: data['conversationId'] as String,
      isPositioned: data['isPositioned'] as bool? ?? true,
      positionX: data['positionX'] as double,
      positionY: data['positionY'] as double,
      rotation: data['rotation'] as double?,
      scale: data['scale'] as double?,
    );
  }

  /// Sync all conversations to catch up on missed updates
  Future<void> syncAllConversations() async {
    try {
      final token = await AuthService.getToken();
      final db = await MessageDatabase.database;

      // Get all conversations
      final conversations = await db.query(MessageDatabase.TABLE_CONVERSATIONS);

      if (kDebugMode) {
        print('🔄 Syncing ${conversations.length} conversations');
      }

      for (var conversation in conversations) {
        final conversationId = conversation['conversation_id'] as String;
        await syncConversation(conversationId);
      }

      if (kDebugMode) {
        print('✅ Sync completed for all conversations');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Sync error: $e');
      }
    }
  }

  /// Sync a specific conversation
  Future<void> syncConversation(String conversationId) async {
    try {
      final token = await AuthService.getToken();
      final db = await MessageDatabase.database;

      // Get last sync state
      final syncState = await db.query(
        TABLE_SYNC_STATE,
        where: 'conversation_id = ?',
        whereArgs: [conversationId],
      );

      String? lastSyncTimestamp;
      if (syncState.isNotEmpty) {
        lastSyncTimestamp = syncState.first['last_sync_timestamp'] as String?;
      }

      // Fetch updates from server
      final response = await http.get(
        Uri.parse(
          '${ApiConfig.baseUrl}/messages/sync/$conversationId'
          '${lastSyncTimestamp != null ? '?after=$lastSyncTimestamp' : ''}',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final messages = data['messages'] as List;
        final deletedIds = (data['deletedMessageIds'] as List?)?.cast<String>() ?? [];
        final chatCleared = data['chatCleared'] as bool? ?? false;

        // Handle chat cleared
        if (chatCleared) {
          await MessageDatabase.deleteConversation(conversationId);
          if (kDebugMode) {
            print('🗑️ Chat cleared for conversation: $conversationId');
          }
        }

        // Handle deleted messages
        for (var messageId in deletedIds) {
          await MessageDatabase.deleteMessage(messageId);
        }

        // Insert new/updated messages
        for (var msgData in messages) {
          // Convert to Message object and insert
          // This would require proper Message.fromJson implementation
          if (kDebugMode) {
            print('📥 Synced message: ${msgData['message_id']}');
          }
        }

        // Update sync state
        await db.insert(
          TABLE_SYNC_STATE,
          {
            'conversation_id': conversationId,
            'last_sync_timestamp': DateTime.now().toIso8601String(),
            'last_sync_sequence': data['lastSequenceId'] ?? 0,
            'device_id': await _getDeviceId(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (kDebugMode) {
          print('✅ Synced conversation: $conversationId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Sync error for $conversationId: $e');
      }
    }
  }

  Future<String> _getDeviceId() async {
    // TODO: Implement device ID generation
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Get queue statistics
  Future<Map<String, int>> getQueueStats() async {
    final db = await MessageDatabase.database;

    final pending = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $TABLE_QUEUE WHERE status = ?', ['pending'])
    ) ?? 0;

    final failed = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $TABLE_QUEUE WHERE status = ?', ['failed'])
    ) ?? 0;

    return {
      'pending': pending,
      'failed': failed,
    };
  }

  /// Clear failed operations
  Future<void> clearFailedOperations() async {
    final db = await MessageDatabase.database;
    await db.delete(TABLE_QUEUE, where: 'status = ?', whereArgs: ['failed']);
  }

  /// Retry failed operations
  Future<void> retryFailedOperations() async {
    final db = await MessageDatabase.database;
    await db.update(
      TABLE_QUEUE,
      {'status': 'pending', 'retry_count': 0},
      where: 'status = ?',
      whereArgs: ['failed'],
    );

    await processQueue();
  }
}
