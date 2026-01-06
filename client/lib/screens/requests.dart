import 'package:client/services/api_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class PendingRequestsScreen extends StatefulWidget {
  const PendingRequestsScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _PendingRequestsScreenState createState() => _PendingRequestsScreenState();
}

class _PendingRequestsScreenState extends State<PendingRequestsScreen> {
  List<Map<String, dynamic>> _pendingRequests = [];
  late ApiService apiService;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    apiService = ApiService();

    fetchPendingRequests();
  }

  Future<void> fetchPendingRequests() async {
    try {
      final requests = await apiService.fetchPendingFriendRequests();
      setState(() {
        _pendingRequests = requests;
        _isLoading = false;
      });
    } catch (error) {
      if (kDebugMode) {
        print('Error fetching pending requests: $error');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> acceptFriendRequest(String friendId) async {
    // Save the request in case we need to rollback
    final requestToRemove = _pendingRequests.firstWhere((request) => request['id'] == friendId);
    final int originalIndex = _pendingRequests.indexOf(requestToRemove);

    // Optimistic UI update - remove immediately
    setState(() {
      _pendingRequests.removeWhere((request) => request['id'] == friendId);
    });

    try {
      await apiService.acceptFriendRequest(friendId);
      // Success - UI already updated
    } catch (error) {
      if (kDebugMode) {
        print('Error accepting friend request: $error');
      }

      // Rollback on error - restore the request
      setState(() {
        _pendingRequests.insert(originalIndex, requestToRemove);
      });

      // Show error to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept friend request. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? Center(child: CupertinoActivityIndicator(color: Colors.white,))
        : _pendingRequests.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Text(
                      ""
                    ),
                  ],
                ),
              )
            : ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: _pendingRequests.length,
              itemBuilder: (context, index) {
                  var user = _pendingRequests[index];
                  String profilePicture = 'assets/noprofile.png';

                  return Dismissible(
                    key: Key(user['id'].toString()), // Unique key for each item
                    direction: DismissDirection.endToStart, // Only swipe left
                    onDismissed: (direction) {
                      // This will be triggered when the item is swiped away
                      // You can add your delete logic here
                      // deleteRequest(user['id']);
                    },
                    background: Container(
                      color: Colors.red, // Red background for the trash can option
                      alignment: Alignment.centerRight,
                      padding: EdgeInsets.only(right: 20),
                      child: Icon(
                        Icons.delete, // Trash can icon
                        color: Colors.white,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(0),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundImage: AssetImage(profilePicture),
                        ),
                        title: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${user['username']}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  '${user['first_name']} ${user['last_name']}',
                                  style: TextStyle(
                                    color: Color(0xFF76767B),
                                    fontWeight: FontWeight.w500,
                                    fontSize: 15,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                SizedBox(
                                  height: 30,
                                  child: ElevatedButton(
                                    onPressed: () => acceptFriendRequest(user['id']),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white10,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(100),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: Text(
                                      "Accept",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
  }
}
