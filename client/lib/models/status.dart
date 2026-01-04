// Status model for status/story feature
class Status {
  final String id;
  final String userId;
  final String userName;
  final String? username;
  final String textContent;
  final String backgroundColor;
  final DateTime createdAt;

  Status({
    required this.id,
    required this.userId,
    required this.userName,
    this.username,
    required this.textContent,
    required this.backgroundColor,
    required this.createdAt,
  });

  // Factory constructor to create Status from JSON (API response)
  factory Status.fromJson(Map<String, dynamic> json) {
    return Status(
      id: json['id'] ?? '',
      userId: json['userId'] ?? json['user_id'] ?? '',
      userName: json['userName'] ?? json['user_name'] ?? '',
      username: json['username'],
      textContent: json['textContent'] ?? json['text_content'] ?? '',
      backgroundColor: json['backgroundColor'] ?? json['background_color'] ?? '#5856D6',
      createdAt: _parseDateTime(json['createdAt'] ?? json['created_at']),
    );
  }

  // Helper to parse DateTime (handles both String and DateTime)
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value;
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (e) {
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  // Convert Status to JSON (for sending to API)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'username': username,
      'textContent': textContent,
      'backgroundColor': backgroundColor,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  // Helper: Check if status is expired (older than 24 hours)
  bool get isExpired {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    return difference.inHours >= 24;
  }

  // Helper: Time remaining until expiration
  Duration get timeRemaining {
    const twentyFourHours = Duration(hours: 24);
    final elapsed = DateTime.now().difference(createdAt);
    final remaining = twentyFourHours - elapsed;

    // Return zero duration if expired
    if (remaining.isNegative) {
      return Duration.zero;
    }

    return remaining;
  }

  // Helper: Get time remaining as a readable string
  String get timeRemainingString {
    final remaining = timeRemaining;

    if (remaining == Duration.zero) {
      return 'Expired';
    }

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  // Copy with method for updating status properties
  Status copyWith({
    String? id,
    String? userId,
    String? userName,
    String? username,
    String? textContent,
    String? backgroundColor,
    DateTime? createdAt,
  }) {
    return Status(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      username: username ?? this.username,
      textContent: textContent ?? this.textContent,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Status(id: $id, userId: $userId, userName: $userName, text: $textContent, bg: $backgroundColor, created: $createdAt)';
  }
}
