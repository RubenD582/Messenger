// remix_screen.dart - Grid overview of all remix groups (Instagram-style)
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/models/remix.dart';
import 'package:client/services/remix_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/screens/create_remix_group_screen.dart';
import 'package:client/screens/remix_detail_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class RemixScreen extends StatefulWidget {
  const RemixScreen({super.key});

  @override
  State<RemixScreen> createState() => _RemixScreenState();
}

class _RemixScreenState extends State<RemixScreen> {
  final RemixService _remixService = RemixService();

  List<RemixGroup> _groups = [];
  Map<String, RemixPost?> _latestPosts = {};
  Map<String, List<GroupMember>> _groupMembers = {};
  Map<String, List<RemixLayer>> _groupLayers = {};
  Map<String, bool> _isMyTurnMap = {}; // Track which groups it's my turn
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      _currentUserId = await AuthService.getUserUuid();

      // Load all groups
      _groups = await _remixService.getGroups();

      // Load latest post, members, and layers for each group
      for (var group in _groups) {
        try {
          final postData = await _remixService.getTodayPost(group.id);
          final post = postData['post'] as RemixPost?;
          final isMyTurn = postData['isMyTurn'] as bool? ?? false;

          _latestPosts[group.id] = post;
          _isMyTurnMap[group.id] = isMyTurn;
          _groupMembers[group.id] = await _remixService.getGroupMembers(group.id);

          // Load layers if post exists
          if (post != null) {
            _groupLayers[group.id] = await _remixService.getLayers(post.id);
          } else {
            _groupLayers[group.id] = [];
          }
        } catch (e) {
          if (kDebugMode) {
            print('Error loading data for group ${group.id}: $e');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading remix groups: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showCreateGroupModal() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateRemixGroupScreen(),
    );

    if (result == true) {
      _loadData();
    }
  }

  void _openRemixDetail(RemixGroup group) {
    final post = _latestPosts[group.id];
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => RemixDetailScreen(
          group: group,
          initialPost: post,
        ),
      ),
    ).then((_) {
      // Refresh when coming back
      _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(
              child: CupertinoActivityIndicator(color: Colors.white),
            )
          : _groups.isEmpty
              ? _buildEmptyState()
              : GridView.builder(
                  padding: const EdgeInsets.only(left: 8, right: 8, top: 16, bottom: 90),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: _groups.length,
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final post = _latestPosts[group.id];
                    final members = _groupMembers[group.id] ?? [];
                    final layers = _groupLayers[group.id] ?? [];

                    return _buildGroupCard(group, post, members, layers);
                  },
                ),
      floatingActionButton: _groups.isNotEmpty && !_isLoading
          ? SizedBox(
              width: 48,
              height: 48,
              child: FloatingActionButton(
                onPressed: _showCreateGroupModal,
                backgroundColor: Colors.white,
                shape: const CircleBorder(),
                child: const Icon(
                  CupertinoIcons.add,
                  color: Colors.black,
                  size: 24,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildGroupCard(RemixGroup group, RemixPost? post, List<GroupMember> members, List<RemixLayer> layers) {
    final hasPost = post != null;

    // Calculate time ago
    String timeAgo = '';
    if (hasPost) {
      final now = DateTime.now();
      final postTime = post.createdAt;
      final difference = now.difference(postTime);

      if (difference.inDays > 0) {
        timeAgo = '${difference.inDays}d ago';
      } else if (difference.inHours > 0) {
        timeAgo = '${difference.inHours}h ago';
      } else if (difference.inMinutes > 0) {
        timeAgo = '${difference.inMinutes}m ago';
      } else {
        timeAgo = 'Just now';
      }
    }

    return GestureDetector(
      onTap: () => _openRemixDetail(group),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Main image or empty state
            hasPost
                ? Hero(
                    tag: 'remix_image_${group.id}',
                    flightShuttleBuilder: (flightContext, animation, flightDirection, fromHeroContext, toHeroContext) {
                      return Material(
                        type: MaterialType.transparency,
                        child: toHeroContext.widget,
                      );
                    },
                    child: Material(
                      type: MaterialType.transparency,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: post.imageUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholderFadeInDuration: Duration.zero,
                            placeholder: (context, url) => Container(
                              color: Colors.grey[850],
                              child: const Center(
                                child: CupertinoActivityIndicator(color: Colors.white),
                              ),
                            ),
                            errorWidget: (context, url, error) => const Icon(
                              Icons.error,
                              color: Colors.white54,
                            ),
                          ),
                          // Render layers
                          ...layers.map((layer) => _buildLayerPreview(layer)),
                        ],
                      ),
                    ),
                  )
                : Hero(
                    tag: 'remix_image_${group.id}',
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.camera,
                            size: 48,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No post yet',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

            // Gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Group info at bottom
            Positioned(
              bottom: 8,
              left: 8,
              right: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Left side: Group name and info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Group name
                        Text(
                          group.name ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Time display
                        if (hasPost)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              timeAgo,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Right side: Single profile picture
                  if (members.isNotEmpty)
                    CircleAvatar(
                      radius: 14,
                      backgroundImage: const AssetImage('assets/noprofile.png'),
                      backgroundColor: Colors.grey[700],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerPreview(RemixLayer layer) {
    if (layer.layerType != 'photo') return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Positioned(
          left: layer.positionX * width - (100 * layer.scale / 2),
          top: layer.positionY * height - (100 * layer.scale / 2),
          child: Transform.rotate(
            angle: layer.rotation * (3.14159 / 180),
            child: Transform.scale(
              scale: layer.scale,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(127),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: CachedNetworkImage(
                  imageUrl: layer.contentUrl!,
                  fit: BoxFit.cover,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_camera, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            'No Remix Groups Yet',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Create a group with your friends to start remixing!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showCreateGroupModal,
            icon: const Icon(Icons.add),
            label: const Text('Create Group'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
