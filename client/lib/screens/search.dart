import 'package:client/screens/home.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'dart:async';
import 'package:client/services/auth_service.dart';
import 'package:shimmer/shimmer.dart';

import '../services/api_service.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _users = [];
  Timer? _debounce;
  bool _isLoading = false;
  late String? uuid;
  List <String> outgoingRequest = [];
  late ApiService apiService;

  @override
  void initState() {
    super.initState();

    setupAPIService().then((_) {

    });

    _searchController.addListener(() {
      if (_searchController.text.isNotEmpty) {
        setState(() {
          _isLoading = true;
        });
      } else if (_searchController.text.isEmpty) {
        setState(() {
          _isLoading = false;
        });
      }
      
      if (_debounce?.isActive ?? false) _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () {
        searchUsers(_searchController.text);
      });
    });
  }

  // Function to search for users
  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _users = [];
      });
      return;
    }

    try {
      final users = await apiService.searchUsers(query);
      setState(() {
        _isLoading = false;
        _users = users;
      });
    } catch (error) {
      setState(() {
        _users = [];
        _isLoading = false;
      });
      if (kDebugMode) {
        print('$error');
      }
    }
  }

  Future<void> setupAPIService() async {
    uuid = (await fetchUuid())!;

    apiService = ApiService();
    apiService.init(uuid);
  }

  Future<String?> fetchUuid() async {
    String? userUuid = await AuthService.getUserUuid();
    if (userUuid != null) {
      return userUuid;
    }

    return null;
  }

  void sendFriendRequest(String friendId, String firstName) async {
    setState(() {
      outgoingRequest.add(friendId);
    });

    try {
      apiService.sendFriendRequest(friendId, uuid!);
      _showToast("Friend request sent to $firstName!");
    } catch (error) {
      _showToast("Error sending friend request: $error");
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          "Search",
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => Home()), // Replace with your home screen widget
            );
          },
          child: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: 24,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0), // Height of the border
          child: Container(
            color: Colors.grey.withAlpha(50),
            height: 1.0,
          ),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Row(
              children: [
                const SizedBox(height: kToolbarHeight,),

                Flexible(
                  child: CupertinoSearchTextField(
                    controller: _searchController,
                    placeholder: "Search for friends...",
                    placeholderStyle: const TextStyle(color: Color(0xFF8E8E93), fontSize: 16),
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    backgroundColor: Color(0xFF1C1C1E),
                    itemColor: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    onChanged: (value) {
                      // The debounce mechanism handles the search
                    },
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
              ],
            ),
            
            const SizedBox(height: 5,),
            
            Expanded(
              child: _isLoading
                  ? ListView.builder(
                      itemCount: 20,
                      itemBuilder: (context, index) {
                        return ListTile(
                          contentPadding: EdgeInsets.all(0),
                          leading: Shimmer.fromColors(
                            baseColor: Colors.grey[100]!.withAlpha(50),
                            highlightColor: Colors.grey[100]!.withAlpha(75),
                            period: Duration(seconds: 2), // Smooth out the animation
                            direction: ShimmerDirection.ltr, // Set direction for shimmer animation
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(100),
                                borderRadius: BorderRadius.all(Radius.circular(24)),
                              ),
                            ),
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Shimmer.fromColors(
                                baseColor: Colors.grey[100]!.withAlpha(50),
                                highlightColor: Colors.grey[100]!.withAlpha(75),
                                period: Duration(seconds: 2), // Smooth out the animation
                                direction: ShimmerDirection.ltr, // Set direction for shimmer animation
                                child: Container(
                                  width: 200,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(100),
                                  ),
                                ),
                              ),
            
                              const SizedBox(height: 5,),
            
                              Shimmer.fromColors(
                                baseColor: Colors.grey[100]!.withAlpha(50),
                                highlightColor: Colors.grey[100]!.withAlpha(75),
                                period: Duration(seconds: 2), // Smooth out the animation
                                direction: ShimmerDirection.ltr, // Set direction for shimmer animation
                                child: Container(
                                  width: 100,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withAlpha(100),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : _users.isEmpty ? Center(
                          child: Text(
                            "",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _users.length,
                          itemBuilder: (context, index) {
                            var user = _users[index];
                            String profilePicture = user['profile_picture'] ?? 'assets/noprofile.png';

                            String buttonText = getButtonText(user, uuid, outgoingRequest);

                            return ListTile(
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
                                      Row(
                                        children: [
                                          Text(
                                            '${user['first_name']} ${user['last_name']}',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                              letterSpacing: -0.3,
                                              height: 1.5
                                            ),
                                          ),

                                          const SizedBox(width: 8,),

                                          Icon(
                                            CupertinoIcons.checkmark_seal_fill,
                                            color: Color.fromARGB(255, 0, 122, 255),
                                            size: 16
                                          )
                                        ],
                                      ),
                                      if (user['username'] != null)
                                        Text(
                                          '@${user['username']}',
                                          style: TextStyle(
                                            color: Color(0xFF76767B),
                                            fontWeight: FontWeight.w500,
                                            fontSize: 15,
                                            letterSpacing: -0.3,
                                            height: 1.4
                                          ),
                                        ),
                                    ],
                                  ),
            
                                  uuid != user['id'] ? SizedBox(
                                    height: 30,
                                    child: ElevatedButton(
                                      onPressed: () => {
                                        if (buttonText == "Add") {
                                          sendFriendRequest(user['id'], user['first_name'])
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color(0xFF1C1C1E),
                                        // side: BorderSide(color: buttonText == "Message" ? Colors.grey : Colors.transparent, width: 1.5), // Add grey border
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(100),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: Text(
                                        buttonText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white.withAlpha(175),
                                        ),
                                      ),
                                    ),
                                  ) : SizedBox(),

                                ],
                              ),

                            );
                          },
                        ),
            
            ),
          ],
        ),
      ),
    );
  }

  String getButtonText(Map<String, dynamic> user, String? uuid, List<String> outgoingRequest) {
    if (outgoingRequest.contains(user['id'])) return "Pending";

    switch (user['status']) {
      case "accepted":
        return "Message";
      case "pending":
        return user['sender'] == uuid ? "Pending" : "Accept";
      case "not_friends":
        return "Add";
      default:
        return "Add";
    }
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.TOP,
      backgroundColor: Color(0xFF212121),
      textColor: Colors.white,
      fontSize: 14.0,
    );
  }
}