import 'dart:convert';
import 'dart:io';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:client/models/message.dart';
import 'package:flutter/foundation.dart';

class MessageDatabase {
  static Database? _database;
  static const String DB_NAME = 'messages.db';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // Encryption
  static encrypt.Encrypter? _encrypter;
  static encrypt.IV? _iv;

  // Tables
  static const String TABLE_MESSAGES = 'messages';
  static const String TABLE_CONVERSATIONS = 'conversations';

  // Initialize database with encryption
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    // Get app directory
    String path = join(await getDatabasesPath(), DB_NAME);

    // Get or create encryption password
    String? password = await _getOrCreatePassword();

    // Initialize encryption for message content
    await _initEncryption();

    // Open encrypted database
    return await openDatabase(
      path,
      password: password,
      version: 3,
      onCreate: _createTables,
      onUpgrade: _onUpgrade,
    );
  }

  // Get or create database password
  static Future<String> _getOrCreatePassword() async {
    try {
      String? password = await _secureStorage.read(key: 'db_password');

      if (password == null) {
        // Generate strong random password
        password = _generateSecurePassword();
        await _secureStorage.write(key: 'db_password', value: password);
      }

      return password;
    } catch (e) {
      // Fallback for macOS development (keychain access issues)
      // In production, this should use proper secure storage
      return 'dev_password_${base64Encode(encrypt.Key.fromSecureRandom(16).bytes)}';
    }
  }

  // Initialize message content encryption (additional layer)
  static Future<void> _initEncryption() async {
    try {
      String? keyString = await _secureStorage.read(key: 'message_key');
      String? ivString = await _secureStorage.read(key: 'message_iv');

      if (keyString == null || ivString == null) {
        final key = encrypt.Key.fromSecureRandom(32);
        final iv = encrypt.IV.fromSecureRandom(16);

        await _secureStorage.write(key: 'message_key', value: base64Encode(key.bytes));
        await _secureStorage.write(key: 'message_iv', value: base64Encode(iv.bytes));

        _encrypter = encrypt.Encrypter(encrypt.AES(key));
        _iv = iv;
      } else {
        final key = encrypt.Key(base64Decode(keyString));
        final iv = encrypt.IV(base64Decode(ivString));

        _encrypter = encrypt.Encrypter(encrypt.AES(key));
        _iv = iv;
      }
    } catch (e) {
      // Fallback for macOS development (keychain access issues)
      // In production, this should use proper secure storage
      final key = encrypt.Key.fromSecureRandom(32);
      final iv = encrypt.IV.fromSecureRandom(16);

      _encrypter = encrypt.Encrypter(encrypt.AES(key));
      _iv = iv;
    }
  }

  // Generate secure random password
  static String _generateSecurePassword() {
    final random = encrypt.Key.fromSecureRandom(32);
    return base64Encode(random.bytes);
  }

  // Create tables
  static Future<void> _createTables(Database db, int version) async {
    // Messages table
    await db.execute('''
      CREATE TABLE $TABLE_MESSAGES (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT UNIQUE NOT NULL,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        receiver_id TEXT NOT NULL,
        encrypted_message TEXT NOT NULL,
        sequence_id INTEGER NOT NULL,
        timestamp TEXT NOT NULL,
        message_type TEXT DEFAULT 'text',
        metadata TEXT,
        is_read INTEGER DEFAULT 0,
        delivered_at TEXT,
        read_at TEXT,
        is_sent INTEGER DEFAULT 1,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),

        UNIQUE(conversation_id, sequence_id)
      )
    ''');

    // Conversations table (for quick lookup)
    await db.execute('''
      CREATE TABLE $TABLE_CONVERSATIONS (
        conversation_id TEXT PRIMARY KEY,
        other_user_id TEXT NOT NULL,
        other_user_name TEXT,
        last_message TEXT,
        last_message_time TEXT,
        unread_count INTEGER DEFAULT 0,
        deleted_locally INTEGER DEFAULT 0,
        updated_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Indexes for performance
    await db.execute('''
      CREATE INDEX idx_messages_conversation
      ON $TABLE_MESSAGES(conversation_id, sequence_id DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_messages_timestamp
      ON $TABLE_MESSAGES(timestamp DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_conversations_updated
      ON $TABLE_CONVERSATIONS(updated_at DESC)
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add deleted_locally column to conversations table
      await db.execute('''
        ALTER TABLE $TABLE_CONVERSATIONS
        ADD COLUMN deleted_locally INTEGER DEFAULT 0
      ''');
    }

    if (oldVersion < 3) {
      // Add soft delete columns to messages table (WhatsApp/Discord style)
      await db.execute('''
        ALTER TABLE $TABLE_MESSAGES
        ADD COLUMN is_deleted INTEGER DEFAULT 0
      ''');

      await db.execute('''
        ALTER TABLE $TABLE_MESSAGES
        ADD COLUMN deleted_at TEXT
      ''');

      await db.execute('''
        ALTER TABLE $TABLE_MESSAGES
        ADD COLUMN deleted_by TEXT
      ''');
    }
  }

  // Encrypt message content
  static String _encryptMessage(String message) {
    if (_encrypter == null || _iv == null) {
      throw Exception('Encryption not initialized');
    }
    return _encrypter!.encrypt(message, iv: _iv).base64;
  }

  // Decrypt message content
  static String _decryptMessage(String encryptedMessage) {
    if (_encrypter == null || _iv == null) {
      throw Exception('Encryption not initialized');
    }
    return _encrypter!.decrypt64(encryptedMessage, iv: _iv);
  }

  // Insert message
  static Future<void> insertMessage(Message message) async {
    final db = await database;

    await db.insert(
      TABLE_MESSAGES,
      {
        'message_id': message.messageId,
        'conversation_id': message.conversationId,
        'sender_id': message.senderId,
        'receiver_id': message.receiverId,
        'encrypted_message': _encryptMessage(message.message),
        'sequence_id': message.sequenceId,
        'timestamp': message.timestamp,
        'message_type': message.messageType,
        'metadata': message.metadata != null ? jsonEncode(message.metadata) : null,
        'is_read': message.isRead ? 1 : 0,
        'delivered_at': message.deliveredAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Update conversation
    await _updateConversation(message);
  }

  // Batch insert messages (for sync)
  static Future<void> insertMessages(List<Message> messages) async {
    final db = await database;
    final batch = db.batch();

    for (var message in messages) {
      batch.insert(
        TABLE_MESSAGES,
        {
          'message_id': message.messageId,
          'conversation_id': message.conversationId,
          'sender_id': message.senderId,
          'receiver_id': message.receiverId,
          'encrypted_message': _encryptMessage(message.message),
          'sequence_id': message.sequenceId,
          'timestamp': message.timestamp,
          'message_type': message.messageType,
          'metadata': message.metadata != null ? jsonEncode(message.metadata) : null,
          'is_read': message.isRead ? 1 : 0,
          'delivered_at': message.deliveredAt,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    await batch.commit(noResult: true);
  }

  // Get messages for conversation (paginated)
  // Excludes soft-deleted messages (WhatsApp/Discord style)
  static Future<List<Message>> getMessages({
    required String conversationId,
    int? beforeSequence,
    int limit = 50,
    bool includeDeleted = false, // Option to include deleted messages (for recovery)
  }) async {
    final db = await database;

    String whereClause = 'conversation_id = ?';
    List<dynamic> whereArgs = [conversationId];

    // Filter out soft-deleted messages by default
    if (!includeDeleted) {
      whereClause += ' AND (is_deleted = 0 OR is_deleted IS NULL)';
    }

    if (beforeSequence != null) {
      whereClause += ' AND sequence_id < ?';
      whereArgs.add(beforeSequence);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      TABLE_MESSAGES,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'sequence_id DESC',
      limit: limit,
    );

    return maps.map((map) => _messageFromMap(map)).toList().reversed.toList();
  }

  // Get messages after a sequence (for sync)
  // Excludes soft-deleted messages
  static Future<List<Message>> getMessagesAfter({
    required String conversationId,
    int? afterSequence,
    bool includeDeleted = false,
  }) async {
    final db = await database;

    String whereClause = 'conversation_id = ?';
    List<dynamic> whereArgs = [conversationId];

    // Filter out soft-deleted messages by default
    if (!includeDeleted) {
      whereClause += ' AND (is_deleted = 0 OR is_deleted IS NULL)';
    }

    if (afterSequence != null) {
      whereClause += ' AND sequence_id > ?';
      whereArgs.add(afterSequence);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      TABLE_MESSAGES,
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'sequence_id ASC',
    );

    return maps.map((map) => _messageFromMap(map)).toList();
  }

  // Get latest sequence ID for conversation (excludes deleted messages)
  static Future<int?> getLatestSequenceId(String conversationId) async {
    final db = await database;

    final result = await db.query(
      TABLE_MESSAGES,
      columns: ['MAX(sequence_id) as max_seq'],
      where: 'conversation_id = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
      whereArgs: [conversationId],
    );

    if (result.isEmpty || result.first['max_seq'] == null) {
      return null;
    }

    return result.first['max_seq'] as int;
  }

  // Update conversation metadata
  static Future<void> _updateConversation(Message message) async {
    final db = await database;

    await db.insert(
      TABLE_CONVERSATIONS,
      {
        'conversation_id': message.conversationId,
        'other_user_id': message.receiverId,
        'last_message': _encryptMessage(message.message),
        'last_message_time': message.timestamp,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Delete message by message_id (for removing temp optimistic messages)
  static Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete(
      TABLE_MESSAGES,
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  // Soft delete entire conversation (WhatsApp/Discord style)
  // Marks messages as deleted instead of removing them permanently
  static Future<void> deleteConversation(String conversationId, {String? userId}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Soft delete all messages in the conversation (WhatsApp Android style)
    await db.update(
      TABLE_MESSAGES,
      {
        'is_deleted': 1,
        'deleted_at': now,
        'deleted_by': userId ?? 'user',
      },
      where: 'conversation_id = ? AND is_deleted = 0',
      whereArgs: [conversationId],
    );

    // Mark conversation as deleted locally (prevents auto-sync from server)
    await db.insert(
      TABLE_CONVERSATIONS,
      {
        'conversation_id': conversationId,
        'other_user_id': '',
        'deleted_locally': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Hard delete conversation (permanent removal, like WhatsApp iPhone VACUUM)
  // Only use this for periodic cleanup or permanent deletion
  static Future<void> permanentlyDeleteConversation(String conversationId) async {
    final db = await database;

    // Permanently remove all messages
    await db.delete(
      TABLE_MESSAGES,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    // Remove conversation metadata
    await db.delete(
      TABLE_CONVERSATIONS,
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  // Check if conversation was deleted locally
  static Future<bool> isConversationDeletedLocally(String conversationId) async {
    final db = await database;

    final result = await db.query(
      TABLE_CONVERSATIONS,
      columns: ['deleted_locally'],
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );

    if (result.isEmpty) return false;

    return (result.first['deleted_locally'] as int? ?? 0) == 1;
  }

  // Reset deleted_locally flag (e.g., when user sends a new message)
  static Future<void> resetDeletedLocally(String conversationId) async {
    final db = await database;

    await db.update(
      TABLE_CONVERSATIONS,
      {'deleted_locally': 0},
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  // Mark messages as read
  static Future<void> markAsRead(String conversationId, int upToSequenceId) async {
    final db = await database;

    await db.update(
      TABLE_MESSAGES,
      {'is_read': 1, 'read_at': DateTime.now().toIso8601String()},
      where: 'conversation_id = ? AND sequence_id <= ? AND is_read = 0',
      whereArgs: [conversationId, upToSequenceId],
    );

    // Update unread count
    await db.update(
      TABLE_CONVERSATIONS,
      {'unread_count': 0},
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
    );
  }

  // Get unread count
  static Future<int> getUnreadCount(String conversationId) async {
    final db = await database;

    final result = await db.query(
      TABLE_MESSAGES,
      columns: ['COUNT(*) as count'],
      where: 'conversation_id = ? AND is_read = 0',
      whereArgs: [conversationId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Cleanup soft-deleted messages (Discord tombstone style)
  // Permanently removes messages that have been soft-deleted for more than X days
  static Future<int> cleanupDeletedMessages({int daysToKeep = 7}) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(Duration(days: daysToKeep)).toIso8601String();

    // Permanently delete messages that were soft-deleted more than X days ago
    final count = await db.delete(
      TABLE_MESSAGES,
      where: 'is_deleted = 1 AND deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoffTime],
    );

    if (kDebugMode) {
      print('Cleaned up $count soft-deleted messages older than $daysToKeep days');
    }

    return count;
  }

  // VACUUM database (WhatsApp iPhone style)
  // Compacts database and reclaims space from deleted messages
  static Future<void> vacuumDatabase() async {
    final db = await database;
    await db.execute('VACUUM');

    if (kDebugMode) {
      print('Database vacuumed - reclaimed space from deleted messages');
    }
  }

  // Auto-cleanup old messages (for both read and deleted)
  static Future<void> clearOldMessages({int daysToKeep = 90}) async {
    final db = await database;
    final cutoffTime = DateTime.now().subtract(Duration(days: daysToKeep));

    // Only hard delete very old messages (not soft-deleted ones, they're handled by cleanupDeletedMessages)
    await db.delete(
      TABLE_MESSAGES,
      where: 'timestamp < ? AND (is_deleted = 0 OR is_deleted IS NULL)',
      whereArgs: [cutoffTime.toIso8601String()],
    );
  }

  // Restore soft-deleted messages (undo deletion)
  static Future<void> restoreDeletedMessages(String conversationId) async {
    final db = await database;

    await db.update(
      TABLE_MESSAGES,
      {
        'is_deleted': 0,
        'deleted_at': null,
        'deleted_by': null,
      },
      where: 'conversation_id = ? AND is_deleted = 1',
      whereArgs: [conversationId],
    );

    // Reset deleted_locally flag
    await resetDeletedLocally(conversationId);

    if (kDebugMode) {
      print('Restored deleted messages for conversation: $conversationId');
    }
  }

  // Get database size
  static Future<int> getDatabaseSize() async {
    final path = join(await getDatabasesPath(), DB_NAME);
    final file = File(path);
    if (await file.exists()) {
      return await file.length();
    }
    return 0;
  }

  // Get deletion statistics (for debugging/analytics)
  static Future<Map<String, int>> getDeletionStats() async {
    final db = await database;

    final totalMessages = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $TABLE_MESSAGES')
    ) ?? 0;

    final deletedMessages = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $TABLE_MESSAGES WHERE is_deleted = 1')
    ) ?? 0;

    final activeMessages = totalMessages - deletedMessages;

    return {
      'total': totalMessages,
      'active': activeMessages,
      'deleted': deletedMessages,
    };
  }

  // Convert database map to Message object
  static Message _messageFromMap(Map<String, dynamic> map) {
    return Message(
      messageId: map['message_id'],
      conversationId: map['conversation_id'],
      senderId: map['sender_id'],
      receiverId: map['receiver_id'],
      message: _decryptMessage(map['encrypted_message']),
      sequenceId: map['sequence_id'],
      timestamp: map['timestamp'],
      messageType: map['message_type'] ?? 'text',
      metadata: map['metadata'] != null ? jsonDecode(map['metadata']) : null,
      isRead: map['is_read'] == 1,
      deliveredAt: map['delivered_at'],
    );
  }

  // Close database
  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
