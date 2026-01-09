// remix_detail_screen.dart - Detailed view for a specific remix group
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/models/remix.dart';
import 'package:client/services/remix_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class RemixDetailScreen extends StatefulWidget {
  final RemixGroup group;
  final RemixPost? initialPost;

  const RemixDetailScreen({
    super.key,
    required this.group,
    this.initialPost,
  });

  @override
  State<RemixDetailScreen> createState() => _RemixDetailScreenState();
}

class _RemixDetailScreenState extends State<RemixDetailScreen> {
  final RemixService _remixService = RemixService();
  final ImagePicker _picker = ImagePicker();

  RemixPost? _todayPost;
  List<RemixPost> _history = [];
  List<RemixLayer> _layers = [];
  List<GroupMember> _members = [];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _todayPost = widget.initialPost;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      _currentUserId = await AuthService.getUserUuid();
      await _loadGroupData();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading remix data: $e');
      }
    }
  }

  Future<void> _loadGroupData() async {
    try {
      // Load group members
      _members = await _remixService.getGroupMembers(widget.group.id);

      // Load today's post
      _todayPost = await _remixService.getTodayPost(widget.group.id);

      // Load layers if post exists
      if (_todayPost != null) {
        _layers = await _remixService.getLayers(_todayPost!.id);
      }

      // Load history
      _history = await _remixService.getPostHistory(groupId: widget.group.id);

      setState(() {});
    } catch (e) {
      if (kDebugMode) {
        print('Error loading group data: $e');
      }
    }
  }

  String _getWhoseTurn() {
    if (_todayPost == null) {
      return 'Anyone can start!';
    }

    final contributors = <String>{_todayPost!.postedBy};
    for (var layer in _layers) {
      contributors.add(layer.addedBy);
    }

    if (contributors.length >= _members.length) {
      return 'All done! Check out the final remix 🎉';
    }

    final membersWhoHaventContributed = _members
        .where((m) => !contributors.contains(m.id))
        .toList();

    if (membersWhoHaventContributed.isEmpty) {
      return 'All done!';
    }

    if (!contributors.contains(_currentUserId) &&
        membersWhoHaventContributed.any((m) => m.id == _currentUserId)) {
      return 'Your turn!';
    }

    final nextPerson = membersWhoHaventContributed.first;
    return '${nextPerson.firstName}\'s turn';
  }

  bool _isMyTurn() {
    if (_todayPost == null) return true;

    final contributors = <String>{_todayPost!.postedBy};
    for (var layer in _layers) {
      contributors.add(layer.addedBy);
    }

    return !contributors.contains(_currentUserId);
  }

  Future<void> _createPost() async {
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(CupertinoIcons.camera_fill, color: Colors.white),
                title: const Text('Camera', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.photo, color: Colors.white),
                title: const Text('Gallery', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final XFile? photo = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (photo == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );

      final post = await _remixService.createPost(
        groupId: widget.group.id,
        imageFile: File(photo.path),
      );

      if (mounted) {
        Navigator.pop(context);

        setState(() {
          _todayPost = post;
          _layers = [];
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 Post created! Friends can now add their layers'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create post: $e')),
        );
      }
    }
  }

  Future<void> _addLayer() async {
    if (_todayPost == null) return;

    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[700],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(CupertinoIcons.camera_fill, color: Colors.white),
                title: const Text('Camera', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.photo, color: Colors.white),
                title: const Text('Gallery', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final XFile? photo = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (photo == null) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );

      final layer = await _remixService.addPhotoLayer(
        postId: _todayPost!.id,
        imageFile: File(photo.path),
        positionX: 0.5,
        positionY: 0.5,
        scale: 0.5,
      );

      if (mounted) {
        Navigator.pop(context);

        setState(() {
          _layers.add(layer);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Layer added!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add layer: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.group.name ?? 'Remix Group',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTodaySection(),
            const SizedBox(height: 24),
            if (_history.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Past Remixes',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildHistoryGrid(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTodaySection() {
    final hasPost = _todayPost != null;
    final canPost = !hasPost;
    final canAddLayer = hasPost && !_todayPost!.hasExpired && _isMyTurn();
    final isMyTurn = _isMyTurn();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Today\'s Remix',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (hasPost && _todayPost!.expiresAt != null)
                Text(
                  'Expires in ${_getTimeRemaining(_todayPost!.expiresAt!)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (_members.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMyTurn
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isMyTurn
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.blue.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isMyTurn
                        ? CupertinoIcons.star_fill
                        : CupertinoIcons.person_fill,
                    color: isMyTurn ? Colors.green : Colors.blue,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getWhoseTurn(),
                    style: TextStyle(
                      color: isMyTurn ? Colors.green : Colors.blue,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          if (hasPost)
            _buildRemixCanvas()
          else
            _buildNoPostYet(),

          const SizedBox(height: 16),

          Row(
            children: [
              if (canPost && isMyTurn)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _createPost,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Post Base Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              if (canAddLayer) ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _addLayer,
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Add Your Layer'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
              if (!isMyTurn && hasPost) ...[
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Waiting for others...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (hasPost && _members.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${_layers.length + 1}/${_members.length} contributions',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: (_layers.length + 1) / _members.length,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRemixCanvas() {
    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.grey[900],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'remix_image_${widget.group.id}',
            child: Material(
              type: MaterialType.transparency,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: _todayPost!.imageUrl,
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    placeholderFadeInDuration: Duration.zero,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[850],
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                  ..._layers.map((layer) => _buildLayer(layer)),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'by ${_todayPost!.posterName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayer(RemixLayer layer) {
    if (layer.layerType != 'photo') return const SizedBox.shrink();

    return Positioned(
      left: layer.positionX * 400 - (100 * layer.scale / 2),
      top: layer.positionY * 400 - (100 * layer.scale / 2),
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
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoPostYet() {
    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.grey[900],
        border: Border.all(color: Colors.white24, width: 2),
      ),
      child: Hero(
        tag: 'remix_image_${widget.group.id}',
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_camera, size: 64, color: Colors.white.withAlpha(127)),
            const SizedBox(height: 16),
            Text(
              'No post yet today',
              style: TextStyle(
                color: Colors.white.withAlpha(204),
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Be the first to post!',
              style: TextStyle(color: Colors.white.withAlpha(153)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryGrid() {
    return Container(
      height: 120,
      margin: const EdgeInsets.only(left: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final post = _history[index];
          return Container(
            width: 100,
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: CachedNetworkImage(
              imageUrl: post.thumbnailUrl,
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }

  String _getTimeRemaining(DateTime expiresAt) {
    final now = DateTime.now();
    final difference = expiresAt.difference(now);

    if (difference.isNegative) return 'Expired';

    final hours = difference.inHours;
    final minutes = difference.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}
