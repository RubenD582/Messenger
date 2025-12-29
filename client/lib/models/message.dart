import 'dart:convert';

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

  // Position data for interactive placement
  double? positionX;        // null = normal flow, 0.0-1.0 = positioned (percentage)
  double? positionY;        // null = normal flow, 0.0-1.0 = positioned (percentage)
  bool isPositioned;        // false = normal message, true = manually positioned
  String? positionedBy;     // userId who positioned the message
  String? positionedAt;     // When the message was positioned

  // Transform data for rotation and scaling
  double? rotation;         // Rotation in radians (null = 0, no rotation)
  double? scale;            // Scale factor (null = 1.0, normal size)

  // For smooth animation (interpolation)
  double? targetX;          // Target position for interpolation
  double? targetY;          // Target position for interpolation

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
    this.positionX,
    this.positionY,
    this.isPositioned = false,
    this.positionedBy,
    this.positionedAt,
    this.rotation,
    this.scale,
    this.targetX,
    this.targetY,
  });

  // Factory constructor to create Message from JSON (API response)
  factory Message.fromJson(Map<String, dynamic> json) {
    // Parse metadata - handle both Map and JSON string
    Map<String, dynamic>? parsedMetadata;
    final metadataValue = json['metadata'];
    if (metadataValue != null) {
      if (metadataValue is Map) {
        parsedMetadata = Map<String, dynamic>.from(metadataValue);
      } else if (metadataValue is String && metadataValue.isNotEmpty) {
        try {
          parsedMetadata = Map<String, dynamic>.from(
            _parseJson(metadataValue) as Map
          );
        } catch (e) {
          // If parsing fails, leave as null
          parsedMetadata = null;
        }
      }
    }

    return Message(
      messageId: json['messageId'] ?? json['message_id'] ?? json['id'] ?? '',
      senderId: json['senderId'] ?? json['sender_id'] ?? '',
      receiverId: json['receiverId'] ?? json['receiver_id'] ?? '',
      conversationId: json['conversationId'] ?? json['conversation_id'] ?? '',
      message: json['message'] ?? '',
      sequenceId: _parseSequenceId(json['sequenceId'] ?? json['sequence_id']),
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
      messageType: json['messageType'] ?? json['message_type'] ?? 'text',
      metadata: parsedMetadata,
      isRead: json['read_at'] != null || json['readAt'] != null,
      deliveredAt: json['delivered_at'] ?? json['deliveredAt'],
      positionX: _parseDouble(json['positionX'] ?? json['position_x']),
      positionY: _parseDouble(json['positionY'] ?? json['position_y']),
      isPositioned: _parseBool(json['isPositioned'] ?? json['is_positioned']),
      positionedBy: json['positionedBy'] ?? json['positioned_by'],
      positionedAt: json['positionedAt'] ?? json['positioned_at'],
      rotation: _parseDouble(json['rotation']),
      scale: _parseDouble(json['scale']),
    );
  }

  // Helper to parse sequence ID (handles both int and string from DB)
  static int _parseSequenceId(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  // Helper to parse double values (handles string from DB)
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  // Helper to parse boolean values (handles int/string from DB)
  static bool _parseBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value != 0;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  // Helper to parse JSON string
  static dynamic _parseJson(String jsonString) {
    try {
      return jsonDecode(jsonString);
    } catch (e) {
      return null;
    }
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
      'positionX': positionX,
      'positionY': positionY,
      'isPositioned': isPositioned,
      'positionedBy': positionedBy,
      'positionedAt': positionedAt,
      'rotation': rotation,
      'scale': scale,
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
    double? positionX,
    double? positionY,
    bool? isPositioned,
    String? positionedBy,
    String? positionedAt,
    double? rotation,
    double? scale,
    double? targetX,
    double? targetY,
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
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      isPositioned: isPositioned ?? this.isPositioned,
      positionedBy: positionedBy ?? this.positionedBy,
      positionedAt: positionedAt ?? this.positionedAt,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      targetX: targetX ?? this.targetX,
      targetY: targetY ?? this.targetY,
    );
  }

  @override
  String toString() {
    return 'Message(messageId: $messageId, sender: $senderId, receiver: $receiverId, message: $message, seq: $sequenceId, read: $isRead)';
  }
}
