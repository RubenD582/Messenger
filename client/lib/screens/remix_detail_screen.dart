// remix_detail_screen.dart - BeReal-style remix detail view
import 'dart:io';
import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:client/models/remix.dart';
import 'package:client/models/remix_editor_result.dart';
import 'package:client/screens/remix_editor_screen.dart';
import 'package:client/services/remix_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
  List<GroupMember> _members = [];
  String? _currentUserId;
  bool _isLoadingRemix = false;
  bool _isLoadingPost = false;

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
      _members = await _remixService.getGroupMembers(widget.group.id);
      _todayPost = await _remixService.getTodayPost(widget.group.id);
      _history = await _remixService.getPostHistory(groupId: widget.group.id);

      setState(() {});
    } catch (e) {
      if (kDebugMode) {
        print('Error loading group data: $e');
      }
    }
  }

  bool _canRemix() {
    return _todayPost != null && !_todayPost!.hasExpired;
  }

  Future<void> _createPost() async {
    final ImageSource? source = await showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text(
          'Choose Photo Source',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.camera),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.camera_fill),
                SizedBox(width: 12),
                Text('Camera'),
              ],
            ),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context, ImageSource.gallery),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.photo_fill),
                SizedBox(width: 12),
                Text('Photo Library'),
              ],
            ),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          isDestructiveAction: true,
          child: const Text('Cancel'),
        ),
      ),
    );

    if (source == null) return;

    final XFile? photo = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (photo == null) return;

    setState(() => _isLoadingPost = true);

    try {
      final post = await _remixService.createPost(
        groupId: widget.group.id,
        imageFile: File(photo.path),
      );

      if (mounted) {
        setState(() {
          _todayPost = post;
          _isLoadingPost = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPost = false);
        _showError('Failed to create post: $e');
      }
    }
  }

  Future<void> _beginRemix() async {
    if (_todayPost == null) return;

    setState(() => _isLoadingRemix = true);
    File? tempFile;

    try {
      final response = await http.get(Uri.parse(_todayPost!.imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download base image.');
      }
      final baseImageBytes = response.bodyBytes;

      if (!mounted) return;

      final RemixEditorResult? result = await Navigator.push<RemixEditorResult>(
        context,
        CupertinoPageRoute(
          builder: (context) => RemixEditorScreen(
            baseImageBytes: baseImageBytes,
            postId: _todayPost!.id,
          ),
        ),
      );

      if (result != null) {
        final directory = await getTemporaryDirectory();
        tempFile = File('${directory.path}/overlay_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(result.overlayImageBytes);

        await _remixService.addPhotoLayer(
          postId: _todayPost!.id,
          imageFile: tempFile,
          positionX: result.normalizedCenterX,
          positionY: result.normalizedCenterY,
          scale: result.scale,
          rotation: result.rotation,
        );

        if (mounted) {
          await _loadGroupData();
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to remix: $e');
      }
    } finally {
      if (tempFile != null && await tempFile.exists()) {
        await tempFile.delete();
      }
      if (mounted) {
        setState(() => _isLoadingRemix = false);
      }
    }
  }

  void _showError(String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
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
      return '$hours hr ${minutes} min left';
    } else {
      return '$minutes min left';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.back,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        title: (_todayPost != null)
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  _todayPost!.posterName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
      ),
      body: Stack(
        children: [
          // Main content
          CustomScrollView(
            slivers: [
              // Image section
              SliverToBoxAdapter(
                child: _buildImageSection(),
              ),

              // Info and actions
              SliverToBoxAdapter(
                child: _buildInfoSection(),
              ),

              // History section
              if (_history.isNotEmpty)
                SliverToBoxAdapter(
                  child: _buildHistorySection(),
                ),

              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.bottom + 50), // Reduced height
              ),
            ],
          ),

          // Floating action button
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildFloatingButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    final hasPost = _todayPost != null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7, // Reduced height
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
      ),
      child: hasPost
          ? Stack(
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: _todayPost!.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.white.withValues(alpha: 0.05),
                    child: const Center(
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 20,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Icon(
                    Icons.error,
                    color: Colors.white,
                    size: 48,
                  ),
                ),

                // Gradient overlay at bottom
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: 350, // Slightly increased height for smoother transition
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(1), // Less harsh black
                        ],
                      ),
                    ),
                  ),
                ),




              ],
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.camera,
                      size: 50,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'No post today',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Be the first to post!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoSection() {
    return Padding(
      padding: const EdgeInsets.all(20), // Reduced padding
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group name and timer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.group.name ?? 'Remix Group',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              if (_todayPost != null && _todayPost!.expiresAt != null && !_todayPost!.hasExpired)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8), // Adjusted padding
                  child: Text(
                    _getTimeRemaining(_todayPost!.expiresAt!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),

          // Members
          Text(
            'MEMBERS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _members.map((member) {
              final isCurrentUser = member.id == _currentUserId;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          member.firstName.isNotEmpty
                              ? member.firstName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isCurrentUser ? 'You' : member.firstName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 0, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Text(
              'HISTORY',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _history.length,
              padding: const EdgeInsets.only(right: 20),
              itemBuilder: (context, index) {
                final post = _history[index];
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: post.thumbnailUrl,
                        fit: BoxFit.cover,
                      ),
                      // Date overlay
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                          child: Text(
                            _formatDate(post.postDate),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingButton() {
    final hasPost = _todayPost != null;
    final canRemix = _canRemix();

    if (_isLoadingPost || _isLoadingRemix) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.9),
            ],
          ),
        ),
        child: SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 3,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.9),
          ],
        ),
      ),
      child: SafeArea(
        child: GestureDetector(
          onTap: hasPost
              ? (canRemix ? _beginRemix : null)
              : _createPost,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: (hasPost && !canRemix)
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              hasPost
                  ? (canRemix ? 'Add Your Remix' : 'Expired')
                  : 'Post Base Photo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: (hasPost && !canRemix)
                    ? Colors.white.withValues(alpha: 0.4)
                    : Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';

    return '${date.month}/${date.day}';
  }
}
