import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// A stateless widget responsible for rendering the UI for the notifications list.
// The state management is handled by the parent widget (_HomeState).
class NotificationsScreen extends StatelessWidget {
  final bool isLoadingRequests;
  final List<Map<String, dynamic>> pendingRequests;
  final Function(String) acceptFriendRequest;
  final Function(String) rejectFriendRequest;
  final String Function(String) formatRelativeTime;

  const NotificationsScreen({
    super.key,
    required this.isLoadingRequests,
    required this.pendingRequests,
    required this.acceptFriendRequest,
    required this.rejectFriendRequest,
    required this.formatRelativeTime,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoadingRequests) {
      return const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator(color: Colors.white)),
      );
    }

    if (pendingRequests.isEmpty) {
      return const SliverFillRemaining(
        child: Center(
          child: Text(
            "No pending requests.",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final user = pendingRequests[index];
          final profilePicture = 'assets/noprofile.png';
          // Assuming the timestamp is in a field named 'created_at'.
          final timestamp = user['created_at'] != null
              ? formatRelativeTime(user['created_at'])
              : '';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 22,
                backgroundImage: AssetImage(profilePicture),
              ),
              title: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  children: [
                    TextSpan(
                      text: user['username'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const TextSpan(text: ' has sent you a request '),
                    TextSpan(
                      text: '• $timestamp',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: () => acceptFriendRequest(user['id']),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        elevation: 0,
                      ),
                      child: const Text(
                        "Accept",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),

                  IconButton(
                    onPressed: () => rejectFriendRequest(user['id']),
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: pendingRequests.length,
      ),
    );
  }
}
