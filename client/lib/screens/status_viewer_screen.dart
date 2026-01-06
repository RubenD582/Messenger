import 'dart:ui';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:client/models/status.dart';
import 'package:client/widgets/dismissible_status_wrapper.dart';
import 'package:client/services/api_service.dart';
import 'package:client/services/status_view_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart'; // Import for GestureRecognizer

class StatusViewerScreen extends StatefulWidget {
  final List<Status> statuses;
  final String? currentUserId;
  final Function(String)? onStatusDeleted;
  final ApiService? apiService;
  final int initialIndex;

  const StatusViewerScreen({
    super.key,
    required this.statuses,
    this.currentUserId,
    this.onStatusDeleted,
    this.apiService,
    this.initialIndex = 0,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode(); // Add FocusNode

  late List<Status> _statuses; // Mutable local list
  StreamSubscription<Map<String, dynamic>>? _statusDeletedSubscription;
  Map<String, int> _viewerCounts = {}; // Map of statusId -> viewer count
  bool _isOwnStatus = false;

  static const Duration _shortLongPressDelay = Duration(milliseconds: 100); // Define a shorter delay

  @override
  void initState() {
    super.initState();

    // Initialize mutable list
    _statuses = List.from(widget.statuses);

    // Set initial index
    _currentIndex = widget.initialIndex;

    // Check if viewing own status
    if (_statuses.isNotEmpty && widget.currentUserId != null) {
      _isOwnStatus = _statuses.first.userId == widget.currentUserId;
    }

    if (kDebugMode) {
      print('🎬 StatusViewerScreen opened with ${_statuses.length} statuses:');
      print('   Is own status: $_isOwnStatus');
      print('   Initial index: $_currentIndex');
      for (var i = 0; i < _statuses.length; i++) {
        print('  [$i] ID: ${_statuses[i].id}, Text: ${_statuses[i].textContent.substring(0, _statuses[i].textContent.length > 20 ? 20 : _statuses[i].textContent.length)}...');
      }
    }

    // Record view for friend's status
    if (!_isOwnStatus && _statuses.isNotEmpty && widget.apiService != null) {
      _recordView(_statuses[_currentIndex].id);
    }

    // Load viewer counts for own status
    if (_isOwnStatus && widget.apiService != null) {
      _loadViewerCounts();
    }

    // Listen for status deletion events
    if (widget.apiService != null) {
      _statusDeletedSubscription = widget.apiService!.statusDeletedStream.listen((data) {
        final deletedStatusId = data['id'];
        if (kDebugMode) {
          print('📩 StatusViewerScreen: Received statusDeleted event for $deletedStatusId');
        }
        _handleStatusDeleted(deletedStatusId);
      });
    }

    _pageController = PageController(initialPage: widget.initialIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() {
        setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStatus();
        }
      });

    _startStatus();

    // Add listener to focus node
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _animationController.stop(); // Pause animation when text field is active
      } else {
        if (_animationController.status != AnimationStatus.completed) {
          _animationController.forward(); // Resume animation when text field loses focus
        }
      }
    });
  }

  void _startStatus() {
    _animationController.stop();
    _animationController.reset();
    _animationController.forward();
  }

  Future<void> _recordView(String statusId) async {
    try {
      await StatusViewService.markAsViewed(statusId);
      if (kDebugMode) {
        print('👁️  Recorded view for status $statusId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error recording view: $e');
      }
    }
  }

  Future<void> _loadViewerCounts() async {
    if (widget.apiService == null) return;
    try {
      for (var status in _statuses) {
        final viewers = await widget.apiService!.getStatusViewers(status.id);
        setState(() {
          _viewerCounts[status.id] = viewers.length;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading viewer counts: $e');
      }
    }
  }

  Future<void> _showViewers() async {
    if (widget.apiService == null || _statuses.isEmpty) return;

    final currentStatus = _statuses[_currentIndex];

    // Pause the timer when modal opens
    _animationController.stop();

    try {
      final viewers = await widget.apiService!.getStatusViewers(currentStatus.id);

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        backgroundColor: const Color(0xFF1C1C1E),
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                child: Row(
                  children: [
                    // const Icon(Icons.visibility, color: Colors.white, size: 24),
                    // const SizedBox(width: 12),
                    Text(
                      '${viewers.length} ${viewers.length == 1 ? 'Viewer' : 'Viewers'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(color: Color(0xFF2C2C2E)),
              // Viewers list
              if (viewers.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text(
                    'No views yet',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 16,
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: viewers.length,
                    itemBuilder: (context, index) {
                      final viewer = viewers[index];
                      final viewedAt = DateTime.parse(viewer['viewedAt']);
                      final timeAgo = _formatViewTime(viewedAt);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 18,
                              backgroundImage: AssetImage('assets/noprofile.png'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${viewer['firstName']} ${viewer['lastName']}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              timeAgo,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
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
        ),
      ),
    );

      // Resume the timer when modal is closed
      if (mounted && _animationController.status != AnimationStatus.completed) {
        _animationController.forward();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error showing viewers: $e');
      }
      // Resume timer even if there was an error
      if (mounted && _animationController.status != AnimationStatus.completed) {
        _animationController.forward();
      }
    }
  }

  String _formatViewTime(DateTime viewedAt) {
    final now = DateTime.now();
    final difference = now.difference(viewedAt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      final day = viewedAt.day;
      final month = _getMonthName(viewedAt.month);
      final hour = viewedAt.hour;
      final minute = viewedAt.minute.toString().padLeft(2, '0');
      return '$day $month $hour:$minute';
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[month - 1];
  }

  void _handleStatusDeleted(String deletedStatusId) {
    final index = _statuses.indexWhere((status) => status.id == deletedStatusId);

    if (index != -1) {
      if (kDebugMode) {
        print('🗑️  Status found in current list at index $index, removing...');
      }

      setState(() {
        _statuses.removeAt(index);
      });

      // If no statuses left, close the viewer
      if (_statuses.isEmpty) {
        if (kDebugMode) {
          print('📤 No statuses left, closing viewer');
        }
        Navigator.pop(context);
        return;
      }

      // Adjust current index if needed
      if (_currentIndex >= _statuses.length) {
        _currentIndex = _statuses.length - 1;
        _pageController.jumpToPage(_currentIndex);
      } else if (index <= _currentIndex) {
        // If we deleted current or previous, restart animation
        _startStatus();
      }
    }
  }

  void _nextStatus() {
    if (_currentIndex < _statuses.length - 1) {
      _pageController.jumpToPage(_currentIndex + 1);
      // onPageChanged will handle updating _currentIndex and calling _startStatus()
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStatus() {
    if (_currentIndex > 0) {
      _pageController.jumpToPage(_currentIndex - 1);
      // onPageChanged will handle updating _currentIndex and calling _startStatus()
    } else {
      Navigator.pop(context);
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final statusDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final timeString = '$hour:$minute';

    if (statusDate == today) {
      return 'Today at $timeString';
    } else {
      return 'Yesterday at $timeString';
    }
  }

  void _showDeleteMenu() {
    // Pause the timer when menu opens
    _animationController.stop();

    showCupertinoModalPopup(
      context: context,
      builder: (BuildContext context) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context); // Close menu
              _deleteCurrentStatus();
            },
            child: const Text('Delete Status'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(context);
            // Resume the timer when menu is cancelled
            if (_animationController.status != AnimationStatus.completed) {
              _animationController.forward();
            }
          },
          isDefaultAction: true,
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _deleteCurrentStatus() async {
    if (_statuses.isEmpty) return;

    final currentStatus = _statuses[_currentIndex];

    // Remove from local list immediately to prevent race condition with WebSocket
    setState(() {
      _statuses.removeAt(_currentIndex);
    });

    try {
      final apiService = ApiService();
      await apiService.deleteStatus(currentStatus.id);

      if (kDebugMode) {
        print('✅ Status deleted: ${currentStatus.id}');
      }

      // Notify parent if callback provided
      if (widget.onStatusDeleted != null) {
        widget.onStatusDeleted!(currentStatus.id);
      }

      // Close viewer immediately
      if (mounted) {
        Navigator.pop(context);
      }

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting status: $e');
      }

      // Re-add the status if delete failed
      setState(() {
        _statuses.insert(_currentIndex, currentStatus);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _statusDeletedSubscription?.cancel();
    _animationController.dispose();
    _pageController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {


    // If list is empty, show empty container (will be popped shortly)
    if (_statuses.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.shrink(),
      );
    }

    // Ensure current index is valid
    if (_currentIndex >= _statuses.length) {
      _currentIndex = _statuses.length - 1;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false, // Prevent keyboard from pushing content up
      body: DismissibleStatusWrapper(
        child: RawGestureDetector(
          gestures: {
            _CustomTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<_CustomTapGestureRecognizer>(
              () => _CustomTapGestureRecognizer(),
              (_CustomTapGestureRecognizer instance) {
                instance.onTapUp = (details) {
                  // If keyboard is active, dismiss it instead of navigating
                  if (_replyFocusNode.hasFocus) {
                    _replyFocusNode.unfocus();
                    return;
                  }

                  final screenWidth = MediaQuery.of(context).size.width;
                  if (details.globalPosition.dx < screenWidth / 3) {
                    _previousStatus();
                  } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
                    _nextStatus();
                  }
                };
              },
            ),
            _CustomLongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<_CustomLongPressGestureRecognizer>(
              () => _CustomLongPressGestureRecognizer(duration: _shortLongPressDelay),
              (_CustomLongPressGestureRecognizer instance) {
                instance.onLongPressStart = (_) {
                  _animationController.stop();
                };
                instance.onLongPressEnd = (_) {
                  if (_animationController.status != AnimationStatus.completed) {
                    _animationController.forward();
                  }
                };
              },
            ),
          },
          child: Stack(
            children: [
              // PageView for statuses
              PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe
                itemCount: _statuses.length,
                onPageChanged: (index) {
                  if (kDebugMode) {
                    print('📄 Page changed to index $index');
                  }
                  setState(() {
                    _currentIndex = index;
                  });
                  _startStatus(); // Restart timer for the new status

                  // Record view for friend's status
                  if (!_isOwnStatus && widget.apiService != null) {
                    _recordView(_statuses[index].id);
                  }
                },
                itemBuilder: (context, index) {
                                    final status = _statuses[index];
                  final colorHex = status.backgroundColor.replaceFirst('#', '');
                  final color = Color(int.parse('FF$colorHex', radix: 16));

                  return Container(
                    color: color,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Text(
                          status.textContent,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Top bar with progress indicators and close button
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Column(
                    children: [
                      // Progress bars
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                        child: Row(
                          children: List.generate(_statuses.length, (index) {

                            return Expanded(
                              child: Container(
                                height: 3,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: index < _currentIndex
                                        ? 1.0
                                        : index == _currentIndex
                                            ? _animationController.value
                                            : 0.0,
                                    backgroundColor: Colors.white.withOpacity(0.3),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),

                      const SizedBox(height: 10.0), // Added spacing

                      // User info and close button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            const CircleAvatar(
                              radius: 20,
                              backgroundImage: AssetImage('assets/noprofile.png'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _statuses[_currentIndex].userName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _formatTime(_statuses[_currentIndex].createdAt),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Show three-dot menu only for own statuses
                            if (widget.currentUserId != null &&
                                _statuses[_currentIndex].userId == widget.currentUserId) ...[
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  icon: const Icon(Icons.more_horiz, color: Colors.white),
                                  onPressed: _showDeleteMenu,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 18,
                                icon: const Icon(Icons.close, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Bottom area - Reply input for friends, Viewers button for own status
              if (_isOwnStatus)
                // Eye icon button to view who saw the status
                Positioned(
                  bottom: MediaQuery.of(context).padding.bottom + 16,
                  right: 16,
                  child: GestureDetector(
                    onTap: _showViewers,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.visibility, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '${_viewerCounts[_statuses[_currentIndex].id] ?? 0}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                // Reply input for friend's status
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    onVerticalDragEnd: (details) {
                      if (details.primaryVelocity! < -100) { // Swiping up
                        _replyFocusNode.requestFocus();
                      }
                    },
                    child: AbsorbPointer(
                      absorbing: _replyFocusNode.hasFocus,
                      child: Material(
                        color: Colors.transparent,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 8.0,
                            left: 8,
                            right: 8,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(25.0),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                              child: Container(
                                padding: const EdgeInsets.only(left: 12.0, right: 0.0),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(25.0),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: CupertinoTextField(
                                        controller: _replyController,
                                        focusNode: _replyFocusNode,
                                        placeholder: 'Reply...',
                                        placeholderStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                                        style: const TextStyle(color: Colors.white),
                                        decoration: const BoxDecoration(),
                                        padding: const EdgeInsets.symmetric(vertical: 13.0),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        // TODO: Implement send reply functionality
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 5),
                                        child: Container(
                                          width: 35,
                                          height: 35,
                                          decoration: BoxDecoration(
                                            color: Color(int.parse('FF${_statuses[_currentIndex].backgroundColor.replaceFirst('#', '')}', radix: 16)).withOpacity(0.8),
                                            borderRadius: BorderRadius.circular(20.0),
                                          ),
                                          child: Center(
                                            child: SvgPicture.asset(
                                              'assets/send.svg',
                                              width: 14,
                                              height: 14,
                                              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom gesture recognizers
class _CustomTapGestureRecognizer extends TapGestureRecognizer {
  _CustomTapGestureRecognizer({Object? debugOwner}) : super(debugOwner: debugOwner);
}

class _CustomLongPressGestureRecognizer extends LongPressGestureRecognizer {
  _CustomLongPressGestureRecognizer({super.duration, Object? debugOwner}) : super(debugOwner: debugOwner);
}