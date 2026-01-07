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

  @override
  void initState() {
    super.initState();
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
    _notificationStreamSubscription.cancel();
    super.dispose();
  }

  Future<void> _fetchNotifications() async {
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
    if (_isLoading) {
      return const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator(color: Colors.white)),
      );
    }

    if (_errorMessage != null) {
      return SliverFillRemaining(
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
      );
    }

    if (_notifications.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF262626),
                    width: 2,
                  ),
                ),
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
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final notification = _notifications[index];
          return _buildNotificationTile(notification);
        },
        childCount: _notifications.length,
      ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(height: 12),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF262626),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          'Accepted',
          style: TextStyle(
            color: Color(0xFF8E8E93),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
}
