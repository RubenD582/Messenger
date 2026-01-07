import 'dart:async';
import 'dart:ui';
import 'package:client/screens/notifications.dart';

import 'package:client/screens/chat_screen.dart';
import 'package:client/screens/status_creation_screen.dart';
import 'package:client/screens/status_viewer_screen.dart';
import 'package:client/models/status.dart';
import 'package:client/models/message.dart';
import 'package:client/database/message_database.dart';
import 'package:client/transitions/circular_page_route.dart';
import 'package:client/widgets/segmented_status_ring.dart';
import 'package:client/services/status_view_service.dart';
import 'discover.dart' as discover;
import 'package:client/services/api_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/location_service.dart';
import 'package:client/theme/colors.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hive/hive.dart';
import 'package:fluttertoast/fluttertoast.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final ScrollController _scrollController = ScrollController();

  double _scrollYOffset = 0.0;
  double _scrollYOpacity = 0.0;

  List<Map<String, dynamic>> _friends = [];
  late Box _friendsBox;

  String? selectedChip = "All";
  late ApiService apiService;
  bool isLoading = true;

  late StreamSubscription<int> _pendingFriendRequestsSubscription;

  // Status state
  List<Status> _myStatuses = [];
  List<Status> _friendStatuses = [];
  late StreamSubscription<Map<String, dynamic>> _statusCreatedSubscription;
  late StreamSubscription<Map<String, dynamic>> _statusDeletedSubscription;

  late String uuid;
  final LocationService _locationService = LocationService();

  // Message state
  Map<String, int> _unreadCounts = {}; // conversationId -> unread count
  Map<String, bool> _typingStatus = {}; // conversationId -> is typing
  Map<String, String> _lastMessages = {}; // conversationId -> last message text
  late StreamSubscription<Map<String, dynamic>> _newMessageSubscription;
  late StreamSubscription<Map<String, dynamic>> _typingIndicatorSubscription; // ADDED THIS LINE
  late StreamSubscription<Map<String, dynamic>> _readReceiptSubscription;
  late StreamSubscription _homeNotificationStreamSubscription; // For home widget's notification listener
  late StreamSubscription<void> _friendListUpdateSubscription; // For friend list updates

  // Notification state
  int _unreadNotificationCount = 0;

  int _selectedIndex = 0;
  final List<String> _pageTitles = ["Home", "Search", "Notifications", "Profile"];

  void _onItemTapped(int index) {
    if (_selectedIndex != index) {
      _scrollController.jumpTo(0);
    }

    if (index == 2) {
      // User tapped on the notifications tab
      setState(() {
        _unreadNotificationCount = 0; // Reset unread count
      });
      apiService.markAllNotificationsAsRead(); // Mark all as read on backend
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();

    // Initialize status view service and clear old views
    StatusViewService.init().then((_) {
      StatusViewService.clearOldViews();
    });

    setupAPIService().then((didSucceed) {
      if (!didSucceed) {
        if (mounted) {
          _showErrorDialog("User authentication failed. Please restart the app.");
        }
        return;
      }
      
      fetchRequestCount();

      // Load statuses (async, doesn't block)
      _loadStatuses();

      // Setup WebSocket listeners BEFORE connecting
      _setupStatusListeners();
      _setupMessageListeners();

      // CRITICAL: Load friends FIRST, THEN connect socket
      // This ensures the UI is ready to display delivered messages
      _openFriendsBox().then((_) async {
        await fetchFriends();
        // Fetch unread counts after friends are loaded
        await _fetchUnreadCounts();

        // NOW connect the WebSocket after everything is ready
        apiService.connectWebSocket(uuid);
        if (kDebugMode) {
          print("✅ WebSocket connected after friends loaded - ready for queued messages");
        }
      });

      // Update location on app launch/login
      _updateLocationOnLaunch();

      _scrollController.addListener(() {
        setState(() {
          _scrollYOffset =
              -(_scrollController.offset / 5).clamp(-100.0, 0.0);
          _scrollYOpacity = (_scrollController.offset / 75).clamp(0, 1);
        });
      });

                _pendingFriendRequestsSubscription = apiService.pendingRequestsStream
                    .listen((count) {
                      setState(() {
                      });
                    });
      
            // Listen for new notifications in the Home widget
            _homeNotificationStreamSubscription = apiService.newNotificationStream.listen((notification) {
              if (!mounted) return;

              final type = notification['type'];

              // Increment unread count for unread notifications
              if (notification['read'] == false || notification['read'] == null) {
                setState(() {
                  _unreadNotificationCount++;
                });
              }

              // Refresh friend list when a friend request is accepted
              if (type == 'FRIEND_REQUEST_ACCEPTED') {
                if (kDebugMode) {
                  print('🎉 Friend request accepted! Refreshing friend list...');
                }
                // Refresh friend list in the background
                fetchFriends();
              }
            });

            // Listen for friend list update triggers (when user accepts a request)
            _friendListUpdateSubscription = apiService.friendListUpdateStream.listen((_) {
              if (mounted) {
                if (kDebugMode) {
                  print('🎉 Refreshing friend list after accepting request...');
                }
                fetchFriends();
              }
            });
          }).catchError((error) {      _showErrorDialog(error.toString()); // Show error dialog
    });
  }

  String formatRelativeTime(String isoString) {
    final now = DateTime.now();
    final then = DateTime.parse(isoString);
    final difference = now.difference(then);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '${years}y';
    } else if (difference.inDays >= 30) {
      final months = (difference.inDays / 30).floor();
      return '${months}M';
    } else if (difference.inDays >= 7) {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}w';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else if (difference.inSeconds > 0) {
      return '${difference.inSeconds}s';
    } else {
      return 'Just Now';
    }
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
              print(
                'Location updated on home screen launch: $city, $state, $country',
              );
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
      _friendsBox
          .get('${uuid}_friends', defaultValue: [])
          .map((friend) => Map<String, dynamic>.from(friend)),
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

  Future<bool> setupAPIService() async {
    String? userUuid = await fetchUuid();

    if (userUuid == null) {
      if (kDebugMode) {
        print("CRITICAL: User UUID is null. API service cannot be initialized.");
      }
      return false;
    }

    uuid = userUuid;
    apiService = ApiService();

    // Initialize API service but DON'T connect socket yet
    apiService.init(uuid, connectSocket: false);

    if (kDebugMode) {
      print("API Service Initialized Successfully for UUID: $uuid");
    }
    return true;
  }

  Future<void> fetchRequestCount() async {
    try {
          await apiService.getRequestCount();
      setState(() {
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
      _myStatuses =
          myStatusesData.map((data) => Status.fromJson(data)).toList();

      // Load friend statuses and mark as viewed based on local storage
      final friendStatusesData = await apiService.getFriendStatuses();
      _friendStatuses =
          friendStatusesData.map((data) {
            final status = Status.fromJson(data);
            // Check if this status has been viewed in local storage
            final hasViewed = StatusViewService.hasViewed(status.id);
            return status.copyWith(hasViewed: hasViewed);
          }).toList();

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

  void _setupMessageListeners() {
    // Listen for new messages
    _newMessageSubscription = apiService.newMessageStream.listen((data) async {
      if (kDebugMode) {
        print('New message received: $data');
      }

      // CRITICAL: Save message to local database immediately
      // This ensures it's available when opening the chat screen
      try {
        final message = Message.fromJson(data);
        await MessageDatabase.insertMessage(message);
        if (kDebugMode) {
          print('✅ Saved message to local DB from home screen: ${message.messageId}');
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error saving message to local DB: $e');
        }
      }

      // Update unread count and last message for the conversation
      final conversationId = data['conversationId'] as String?;
      final senderId = data['senderId'] as String?;
      final message = data['message'] as String?;

      if (conversationId != null && message != null) {
        setState(() {
          // Store the last message text
          _lastMessages[conversationId] = message;

          // Only increment unread count if the message is from someone else
          if (senderId != null && senderId != uuid) {
            _unreadCounts[conversationId] =
                (_unreadCounts[conversationId] ?? 0) + 1;
          }
        });
      }
    });

    // Listen for typing indicators
    _typingIndicatorSubscription = apiService.typingIndicatorStream.listen((
      data,
    ) {
      if (kDebugMode) {
        print('Typing indicator received: $data');
      }

      final conversationId = data['conversationId'] as String?;
      final isTyping = data['isTyping'] as bool? ?? false;

      if (conversationId != null) {
        setState(() {
          _typingStatus[conversationId] = isTyping;
        });
      }
    });

    // Listen for read receipts
    _readReceiptSubscription = apiService.readReceiptStream.listen((data) {
      if (kDebugMode) {
        print('Read receipt received: $data');
      }

      final conversationId = data['conversationId'] as String?;

      if (conversationId != null) {
        setState(() {
          _unreadCounts[conversationId] = 0;
        });
      }
    });
  }

  Future<void> _fetchUnreadCounts() async {
    try {
      // Initialize unread counts to 0 for all friends
      // Real-time updates will come from WebSocket events
      for (var friend in _friends) {
        final conversationId = _getConversationId(uuid, friend['friend_id']);

        if (!_unreadCounts.containsKey(conversationId)) {
          setState(() {
            _unreadCounts[conversationId] = 0;
          });
        }
      }
    } catch (error) {
      if (kDebugMode) {
        print('Error initializing unread counts: $error');
      }
    }
  }

  void _openStatusCreationScreen(GlobalKey statusCircleKey) {
    // Get the position of the status circle
    final RenderBox? renderBox =
        statusCircleKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

     // final offset = renderBox.localToGlobal(Offset.zero);
     // final circleCenter =
     //     offset + Offset(renderBox.size.width / 2, renderBox.size.height / 2);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => StatusCreationScreen(apiService: apiService),
      ),
    );
  }

  void _showSearchModal() {
    showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder:
              (context) => Stack(
                children: [
                  BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                  DraggableScrollableSheet(
                initialChildSize: 0.9,
                minChildSize: 0.5,
                maxChildSize: 0.95,
                builder: (_, controller) {
                  return ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black,
                      ),
                      child: discover.DiscoverScreen(),
                    ),
                  );
                },
              ),
                ],
              ),
    );
  }

  @override
  void dispose() {
    _pendingFriendRequestsSubscription.cancel();
    _statusCreatedSubscription.cancel();
    _statusDeletedSubscription.cancel();
    _newMessageSubscription.cancel();
    _typingIndicatorSubscription.cancel();
    _readReceiptSubscription.cancel();
    _homeNotificationStreamSubscription.cancel(); // Cancel subscription
    _friendListUpdateSubscription.cancel(); // Cancel friend list update subscription
    apiService.disconnectWebSocket();

    _scrollController.dispose();

    super.dispose();
  }

  Future<void> _refreshContent() async {
    await Future.delayed(Duration(seconds: 2));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey[900]!, width: 0.5),
          ),
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.black,
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: SizedBox(
                width: 24,
                height: 24,
                child: Opacity(
                  opacity: 0.5,
                  child: SvgPicture.asset('assets/home.svg'),
                ),
              ),
              activeIcon: SizedBox(
                width: 24,
                height: 24,
                child: SvgPicture.asset('assets/home.svg'),
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: SizedBox(
                width: 24,
                height: 24,
                child: Opacity(
                  opacity: 0.5,
                  child: Icon(CupertinoIcons.search, color: Colors.white),
                ),
              ),
              activeIcon: SizedBox(
                width: 24,
                height: 24,
                child: Icon(CupertinoIcons.search, color: Colors.white),
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Stack(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Opacity(
                      opacity: 0.5,
                      child: Icon(CupertinoIcons.bell, color: Colors.white),
                    ),
                  ),
                  if (_unreadNotificationCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: Text(
                          _unreadNotificationCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                ],
              ),
              activeIcon: Stack(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Icon(CupertinoIcons.bell, color: Colors.white),
                  ),
                  if (_unreadNotificationCount > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: Text(
                          _unreadNotificationCount.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                ],
              ),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: SizedBox(
                width: 24,
                height: 24,
                child: Opacity(
                  opacity: 0.5,
                  child: SvgPicture.asset('assets/profile.svg'),
                ),
              ),
              activeIcon: SizedBox(
                width: 24,
                height: 24,
                child: SvgPicture.asset('assets/profile.svg'),
              ),
              label: '',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          showSelectedLabels: false,
          showUnselectedLabels: false,
          type: BottomNavigationBarType.fixed,
        ),
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (_selectedIndex != 0)
            SliverAppBar(
              backgroundColor: AppColors.background,
              pinned: true,
              centerTitle: true,
              toolbarHeight: 40.0,
              title: Text(
                _pageTitles[_selectedIndex],
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          else
            SliverAppBar(
              backgroundColor: Colors.transparent,
              floating: true,
              pinned: true,
              scrolledUnderElevation: 0.0,
              expandedHeight: 60,
              toolbarHeight: 40,
              automaticallyImplyLeading: false,
              flexibleSpace: Builder(
                builder: (context) {
                  return Container(
                    decoration: const BoxDecoration(color: AppColors.background),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => discover.DiscoverScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  CupertinoIcons.search,
                                  color: Colors.white,
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: SvgPicture.asset(
                                    'assets/way.svg',
                                    height: 20,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  _showSearchModal();
                                },
                                icon: const Icon(
                                  CupertinoIcons.square_pencil,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          if (_selectedIndex == 0) ...[
            // **Stories Bar (UI Mockup)**
            if (selectedChip == "All" || selectedChip == "Status")
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 12),
                sliver: SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: Offset(0, _scrollYOffset * 0.5),
                    child: _buildStoriesBar(),
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                sliver: SliverToBoxAdapter(
                child: Transform.translate(
                  offset: Offset(0, _scrollYOffset * 0.75),
                  child: Container(
                    padding: const EdgeInsets.only(
                      left: 12,
                      right: 12,
                    ),
                    child: AnimatedOpacity(
                      opacity: 1 - _scrollYOpacity,
                      duration: const Duration(milliseconds: 200),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            chip("All"),
                            const SizedBox(width: 6),
                            chip("Pinned"),
                            const SizedBox(width: 6),
                            chip("Status"),
                            const SizedBox(width: 6),
                            Container(
                              height: 32,
                              width: 32,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF1C1C1E),
                              ),
                              child: Icon(
                                Icons.add,
                                color: Colors.white.withAlpha(150),
                                size: 18,
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

            // **Friend List**
            if (selectedChip != "Status")
              if (_friends.isEmpty && !isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(),
                )
              else
                SliverToBoxAdapter(
                  child: Transform.translate(
                    offset: Offset(0, _scrollYOffset),
                    child: Container(
                      child: friendList(),
                    ),
                  ),
                ),
          ] else if (_selectedIndex == 2) ...[
            NotificationsScreen(
              apiService: apiService,
              formatRelativeTime: formatRelativeTime,
            )
          ] else ...[
            SliverFillRemaining(
              child: Center(
                child: Text(
                  'Screen for index $_selectedIndex',
                  style: TextStyle(color: Colors.white)
                )
              )
            )
          ]
        ],
      ),
    );
  }


  Widget friendList() {
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

          // Get conversation ID for this friend
          final conversationId = _getConversationId(uuid, user['friend_id']);

          // Real data from WebSocket streams
          final bool isTyping = _typingStatus[conversationId] ?? false;
          final int unreadCount = _unreadCounts[conversationId] ?? 0;

          // Mock data for features not yet implemented

          final String lastMessage =
              _lastMessages[conversationId] ?? 'Say Hi!';
          final String timestamp =
              index % 6 == 0
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

          return Column(
            children: [
              Dismissible(
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
                  child: Icon(
                    Icons.push_pin,
                    color: Colors.white,
                    size: 20,
                    weight: 300,
                  ),
                ),
                secondaryBackground: Container(
                  color: Color(0xFFFF3B30),
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: 20),
                  child: Icon(Icons.delete, color: Colors.white, size: 24),
                ),
                child: InkWell(
                  onTap: () {
                    final conversationId = _getConversationId(
                      uuid,
                      user['friend_id'],
                    );
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => ChatScreen(
                              conversationId: conversationId,
                              friendId: user['friend_id'],
                              friendName:
                                  '${user['first_name']} ${user['last_name']}',
                              apiService: apiService,
                            ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Profile picture with online status
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Color(0xFF2C2C2E),
                              backgroundImage: AssetImage(profilePicture),
                            ),
                          ],
                        ),
                        SizedBox(width: 12),
                        // Message and name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Name at the top with badge
                              Row(
                                children: [
                                  Text(
                                    '${user['first_name']} ${user['last_name']}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (user['developer'] == true || user['verified'] == true) ...[
                                    const SizedBox(width: 6),
                                    _buildVerificationBadge(user['developer'] == true, user['verified'] == true),
                                  ],
                                ],
                              ),
                              SizedBox(height: 4),
                              // Message and timestamp below name
                              isTyping
                                  ? Text(
                                      'Typing...',
                                      style: TextStyle(
                                        color: Color(0xFF30D158),
                                        fontSize: 13,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    )
                                  : unreadCount > 0
                                      ? RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '$unreadCount New Message${unreadCount > 1 ? 's' : ''}',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              TextSpan(
                                                text: ' • ',
                                                style: TextStyle(
                                                  color: Color(0xFF8E8E93),
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              TextSpan(
                                                text: timestamp,
                                                style: TextStyle(
                                                  color: Color(0xFF8E8E93),
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : RichText(
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: lastMessage,
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              TextSpan(
                                                text: ' • ',
                                                style: TextStyle(
                                                  color: Color(0xFF8E8E93),
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 12,
                                                ),
                                              ),
                                              TextSpan(
                                                text: timestamp,
                                                style: TextStyle(
                                                  color: Color(0xFF8E8E93),
                                                  fontWeight: FontWeight.w400,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 200),
      child: Center(
        child: ElevatedButton.icon(
          onPressed: _showSearchModal,
          // icon: const Icon(CupertinoIcons.add_circled_solid, color: Colors.white), // Filled icon
          label: const Text(
            'Add Friends',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
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
      height: 70,
      padding: EdgeInsets.zero,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount:
            1 + uniqueFriendStatuses.length, // "Your Story" + unique friends
        itemBuilder: (context, index) {
          final isYou = index == 0;

          if (isYou) {
            // "Your Story" circle
            final yourStoryKey = GlobalKey();
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () {
                  if (hasMyStatus) {
                    // Show action sheet to view or create
                    showCupertinoModalPopup(
                      context: context,
                      builder:
                          (BuildContext context) => CupertinoActionSheet(
                            actions: [
                              CupertinoActionSheetAction(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => StatusViewerScreen(
                                            statuses: _myStatuses,
                                            currentUserId: uuid,
                                            apiService: apiService,
                                          ),
                                    ),
                                  ).then((_) {
                                    // Reload statuses when coming back
                                    _loadStatuses();
                                  });
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
                        hasMyStatus
                            ? SegmentedStatusRing(
                              segmentCount: _myStatuses.length,
                              size: 64,
                              strokeWidth: 2.5,
                              child: const CircleAvatar(
                                radius: 26,
                                backgroundImage: AssetImage(
                                  'assets/noprofile.png',
                                ),
                              ),
                            )
                            : Container(
                              width: 64,
                              height: 64,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF48484A),
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
                                  backgroundImage: AssetImage(
                                    'assets/noprofile.png',
                                  ),
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
                            child: const Icon(
                              Icons.add,
                              size: 12,
                              color: Colors.white,
                            ),
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
            final viewedCount =
                friendStatuses.where((status) => status.hasViewed).length;

            // Find the first unviewed status index
            final firstUnviewedIndex = friendStatuses.indexWhere(
              (status) => !status.hasViewed,
            );
            final initialIndex =
                firstUnviewedIndex != -1 ? firstUnviewedIndex : 0;

            final storyKey = GlobalKey(); // Add a GlobalKey here
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                key: storyKey, // Assign the key to the GestureDetector
                onTap: () {
                  // Get the position of the status circle
                  final RenderBox? renderBox =
                      storyKey.currentContext?.findRenderObject() as RenderBox?;
                  if (renderBox == null) return;

                  final offset = renderBox.localToGlobal(Offset.zero);
                  // final circleCenter =
                      offset +
                      Offset(
                        renderBox.size.width / 2,
                        renderBox.size.height / 2,
                      );

                  // View friend statuses with CircularRevealPageRoute
                  // Start from the first unviewed status
                  Navigator.push(
                    context,
                    CircularRevealPageRoute(
                      builder:
                          (context) => StatusViewerScreen(
                            statuses: friendStatuses,
                            currentUserId: uuid,
                            apiService: apiService,
                            initialIndex: initialIndex,
                          ),
                      originOffset: Offset(0, 0), // Provide a default offset
                      originRadius: 32.0, // Status circle radius
                    ),
                  ).then((_) {
                    // Reload statuses when coming back to update viewed status
                    _loadStatuses();
                  });
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SegmentedStatusRing(
                      segmentCount: friendStatuses.length,
                      viewedCount: viewedCount,
                      size: 64,
                      strokeWidth: 2.5,
                      child: const CircleAvatar(
                        radius: 26,
                        backgroundImage: AssetImage('assets/noprofile.png'),
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

  Widget _buildVerificationBadge(bool isDeveloper, bool isVerified) {
    // Developer badge takes priority
    if (isDeveloper) {
      return SvgPicture.asset(
        'assets/developer.svg',
        width: 16,
        height: 16,
      );
    } else if (isVerified) {
      return SvgPicture.asset(
        'assets/verified.svg',
        width: 16,
        height: 16,
      );
    }
    return const SizedBox.shrink();
  }
}
