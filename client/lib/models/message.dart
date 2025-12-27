// Message model for chat system
class Message {
  final String messageId;
  final String senderId;
  final String receiverId;
  final String conversationId;
  final String message;
  final int sequenceId;
  final String timestamp;
  final String messageType;
  final Map<String, dynamic>? metadata;
  bool isRead;
  String? deliveredAt;

  Message({
    required this.messageId,
    required this.senderId,
    required this.receiverId,
    required this.conversationId,
    required this.message,
    required this.sequenceId,
    required this.timestamp,
    this.messageType = 'text',
    this.metadata,
    this.isRead = false,
    this.deliveredAt,
  });

  // Factory constructor to create Message from JSON (API response)
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      messageId: json['messageId'] ?? json['message_id'] ?? json['id'] ?? '',
      senderId: json['senderId'] ?? json['sender_id'] ?? '',
      receiverId: json['receiverId'] ?? json['receiver_id'] ?? '',
      conversationId: json['conversationId'] ?? json['conversation_id'] ?? '',
      message: json['message'] ?? '',
      sequenceId: _parseSequenceId(json['sequenceId'] ?? json['sequence_id']),
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      messageType: json['messageType'] ?? json['message_type'] ?? 'text',
      metadata: json['metadata'] as Map<String, dynamic>?,
      isRead: json['read_at'] != null || json['readAt'] != null,
      deliveredAt: json['delivered_at'] ?? json['deliveredAt'],
    );
  }

  // Helper to parse sequence ID (handles both int and string from DB)
  static int _parseSequenceId(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // Convert Message to JSON (for sending to API)
  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'receiverId': receiverId,
      'conversationId': conversationId,
      'message': message,
      'sequenceId': sequenceId,
      'timestamp': timestamp,
      'messageType': messageType,
      'metadata': metadata,
      'isRead': isRead,
      'deliveredAt': deliveredAt,
    };
  }

  // Copy with method for updating message properties
  Message copyWith({
    String? messageId,
    String? senderId,
    String? receiverId,
    String? conversationId,
    String? message,
    int? sequenceId,
    String? timestamp,
    String? messageType,
    Map<String, dynamic>? metadata,
    bool? isRead,
    String? deliveredAt,
  }) {
    return Message(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      conversationId: conversationId ?? this.conversationId,
      message: message ?? this.message,
      sequenceId: sequenceId ?? this.sequenceId,
      timestamp: timestamp ?? this.timestamp,
      messageType: messageType ?? this.messageType,
      metadata: metadata ?? this.metadata,
      isRead: isRead ?? this.isRead,
      deliveredAt: deliveredAt ?? this.deliveredAt,
    );
  }

  @override
  String toString() {
    return 'Message(messageId: $messageId, sender: $senderId, receiver: $receiverId, message: $message, seq: $sequenceId, read: $isRead)';
  }
}
