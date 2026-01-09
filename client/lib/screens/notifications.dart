import 'dart:async'; // Import StreamSubscription
import 'package:client/services/api_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class NotificationsScreen extends StatefulWidget {
  final ApiService apiService;
  final Function(String) formatRelativeTime;

  const NotificationsScreen({
    super.key,
    required this.apiService,
    required this.formatRelativeTime,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];
  late StreamSubscription _notificationStreamSubscription;
  String? _errorMessage;
  final Set<String> _notificationIds = {}; // Track notification IDs to prevent duplicates
  String? selectedChip = "All"; // New state variable for selected chip
  List<Map<String, dynamic>> _groupedNotifications = []; // New list for notifications with dividers

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print('🔔 NotificationsScreen: initState called');
    }
    _fetchNotifications();

    // Subscribe to real-time notifications with error handling
    _notificationStreamSubscription = widget.apiService.newNotificationStream.listen(
      (newNotification) {
        if (kDebugMode) {
          print('🔔 NotificationsScreen: Received real-time notification: $newNotification');
        }
        if (mounted) {
          final notificationId = newNotification['id'] as String?;

          // Prevent duplicates
          if (notificationId != null && _notificationIds.contains(notificationId)) {
            if (kDebugMode) {
              print('🔔 NotificationsScreen: Skipping duplicate notification $notificationId');
            }
            return;
          }

          setState(() {
            // Prepend the new notification to the list
            _notifications.insert(0, newNotification);
            if (notificationId != null) {
              _notificationIds.add(notificationId);
            }
            // If the list was previously empty, ensure loading state is cleared
            if (_notifications.length == 1) {
              _isLoading = false;
            }
            _sortAndGroupNotifications(); // Sort and group after real-time update
          });
        }
      },
      onError: (error) {
        if (kDebugMode) {
          print('❌ NotificationsScreen: Stream error: $error');
        }
      },
      cancelOnError: false,
    );
  }

  @override
  void dispose() {
    if (kDebugMode) {
      print('🔔 NotificationsScreen: dispose called');
    }
    _notificationStreamSubscription.cancel();
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
    if (kDebugMode) {
      print('🔔 NotificationsScreen: _fetchNotifications called');
    }
    try {
      final notifications = await widget.apiService.fetchNotifications();
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _notificationIds.clear();
          // Track all notification IDs to prevent duplicates
          for (var notif in notifications) {
            final id = notif['id'] as String?;
            if (id != null) {
              _notificationIds.add(id);
            }
          }
          _isLoading = false;
          _errorMessage = null;
          if (kDebugMode) {
            print('🔔 NotificationsScreen: Fetched ${notifications.length} notifications.');
          }
          _sortAndGroupNotifications(); // Sort and group after fetching
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error fetching notifications: $e');
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load notifications';
        });
      }
    }
  }

  void _sortAndGroupNotifications() {
    // Sort notifications by timestamp (latest first)
    if (_notifications.isNotEmpty) {
      _notifications.sort((a, b) {
        final DateTime dateA = DateTime.parse(a['timestamp']);
        final DateTime dateB = DateTime.parse(b['timestamp']);
        return dateB.compareTo(dateA); // Sort descending (latest first)
      });
    }

    _groupedNotifications.clear();
    if (_notifications.isEmpty) return;

    final now = DateTime.now();
    // Normalize 'now' to start of day for accurate day comparisons
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sevenDaysAgo = today.subtract(const Duration(days: 7));
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));

    String lastDividerCategory = '';

    // Filter notifications first before grouping
    final List<Map<String, dynamic>> filteredNotifications = _filterNotifications();

    for (var notification in filteredNotifications) {
      final DateTime notificationDate = DateTime.parse(notification['timestamp']);
      // Normalize notificationDate to start of day for consistent comparisons
      final DateTime normalizedNotificationDate = DateTime(notificationDate.year, notificationDate.month, notificationDate.day);
      
      String currentDividerCategory = '';
      if (normalizedNotificationDate.isAtSameMomentAs(today)) {
        currentDividerCategory = 'Today';
      } else if (normalizedNotificationDate.isAtSameMomentAs(yesterday)) {
        currentDividerCategory = 'Yesterday';
      } else if (normalizedNotificationDate.isAfter(sevenDaysAgo)) {
        currentDividerCategory = 'Last 7 days';
      } else if (normalizedNotificationDate.isAfter(thirtyDaysAgo)) {
        currentDividerCategory = 'Last 30 days';
      } else {
        currentDividerCategory = 'Older';
      }

      // Add divider if category changes or it's the first notification
      if (currentDividerCategory != lastDividerCategory) {
        _groupedNotifications.add({
          'type': 'divider',
          'title': currentDividerCategory,
        });
        lastDividerCategory = currentDividerCategory;
      }

      _groupedNotifications.add(notification);
    }
  }

  Widget _buildTimeDivider(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14, // Appropriate size for a divider
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _acceptFriendRequest(String friendId, String notificationId) async {
    // Optimistically update the notification status
    _updateNotificationStatus(notificationId, 'accepted');

    try {
      await widget.apiService.acceptFriendRequest(friendId);
      // Update the status in the backend
      await widget.apiService.updateNotificationStatus(notificationId, 'accepted');
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error accepting friend request: $e');
      }
      // Rollback: restore the notification status
      if (mounted) {
        _updateNotificationStatus(notificationId, 'pending');
      }
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept friend request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectFriendRequest(String friendId, String notificationId) async {
    // Optimistically remove the notification
    final removedNotification = _removeNotification(notificationId);

    try {
      await widget.apiService.rejectFriendRequest(friendId);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error rejecting friend request: $e');
      }
      // Rollback: restore the notification if the API call failed
      if (removedNotification != null && mounted) {
        setState(() {
          _notifications.insert(0, removedNotification);
          final id = removedNotification['id'] as String?;
          if (id != null) {
            _notificationIds.add(id);
          }
        });
      }
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to reject friend request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _updateNotificationStatus(String notificationId, String status) {
    setState(() {
      final index = _notifications.indexWhere((n) => n['id'] == notificationId);
      if (index != -1) {
        _notifications[index]['status'] = status;
      }
    });
  }

  Map<String, dynamic>? _removeNotification(String notificationId) {
    Map<String, dynamic>? removedNotification;
    setState(() {
      final index = _notifications.indexWhere((n) => n['id'] == notificationId);
      if (index != -1) {
        removedNotification = _notifications.removeAt(index);
        _notificationIds.remove(notificationId);
      }
    });
    return removedNotification;
  }


    @override
    Widget build(BuildContext context) {
      // This method now returns a List<Widget> (slivers)
  
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    chip("All"),
                    const SizedBox(width: 6),
                    chip("Replies"),
                    const SizedBox(width: 6),
                    chip("Requests"),
                    const SizedBox(width: 6),
                    chip("Verified"),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator(color: Colors.white)),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _isLoading = true;
                          _errorMessage = null;
                        });
                        _fetchNotifications();
                      },
                      child: const Text("Retry"),
                    ),
                  ],
                ),
              ),
            )
          else if (_groupedNotifications.isEmpty) // Check grouped list emptiness
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      child: const Icon(
                        CupertinoIcons.bell,
                        size: 48,
                        color: Color(0xFF262626),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "No notifications yet",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "When someone sends you a friend request,\nyou'll see it here.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final item = _groupedNotifications[index];
                  if (item['type'] == 'divider') {
                    return _buildTimeDivider(item['title']);
                  } else {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 1.0), // Reduced spacing
                                        child: _buildNotificationTile(item),
                                      );                  }
                },
                childCount: _groupedNotifications.length,
              ),
            ),
        ],
      );
    }
  Widget _buildNotificationTile(Map<String, dynamic> notification) {
    final type = notification['type'];
    final actor = notification['actor'];
    final timestamp = notification['timestamp'] != null
        ? widget.formatRelativeTime(notification['timestamp'])
        : '';

    switch (type) {
      case 'FRIEND_REQUEST_RECEIVED':
        return _buildFriendRequestTile(notification, actor, timestamp);
      case 'FRIEND_REQUEST_ACCEPTED':
        return _buildRequestAcceptedTile(actor, timestamp);
      default:
        return const SizedBox.shrink(); // Hide unknown notification types
    }
  }

  Widget _buildFriendRequestTile(Map<String, dynamic> notification, Map<String, dynamic> actor, String timestamp) {
    final profilePicture = 'assets/noprofile.png';
    final username = actor['username'] ?? 'Someone';
    final actorId = actor['id'];
    final notificationId = notification['id'] as String;
    final status = notification['status'] ?? 'pending';
    final isDeveloper = actor['developer'] == true;
    final isVerified = actor['verified'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Vertically center profile picture
        children: [
          // Profile picture
          CircleAvatar(
            radius: 20,
            backgroundImage: AssetImage(profilePicture),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isDeveloper || isVerified)
                      _buildVerificationBadge(isDeveloper, isVerified),
                    Text(
                      'sent you a friend request',
                      style: const TextStyle(
                        color: Color(0xFFE0E0E0),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '•',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      timestamp,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6), // Reduced spacing
                _buildRequestActions(status, actorId, notificationId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestActions(String status, String actorId, String notificationId) {
    if (status == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7), // Match Confirm/Delete padding
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Added',
          style: TextStyle(
            color: const Color(0xFF8E8E93), // Change text color to light grey
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    } else {
      // Pending - show action buttons
      return Row(
        children: [
          // Accept button
          GestureDetector(
            onTap: () => _acceptFriendRequest(actorId, notificationId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Confirm',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Reject button
          GestureDetector(
            onTap: () => _rejectFriendRequest(actorId, notificationId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF262626),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Delete',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
    }
  }

  Widget _buildRequestAcceptedTile(Map<String, dynamic> actor, String timestamp) {
    final profilePicture = 'assets/noprofile.png';
    final username = actor['username'] ?? 'Someone';
    final isDeveloper = actor['developer'] == true;
    final isVerified = actor['verified'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center, // Vertically center profile picture
        children: [
          // Profile picture
          CircleAvatar(
            radius: 20,
            backgroundImage: AssetImage(profilePicture),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 2,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isDeveloper || isVerified)
                      _buildVerificationBadge(isDeveloper, isVerified),
                    Text(
                      'accepted your friend request',
                      style: const TextStyle(
                        color: Color(0xFFE0E0E0),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '•',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      timestamp,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge(bool isDeveloper, bool isVerified) {
    // Developer badge takes priority
    if (isDeveloper) {
      return SvgPicture.asset(
        'assets/developer.svg',
        width: 14,
        height: 14,
      );
    } else if (isVerified) {
      return SvgPicture.asset(
        'assets/verified.svg',
        width: 14,
        height: 14,
      );
    }
    return const SizedBox.shrink();
  }

  // New chip widget for filtering notifications
  Widget chip(String name) {
    bool isSelected = selectedChip == name;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0),
      child: IntrinsicWidth(
        child: GestureDetector(
          onTap: () {
            setState(() {
              selectedChip = name;
            });
          },
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
              borderRadius: const BorderRadius.all(Radius.circular(100)),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(left: 15, right: 15),
                child: Text(
                  name,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.black
                        : Colors.white.withAlpha(150),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // New method to filter notifications based on the selected chip
  List<Map<String, dynamic>> _filterNotifications() {
    if (selectedChip == "All") {
      return _notifications;
    } else if (selectedChip == "Replies") {
      // Assuming 'reply' type or similar in your notification data
      return _notifications.where((n) => n['type'] == 'REPLY').toList();
    } else if (selectedChip == "Follows") {
      return _notifications.where((n) => 
        n['type'] == 'FRIEND_REQUEST_RECEIVED' || 
        n['type'] == 'FRIEND_REQUEST_ACCEPTED'
      ).toList();
    } else if (selectedChip == "Verified") {
      return _notifications.where((n) => 
        (n['actor'] != null && n['actor']['verified'] == true) ||
        (n['targetUser'] != null && n['targetUser']['verified'] == true)
      ).toList();
    }
    return _notifications; // Fallback to all
  }
}