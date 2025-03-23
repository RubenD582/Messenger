import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:client/services/auth.dart';
import 'package:shimmer/shimmer.dart';

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

  // Function to search for users
  Future<void> _searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() {
        _users = [];
      });
      return;
    }

    // Get the JWT token from secure storage
    final token = await AuthService.getToken();
    if (token == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    // Make the search request
    try {
      final response = await http.get(
        Uri.parse('http://localhost:3000/friends/search?q=$query'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _users = json.decode(response.body)['users'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _users = [];
          _isLoading = false;
        });
        if (kDebugMode) {
          print(response.body);
        }
      }
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

  @override
  void initState() {
    super.initState();

    fetchUuid();

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
        _searchUsers(_searchController.text);
      });
    });
  }

  Future<void> fetchUuid() async {
    String? userUuid = await AuthService.getUserUuid();
    if (userUuid != null) {
      setState(() {
        uuid = userUuid;  // Update the uuid in the state
      });
    } else {
      setState(() {
        uuid = null;  // If no UUID is found, set it to null
      });
    }
  }


  void sendFriendRequest(String friendId, String firstName) async {
    const String baseUrl = "http://localhost:3000";
    final url = Uri.parse('$baseUrl/friends/send-request');

    setState(() {
      outgoingRequest.add(friendId);
    });

    if (uuid == null) {
      return;
    }

    final body = json.encode({
      'friendId': friendId,
      'userId': uuid
    });

    final token = await AuthService.getToken();
    if (token == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: body,
      );

      if (response.statusCode == 201) {
        if (kDebugMode) {
          print("Friend request sent successfully!");
        }

        _showToast("Friend request sent to $firstName!");
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        if (kDebugMode) {
          print("${errorData['message']}");
        }

        _showToast("${errorData['message']}");
      } else {
        if (kDebugMode) {
          print("${response.statusCode}, ${response.body}");
        }

        _showToast("${response.statusCode}, ${response.body}");
      }
    } catch (error) {
      if (kDebugMode) {
        print("Error sending friend request: $error");
      }

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
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.9,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Container(
              width: 60,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(
                  Radius.circular(100),
                ),
                color: Colors.white.withAlpha(25),
              ),
            ),

            const SizedBox(height: 15,),

            Row(
              children: [
                Flexible(
                  child: CupertinoSearchTextField(
                    controller: _searchController,
                    placeholder: "Search for username...",
                    padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    backgroundColor: Color(0xFF1C1C1E),
                    itemColor: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                    onChanged: (value) {
                      // The debounce mechanism handles the search
                    },
                    onSubmitted: (value) {},
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        CupertinoIcons.search,
                        color: Colors.white.withAlpha(100),
                      ),
                    ),
                    suffixIcon: Icon(null),
                  ),
                ),

                const SizedBox(width: 10,),

                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.all(
                      Radius.circular(100),
                    ),
                    color: Colors.white.withAlpha(25),
                  ),
                  child: GestureDetector(
                    child: Icon(Icons.clear, size: 18, color: Colors.white.withAlpha(150),),
                    onTap: () {
                      Navigator.pop(context);
                    },
                  ),
                )
              ],
            ),

            const SizedBox(height: 20,),

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
                  : _users.isEmpty
                      ? Center(
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
                                      Text(
                                        '${user['username']}${uuid != user['id'] ? '' : ' (Me)'}',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
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

                                  uuid != user['id'] ? SizedBox(
                                    height: 30,
                                    child: ElevatedButton(
                                      onPressed: () => {
                                        if (buttonText == "Add") {
                                          sendFriendRequest(user['id'], user['first_name'])
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Color(0xFF1C1C1E), // Remove background color
                                        // side: BorderSide(color: buttonText == "Message" ? Colors.grey : Colors.transparent, width: 1.5), // Add grey border
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: Text(
                                        buttonText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
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
