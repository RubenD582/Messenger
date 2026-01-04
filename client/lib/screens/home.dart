import 'dart:async';
import 'dart:ui';

import 'package:client/screens/requests.dart';
import 'package:client/screens/chat_screen.dart';
import 'package:client/screens/status_creation_screen.dart';
import 'package:client/screens/status_viewer_screen.dart';
import 'package:client/models/status.dart';
import 'package:client/transitions/circular_page_route.dart';
import 'discover.dart' as discover;
import 'package:client/services/api_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/location_service.dart';
import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:hive/hive.dart';
import 'package:fluttertoast/fluttertoast.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  double _scrollYOffset = 0.0;
  double _scrollYOpacity = 0.0;

  List<Map<String, dynamic>> _friends = [];
  late Box _friendsBox;

  String? selectedChip = "All";
  late ApiService apiService;
  bool isLoading = true;

  late StreamSubscription<int> _pendingFriendRequestsSubscription;
  int _pendingFriendRequestsCount = 0;

  // Status state
  List<Status> _myStatuses = [];
  List<Status> _friendStatuses = [];
  late StreamSubscription<Map<String, dynamic>> _statusCreatedSubscription;
  late StreamSubscription<Map<String, dynamic>> _statusDeletedSubscription;

  late String uuid;
  final LocationService _locationService = LocationService();

  @override
  void initState() {
    super.initState();

    setupAPIService().then((_) {
      fetchRequestCount();

      // Open the Hive box first
      _openFriendsBox().then((_) {
        fetchFriends();
      });

      // Load statuses
      _loadStatuses();

      // Setup status WebSocket listeners
      _setupStatusListeners();

      // Update location on app launch/login
      _updateLocationOnLaunch();

      _scrollController.addListener(() {
        setState(() {
          _scrollYOffset = -(_scrollController.offset / 5).clamp(-100.0, 0.0);
          _scrollYOpacity = (_scrollController.offset / 75).clamp(0, 1);
        });
      });

      _pendingFriendRequestsSubscription = apiService.pendingRequestsStream.listen((count) {
        setState(() {
          _pendingFriendRequestsCount = count;
        });
      });
    }).catchError((error) {
      _showErrorDialog(error.toString());  // Show error dialog
    });
  }

  Future<void> _updateLocationOnLaunch() async {
    try {
      // Check if location is enabled
      final isLocationEnabled = await _locationService.isLocationEnabled();

      if (isLocationEnabled) {
        // Get current location
        final locationData = await _locationService.getCurrentLocation();

        if (locationData != null) {
          // Update on backend
          final success = await _locationService.updateLocationOnBackend();

          if (success && mounted) {
            final country = locationData['country'] as String? ?? 'Unknown';
            final state = locationData['state'] as String? ?? 'Unknown';
            final city = locationData['city'] as String? ?? 'Unknown';

            // Show toast with location info
            Fluttertoast.showToast(
              msg: "📍 $city, $state, $country",
              toastLength: Toast.LENGTH_LONG,
              gravity: ToastGravity.TOP,
              timeInSecForIosWeb: 3,
              backgroundColor: const Color(0xFF0095F6),
              textColor: Colors.white,
              fontSize: 14.0,
            );

            if (kDebugMode) {
              print('Location updated on home screen launch: $city, $state, $country');
            }
          }
        }
      } else {
        if (kDebugMode) {
          print('Location not enabled, skipping auto-update');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating location on launch: $e');
      }
      // Don't show error to user, just fail silently
    }
  }

  void _showErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Server offline"),
          content: Text(errorMessage),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("OK"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openFriendsBox() async {
    _friendsBox = await Hive.openBox('friendsBox');
    _loadFriendsFromHive();
  }

  Future<void> _loadFriendsFromHive() async {
    if (uuid.isEmpty) {
      return;
    }

    List<Map<String, dynamic>> storedFriends = List<Map<String, dynamic>>.from(
      _friendsBox.get('${uuid}_friends', defaultValue: []).map((friend) => Map<String, dynamic>.from(friend))
    );

    setState(() {
      _friends = storedFriends;
    });
  }


  Future<void> _saveFriendsToHive() async {
    if (uuid.isEmpty) {
      if (kDebugMode) {
        print("UUID is null or empty, cannot save friends.");
      }
      return;
    }

    if (_friends.isNotEmpty) {
      await _friendsBox.put('${uuid}_friends', _friends);

      if (kDebugMode) {
        print("Saved friends to Hive: $_friends");
      }
    }
  }

  Future<void> setupAPIService() async {
    uuid = (await fetchUuid())!;
    
    apiService = ApiService();
    apiService.init(uuid);
  }

  Future<void> fetchRequestCount() async {
    try {
      final requests = await apiService.getRequestCount();
      setState(() {
        _pendingFriendRequestsCount = requests;
        isLoading = false;
      });
    } catch (error) {
      if (kDebugMode) {
        print('Error fetching pending requests: $error');
      }
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchFriends() async {
    try {
      final friends = await apiService.fetchFriends();

      setState(() {
        _friends = friends; // Replace instead of append
      });

      await _saveFriendsToHive();
    } catch (error) {
      if (kDebugMode) {
        print('Error fetching friends: $error');
      }
    }
  }

  Future<String?> fetchUuid() async {
    String? userUuid = await AuthService.getUserUuid();
    if (userUuid != null) {
      return userUuid;
    }

    return null;
  }

  Future<void> _loadStatuses() async {
    try {
      // Load user's own statuses (up to 20)
      final myStatusesData = await apiService.getMyStatuses();
      _myStatuses = myStatusesData.map((data) => Status.fromJson(data)).toList();

      // Load friend statuses
      final friendStatusesData = await apiService.getFriendStatuses();
      _friendStatuses = friendStatusesData.map((data) => Status.fromJson(data)).toList();

      setState(() {});
    } catch (error) {
      if (kDebugMode) {
        print('Error loading statuses: $error');
      }
    }
  }

  void _setupStatusListeners() {
    // Listen for new statuses
    _statusCreatedSubscription = apiService.statusCreatedStream.listen((data) {
      if (kDebugMode) {
        print('Status created event received: $data');
      }
      _loadStatuses(); // Refresh statuses
    });

    // Listen for deleted statuses
    _statusDeletedSubscription = apiService.statusDeletedStream.listen((data) {
      if (kDebugMode) {
        print('Status deleted event received: $data');
      }
      _loadStatuses(); // Refresh statuses
    });
  }

  void _openStatusCreationScreen(GlobalKey statusCircleKey) {
    // Get the position of the status circle
    final RenderBox? renderBox = statusCircleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final circleCenter = offset + Offset(renderBox.size.width / 2, renderBox.size.height / 2);

    Navigator.of(context).push(
      CircularRevealPageRoute(
        builder: (context) => StatusCreationScreen(apiService: apiService),
        originOffset: circleCenter,
        originRadius: 32.0, // Status circle radius
      ),
    );
  }

  void _showSearchModal() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => discover.SearchPage()),
    );
  }


  @override
  void dispose() {
    _pendingFriendRequestsSubscription.cancel();
    _statusCreatedSubscription.cancel();
    _statusDeletedSubscription.cancel();
    apiService.disconnectWebSocket();

    _scrollController.dispose();

    super.dispose();
  }

  Future<void> _refreshContent() async {
    await Future.delayed(Duration(seconds: 2)); 
    setState(() {

    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            floating: true,
            pinned: true,
            scrolledUnderElevation: 0.0,
            expandedHeight: 120,
            toolbarHeight: 70,
            automaticallyImplyLeading: false,
            flexibleSpace: Builder(
              builder: (context) {
                // Animate text size and alignment based on scroll offset
                double textSize = 32;
                // double textSize = 50 - (_scrollOffset * 0.2).clamp(18.0, 22.0);
                // double textAlignment = (_scrollOffset > 30) ? 0.0 : 1.0; // Move the text to the center when scrolling

                return ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(175),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Align(
                                  // alignment: Alignment(0.0, textAlignment),  // Center the text on scroll
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 0),
                                    child: Text(
                                      "Messages",
                                      textAlign: TextAlign.left,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: textSize,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    _iconButton(Icons.more_horiz, Colors.white.withAlpha(50), _showSearchModal),
                                    const SizedBox(width: 10),
                                    _iconButton(Icons.add, Color(0xFF5856D6), _showSearchModal),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
                
          // **Sticky Search Header**
          SliverStickyHeader(
            header: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: Colors.black,
              child: Transform.translate(
                offset: Offset(
                  0, 
                  _scrollYOffset
                ),
      
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: "Search",
                  placeholderStyle: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  backgroundColor: AppColors.surfaceVariant,
                  itemColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (value) {},
                  onSubmitted: (value) {},
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      CupertinoIcons.search,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                  ),
                  suffixIcon: Icon(null),
                ),
              ),
            ),
            sliver: SliverToBoxAdapter(
              child: Transform.translate(
                offset: Offset(
                0, 
                _scrollYOffset * 0.75
              ),
                child: Container(
                  padding: EdgeInsets.only(left: 10, right: 10, top: 8, bottom: 8),
                  child: AnimatedOpacity(
                    opacity: 1 - _scrollYOpacity,
                    duration: Duration(milliseconds: 200),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          chip("All"),
                          const SizedBox(width: 6),
                          chip("Pinned"),
                          const SizedBox(width: 6),
                          chip("Requests", _pendingFriendRequestsCount),
                          const SizedBox(width: 6),
                          Container(
                            height: 32,
                            width: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF1C1C1E),
                            ),
                            child: Icon(
                              Icons.add,
                              color: Colors.white.withAlpha(150),
                              size: 18,
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      
          // **Stories Bar (UI Mockup)**
          if (selectedChip == "All")
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: Offset(0, _scrollYOffset * 0.5),
                child: _buildStoriesBar(),
              ),
            ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 10),
          ),

          // **Friend List / Requests**
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: Offset(
                0,
                _scrollYOffset
              ),
              child: Container(
                child: selectedChip == "Requests"
                  ? PendingRequestsScreen()
                  : friendList(),
              ),
            )
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, Color bgColor, VoidCallback onTap) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }


  Widget friendList() {
    // Empty state
    if (_friends.isEmpty && !isLoading) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      backgroundColor: Colors.transparent,
      color: Colors.white,
      onRefresh: _refreshContent,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: _friends.length,
        itemBuilder: (context, index) {
          var user = _friends[index];
          String profilePicture = 'assets/noprofile.png';

          // Mock data for demo (replace with real data from backend)
          final bool isOnline = index % 3 == 0; // Mock: every 3rd user is online
          final bool isTyping = index == 0; // Mock: first user is typing
          final int unreadCount = index % 5 == 0 ? (index % 10) + 1 : 0; // Mock unread count
          final String lastMessage = isTyping
              ? ''
              : index % 4 == 0
                  ? 'Hey! How are you doing? 😊'
                  : index % 4 == 1
                      ? 'See you tomorrow!'
                      : index % 4 == 2
                          ? 'Thanks for the help!'
                          : 'Sounds good!';
          final String timestamp = index % 6 == 0
              ? 'Just now'
              : index % 6 == 1
                  ? '2m ago'
                  : index % 6 == 2
                      ? '1h ago'
                      : index % 6 == 3
                          ? 'Yesterday'
                          : index % 6 == 4
                              ? 'Tuesday'
                              : 'Monday';

          return Dismissible(
            key: Key(user['id'].toString()),
            direction: DismissDirection.horizontal,
            onDismissed: (direction) {
              if (direction == DismissDirection.endToStart) {
                // Delete action
              } else if (direction == DismissDirection.startToEnd) {
                // Pin action
              }
            },
            background: Container(
              color: Color(0xFF5856D6),
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(left: 20),
              child: Icon(Icons.push_pin, color: Colors.white, size: 24),
            ),
            secondaryBackground: Container(
              color: Color(0xFFFF3B30),
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
              child: Icon(Icons.delete, color: Colors.white, size: 24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: InkWell(
                  onTap: () {
                    final conversationId = _getConversationId(uuid, user['friend_id']);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          conversationId: conversationId,
                          friendId: user['friend_id'],
                          friendName: '${user['first_name']} ${user['last_name']}',
                          apiService: apiService,
                        ),
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      // Profile picture with online status
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: AssetImage(profilePicture),
                          ),
                          if (isOnline)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: Color(0xFF30D158),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.black, width: 2.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(width: 12),
                      // Message info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${user['first_name']} ${user['last_name']}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w600,
                                    fontSize: 16,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  timestamp,
                                  style: TextStyle(
                                    color: unreadCount > 0
                                        ? Color(0xFF5856D6)
                                        : Color(0xFF76767B),
                                    fontSize: 13,
                                    fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: isTyping
                                      ? Row(
                                          children: [
                                            Text(
                                              'Typing...',
                                              style: TextStyle(
                                                color: Color(0xFF30D158),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            SizedBox(width: 4),
                                          ],
                                        )
                                      : Text(
                                          lastMessage,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: unreadCount > 0
                                                ? Color(0xFFD1D1D6)
                                                : Color(0xFF76767B),
                                            fontSize: 14,
                                            fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.w400,
                                          ),
                                        ),
                                ),
                                if (unreadCount > 0) ...[
                                  SizedBox(width: 8),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Color(0xFF5856D6),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    constraints: BoxConstraints(minWidth: 20),
                                    child: Text(
                                      unreadCount > 9 ? '9+' : unreadCount.toString(),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.chat_bubble_2,
            size: 80,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tap + to start chatting with friends',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }


  // Helper function to generate conversation ID (same logic as backend)
  String _getConversationId(String userId1, String userId2) {
    final sorted = [userId1, userId2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }

  // Stories Bar (UI Mockup - no functionality)
  Widget _buildStoriesBar() {
    // Build list with "Your Story" first, then friend statuses
    final hasMyStatus = _myStatuses.isNotEmpty && !_myStatuses.last.isExpired;

    // Group friend statuses by userId to avoid duplicates
    final Map<String, List<Status>> groupedStatuses = {};
    for (var status in _friendStatuses) {
      if (!groupedStatuses.containsKey(status.userId)) {
        groupedStatuses[status.userId] = [];
      }
      groupedStatuses[status.userId]!.add(status);
    }

    final uniqueFriendStatuses = groupedStatuses.values.toList();

    return Container(
      height: 80,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: 1 + uniqueFriendStatuses.length, // "Your Story" + unique friends
        itemBuilder: (context, index) {
          final isYou = index == 0;

          if (isYou) {
            // "Your Story" circle
            final yourStoryKey = GlobalKey();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () {
                  if (hasMyStatus) {
                    // Show action sheet to view or create
                    showCupertinoModalPopup(
                      context: context,
                      builder: (BuildContext context) => CupertinoActionSheet(
                        actions: [
                          CupertinoActionSheetAction(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => StatusViewerScreen(statuses: _myStatuses),
                                ),
                              );
                            },
                            child: const Text('View Status'),
                          ),
                          CupertinoActionSheetAction(
                            onPressed: () {
                              Navigator.pop(context);
                              _openStatusCreationScreen(yourStoryKey);
                            },
                            child: const Text('Create New Status'),
                          ),
                        ],
                        cancelButton: CupertinoActionSheetAction(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          isDefaultAction: true,
                          child: const Text('Cancel'),
                        ),
                      ),
                    );
                  } else {
                    // No statuses, directly create
                    _openStatusCreationScreen(yourStoryKey);
                  }
                },
                child: Column(
                  key: yourStoryKey,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: hasMyStatus
                                ? const LinearGradient(
                                    colors: [Color(0xFF8B7FE8), Color(0xFF5856D6)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            color: hasMyStatus ? null : const Color(0xFF1C1C1E),
                          ),
                          padding: const EdgeInsets.all(2.5),
                          child: Container(
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
                            ),
                            padding: const EdgeInsets.all(2.5),
                            child: const CircleAvatar(
                              radius: 26,
                              backgroundImage: AssetImage('assets/noprofile.png'),
                            ),
                          ),
                        ),
                        // Always show + icon
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: const Color(0xFF007AFF),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                            ),
                            child: const Icon(Icons.add, size: 12, color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          } else {
            // Friend status circle
            final friendStatuses = uniqueFriendStatuses[index - 1];
            final storyKey = GlobalKey(); // Add a GlobalKey here
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                key: storyKey, // Assign the key to the GestureDetector
                onTap: () {
                  // Get the position of the status circle
                  final RenderBox? renderBox = storyKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox == null) return;

                  final offset = renderBox.localToGlobal(Offset.zero);
                  final circleCenter = offset + Offset(renderBox.size.width / 2, renderBox.size.height / 2);

                  // View friend statuses with CircularRevealPageRoute
                  Navigator.push(
                    context,
                    CircularRevealPageRoute(
                      builder: (context) => StatusViewerScreen(statuses: friendStatuses),
                      originOffset: circleCenter,
                      originRadius: 32.0, // Status circle radius
                    ),
                  );
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF8B7FE8), Color(0xFF5856D6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.all(2.5),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black,
                        ),
                        padding: const EdgeInsets.all(2.5),
                        child: const CircleAvatar(
                          radius: 26,
                          backgroundImage: AssetImage('assets/noprofile.png'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        },
      ),
    );
  }

  // Updated chip function with single selection handling
  Widget chip(String name, [int? count]) {
    bool isSelected = selectedChip == name;  // Check if the chip is selected

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
              color: isSelected ? Color(0xFF5856D6) : Color(0xFF1C1C1E),
              borderRadius: const BorderRadius.all(
                Radius.circular(100),
              ),
            ),
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(left: 15, right: 15),
                child: Row(
                  children: [
                    // Display the count if it exists, or an empty string if count is null
                    // if (count != null && count != 0 && !isSelected)
                    //   Padding(
                    //     padding: const EdgeInsets.only(right: 8.0),
                    //     child: Container(
                    //       width: 6,
                    //       height: 6,
                    //       decoration: BoxDecoration(
                    //         color: isSelected ? Colors.white : Color.fromARGB(255, 0, 122, 255),
                    //         borderRadius: BorderRadius.all(
                    //           Radius.circular(100)
                    //         )
                    //       ),
                    //     ),
                    //   ),

                    Text(
                      name,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Color(0xFFFFFFFF).withAlpha(150),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),

                    // Display the count if it exists, or an empty string if count is null
                    if (count != null && count != 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Text(
                          '(${count >= 10 ? '9+' : count.toString()})',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Color.fromARGB(140, 255, 255, 255),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
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
    );
  }
}