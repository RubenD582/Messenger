// remix.dart - Models for daily remix feature

class RemixGroup {
  final String id;
  final String? name;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isActive;
  final int? memberCount;
  final DateTime? lastPostDate;

  RemixGroup({
    required this.id,
    this.name,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.isActive = true,
    this.memberCount,
    this.lastPostDate,
  });

  factory RemixGroup.fromJson(Map<String, dynamic> json) {
    return RemixGroup(
      id: json['id'],
      name: json['name'],
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      isActive: json['is_active'] ?? true,
      memberCount: json['member_count'] != null
          ? int.tryParse(json['member_count'].toString())
          : null,
      lastPostDate: json['last_post_date'] != null
          ? DateTime.parse(json['last_post_date'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'is_active': isActive,
    };
  }
}

class RemixPost {
  final String id;
  final String groupId;
  final String postedBy;
  final DateTime postDate;
  final String imageUrl;
  final String thumbnailUrl;
  final int? imageWidth;
  final int? imageHeight;
  final String? theme;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final bool isComplete;
  final String? firstName;
  final String? lastName;
  final int? layerCount;

  RemixPost({
    required this.id,
    required this.groupId,
    required this.postedBy,
    required this.postDate,
    required this.imageUrl,
    required this.thumbnailUrl,
    this.imageWidth,
    this.imageHeight,
    this.theme,
    required this.createdAt,
    this.expiresAt,
    this.isComplete = false,
    this.firstName,
    this.lastName,
    this.layerCount,
  });

  factory RemixPost.fromJson(Map<String, dynamic> json) {
    return RemixPost(
      id: json['id'],
      groupId: json['group_id'],
      postedBy: json['posted_by'],
      postDate: DateTime.parse(json['post_date']),
      imageUrl: json['image_url'],
      thumbnailUrl: json['thumbnail_url'],
      imageWidth: json['image_width'] != null
          ? int.tryParse(json['image_width'].toString())
          : null,
      imageHeight: json['image_height'] != null
          ? int.tryParse(json['image_height'].toString())
          : null,
      theme: json['theme'],
      createdAt: DateTime.parse(json['created_at']),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      isComplete: json['is_complete'] ?? false,
      firstName: json['first_name'],
      lastName: json['last_name'],
      layerCount: json['layer_count'] != null
          ? int.tryParse(json['layer_count'].toString())
          : null,
    );
  }

  String get posterName => '${firstName ?? ''} ${lastName ?? ''}'.trim();

  bool get hasExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);
}

class RemixLayer {
  final String id;
  final String postId;
  final String addedBy;
  final String layerType; // 'photo', 'sticker', 'text', 'drawing'
  final String? contentUrl;
  final String? textContent;
  final Map<String, dynamic>? stickerData;
  final Map<String, dynamic>? drawingData;
  final double positionX; // 0.0 to 1.0
  final double positionY; // 0.0 to 1.0
  final double scale; // 0.1 to 10.0
  final double rotation; // -180 to 180
  final int zIndex;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;
  final String? firstName;
  final String? lastName;
  final String? username;

  RemixLayer({
    required this.id,
    required this.postId,
    required this.addedBy,
    required this.layerType,
    this.contentUrl,
    this.textContent,
    this.stickerData,
    this.drawingData,
    this.positionX = 0.5,
    this.positionY = 0.5,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.zIndex = 0,
    this.metadata,
    required this.createdAt,
    this.firstName,
    this.lastName,
    this.username,
  });

  factory RemixLayer.fromJson(Map<String, dynamic> json) {
    return RemixLayer(
      id: json['id'],
      postId: json['post_id'],
      addedBy: json['added_by'],
      layerType: json['layer_type'],
      contentUrl: json['content_url'],
      textContent: json['text_content'],
      stickerData: json['sticker_data'] != null
          ? Map<String, dynamic>.from(json['sticker_data'])
          : null,
      drawingData: json['drawing_data'] != null
          ? Map<String, dynamic>.from(json['drawing_data'])
          : null,
      positionX: double.parse(json['position_x'].toString()),
      positionY: double.parse(json['position_y'].toString()),
      scale: double.parse(json['scale'].toString()),
      rotation: double.parse(json['rotation'].toString()),
      zIndex: json['z_index'] != null
          ? int.tryParse(json['z_index'].toString()) ?? 0
          : 0,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
      createdAt: DateTime.parse(json['created_at']),
      firstName: json['first_name'],
      lastName: json['last_name'],
      username: json['username'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'post_id': postId,
      'added_by': addedBy,
      'layer_type': layerType,
      'content_url': contentUrl,
      'text_content': textContent,
      'sticker_data': stickerData,
      'drawing_data': drawingData,
      'position_x': positionX,
      'position_y': positionY,
      'scale': scale,
      'rotation': rotation,
      'z_index': zIndex,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get addedByName => '${firstName ?? ''} ${lastName ?? ''}'.trim();
}

class GroupMember {
  final String id;
  final String firstName;
  final String lastName;
  final String username;
  final int streakCount;
  final DateTime joinedAt;

  GroupMember({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.username,
    this.streakCount = 0,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      id: json['id'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      username: json['username'],
      streakCount: json['streak_count'] != null
          ? int.tryParse(json['streak_count'].toString()) ?? 0
          : 0,
      joinedAt: DateTime.parse(json['joined_at']),
    );
  }

  String get fullName => '$firstName $lastName'.trim();
}
