import 'dart:async';
import 'dart:ui';

import 'package:client/screens/requests.dart';
import 'search.dart';
import 'package:client/services/api_service.dart';
import 'package:client/services/auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';
import 'package:hive/hive.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  double _scrollOffset = 0.0;
  double _scrollYOffset = 0.0;
  double _scrollYOpacity = 0.0;

  List<Map<String, dynamic>> _friends = [];
  late Box _friendsBox;

  String? selectedChip = "All";
  late ApiService apiService;
  bool isLoading = true;

  late StreamSubscription<int> _pendingFriendRequestsSubscription;
  int _pendingFriendRequestsCount = 0;

  late String uuid;

  @override
  void initState() {
    super.initState();

    setupAPIService().then((_) {
      fetchRequestCount();

      // Open the Hive box first
      _openFriendsBox().then((_) {
        fetchFriends();
      });

      _scrollController.addListener(() {
        setState(() {
          _scrollOffset = _scrollController.offset;
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
        _friends += friends;
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
  
  void _showSearchModal() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SearchPage()),
    );
  }


  @override
  void dispose() {
    _pendingFriendRequestsSubscription.cancel();
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
                                  child: Text(
                                    "Messages",
                                    textAlign: TextAlign.left,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: textSize,  // Animate the text size
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Row(
                                  children: [
                                    _iconButton(Icons.more_horiz, Colors.white.withAlpha(50), _showSearchModal),
                                    const SizedBox(width: 10),
                                    _iconButton(Icons.add, Color.fromARGB(255, 0, 122, 255), _showSearchModal),
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
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              color: Colors.black,
              child: Transform.translate(
                offset: Offset(
                  0, 
                  _scrollYOffset
                ),
      
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  placeholder: "Search...",
                  placeholderStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 16),
                  style: TextStyle(color: Colors.white),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                  backgroundColor: Color(0xFF1C1C1E),
                  itemColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  onChanged: (value) {},
                  onSubmitted: (value) {},
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(top: 5, left: 8),
                    child: Icon(
                      CupertinoIcons.search,
                      color: Color(0xFF8E8E93),
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
                  padding: EdgeInsets.only(left: 10, right: 10, top: 2, bottom: 20),
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
      
          // **Friend List / Requests**
          SliverFillRemaining(
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
    return RefreshIndicator(
      backgroundColor: Colors.transparent,
      color: Colors.white,
      onRefresh: _refreshContent,
      child: ListView.builder(
        padding: EdgeInsets.only(top: 0),
        shrinkWrap: true,
        physics: NeverScrollableScrollPhysics(),
        itemCount: _friends.length,
        itemBuilder: (context, index) {
          var user = _friends[index];
          String profilePicture = 'assets/noprofile.png';
      
          return Dismissible(
            key: Key(user['id'].toString()), // Unique key for each item
            direction: DismissDirection.horizontal, // Allow swiping in both directions
            onDismissed: (direction) {
              if (direction == DismissDirection.endToStart) {
                // Delete action
                // deleteRequest(user['id']);
              } else if (direction == DismissDirection.startToEnd) {
                // Pin action
                // pinUser(user['id']);
              }
            },
      
            /// **Left Swipe (Delete)**
            background: Container(
              color: Colors.blue, // Pin action background
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.only(left: 20),
              child: Icon(
                Icons.push_pin, // Pin icon
                color: Colors.white,
              ),
            ),
      
            /// **Right Swipe (Pin)**
            secondaryBackground: Container(
              color: Colors.red, // Delete action background
              alignment: Alignment.centerRight,
              padding: EdgeInsets.only(right: 20),
              child: Icon(
                Icons.delete, // Trash icon
                color: Colors.white,
              ),
            ),
      
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                          '${user['first_name']} ${user['last_name']}',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          'Tap to send a message',
                          style: TextStyle(
                            color: Color(0xFF76767B),
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
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
              color: isSelected ? Color.fromARGB(255, 0, 122, 255) : Color(0xFF1C1C1E),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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