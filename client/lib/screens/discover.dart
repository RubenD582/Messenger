import 'dart:async';

import 'dart:convert';

import 'package:client/services/api_service.dart';

import 'package:client/services/auth_service.dart';

import 'package:client/services/location_service.dart';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:flutter/cupertino.dart';

import 'package:shimmer/shimmer.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  _DiscoverScreenState createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  late final ApiService _apiService;

  final LocationService _locationService = LocationService();

  final AuthService _authService = AuthService();

  String? _currentUserId;

  String? _username;

  bool _isLoadingSuggestions = false;

  List<Map<String, dynamic>> _suggestions = [];

  List<Map<String, dynamic>> _filteredSuggestions = [];

  Set<String> _sentRequests = {};

  bool _locationChecked = false;

  final TextEditingController _searchController = TextEditingController();

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();

    _apiService = ApiService();

    _searchController.addListener(_onSearchChanged);

    _loadCurrentUserAndInit();
  }

  void _onSearchChanged() {
    _debounceTimer?.cancel();

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      final query = _searchController.text.trim();

      if (query.isEmpty) {
        setState(() {
          _filteredSuggestions = _suggestions;
        });
      } else {
        _searchUsers(query);
      }
    });
  }

  Future<void> _searchUsers(String query) async {
    if (_currentUserId == null) return;

    try {
      final results = await _apiService.searchUsers(_currentUserId!, query);

      if (mounted) {
        setState(() {
          _filteredSuggestions = results;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error searching users: $e');
      }
    }
  }

  Future<void> _loadCurrentUserAndInit() async {
    final userId = await AuthService.getUserUuid();

    final userData = await _authService.getUserData();

    if (mounted) {
      setState(() {
        _currentUserId = userId;

        _username = userData?['username'];
      });

      if (userId != null) {
        _apiService.init(userId);

        await _checkLocationPermission();

        _fetchSuggestions();
      }
    }
  }

  Future<void> _checkLocationPermission() async {
    if (_locationChecked) return;

    setState(() {
      _locationChecked = true;
    });

    final isEnabled = await _locationService.isLocationEnabled();

    if (!isEnabled) {
      final success = await _locationService.enableLocationAndUpdate();

      if (mounted && success) {
        _fetchSuggestions();
      }
    }
  }

  Future<void> _fetchSuggestions() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoadingSuggestions = true;
    });

    try {
      final suggestions = await _apiService.getFriendSuggestions(
        _currentUserId!,
      );

      if (mounted) {
        setState(() {
          _suggestions = suggestions;

          _filteredSuggestions = suggestions;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching suggestions: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSuggestions = false;
        });
      }
    }
  }

  Future<void> _sendFriendRequest(String friendId) async {
    if (_currentUserId == null) return;

    setState(() {
      _sentRequests.add(friendId);
    });

    try {
      final result = await _apiService.sendFriendRequest(
        friendId,
        _currentUserId!,
      );

      if (result['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Friend request sent!'),

              backgroundColor: Colors.green[700],

              behavior: SnackBarBehavior.floating,

              duration: const Duration(seconds: 2),
            ),
          );
        }

        if (result['autoAccepted'] == true) {
          setState(() {
            _suggestions.removeWhere((user) => user['userId'] == friendId);

            _filteredSuggestions.removeWhere(
              (user) => user['userId'] == friendId,
            );
          });
        }
      } else {
        setState(() {
          _sentRequests.remove(friendId);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Failed to send request'),

              backgroundColor: Colors.red[700],

              behavior: SnackBarBehavior.floating,

              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error sending friend request: $e');
      }

      setState(() {
        _sentRequests.remove(friendId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Network error. Please try again.'),

            backgroundColor: Colors.red[700],

            behavior: SnackBarBehavior.floating,

            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _dismissSuggestion(String userId) {
    setState(() {
      _suggestions.removeWhere((user) => user['userId'] == userId);

      _filteredSuggestions.removeWhere((user) => user['userId'] == userId);
    });

    // Optionally, call an API to inform the backend about the dismissal
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 10, 10, 10),

      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 10, 10, 10),

        elevation: 0,

        scrolledUnderElevation: 0,

        surfaceTintColor: Colors.transparent,

        centerTitle: true,

        leading: IconButton(
          icon: const Icon(
            CupertinoIcons.chevron_down,
            color: Colors.white,
            size: 22,
          ),

          onPressed: () => Navigator.of(context).pop(),
        ),

        title: const Text(
          'Suggestions',

          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),

        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),

          child: Container(
            height: 1,

            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withAlpha(20), width: 1),
              ),
            ),
          ),
        ),
      ),

      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const SizedBox(height: 16),

            // Permanent Search TextField
            CupertinoSearchTextField(
              controller: _searchController,
              placeholder: 'Search for Friends...',
              backgroundColor: Colors.grey[900],
              itemColor: Colors.grey[600] ?? Colors.grey,
              style: const TextStyle(
                color: Colors.white,

                fontSize: 17,

                fontWeight: FontWeight.w400,
              ),

              placeholderStyle: TextStyle(
                color: Colors.grey[600],

                fontSize: 17,

                fontWeight: FontWeight.w400,
              ),
            ),

            const SizedBox(height: 20),

            // Invite Friends Container
            // Container(
            //   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

            //   decoration: BoxDecoration(
            //     color: Colors.grey[900],

            //     borderRadius: BorderRadius.circular(12),
            //   ),

            //   child: Row(
            //     children: [
            //       CircleAvatar(
            //         radius: 20,
            //         backgroundColor: Colors.white.withValues(alpha: 0.1),
            //         backgroundImage: const AssetImage('assets/noprofile.png'),
            //       ),

            //       const SizedBox(width: 12),

            //       Expanded(
            //         child: Column(
            //           crossAxisAlignment: CrossAxisAlignment.start,

            //           children: [
            //             const Text(
            //               'Invite friends',
            //               style: TextStyle(
            //                 color: Colors.white,
            //                 fontSize: 16,
            //                 fontWeight: FontWeight.w600,
            //               ),
            //             ),

            //             const SizedBox(height: 2),

            //             Text(
            //               _username != null
            //                   ? 'messenger.com/$_username'
            //                   : 'messenger.com/...',
            //               style: TextStyle(
            //                 color: Colors.grey[600],
            //                 fontSize: 15,
            //               ),

            //               overflow: TextOverflow.ellipsis,
            //             ),
            //           ],
            //         ),
            //       ),

            //       const SizedBox(width: 12),

            //       Icon(CupertinoIcons.share, color: Colors.grey[400]),
            //     ],
            //   ),
            // ),

            const SizedBox(height: 12),

            // Find Friends Title
            Text(
              'SUGGESTED FRIENDS',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 20),

            // Suggestions List
            Expanded(
              child:
                  _isLoadingSuggestions
                      ? _buildSuggestionsShimmer()
                      : _filteredSuggestions.isEmpty
                      ? Center(
                        child: Text(
                          _searchController.text.isNotEmpty
                              ? 'No results found'
                              : 'No suggestions available',

                          style: TextStyle(
                            color: Colors.grey[600],

                            fontSize: 14,
                          ),
                        ),
                      )
                                            : ListView.builder(
                                                itemCount: _filteredSuggestions.length,
                                                padding: const EdgeInsets.only(bottom: 20),
                                                physics: const NeverScrollableScrollPhysics(), // Added this line
                                                itemBuilder: (context, index) {
                                                  final user = _filteredSuggestions[index];
                                                  return _buildSuggestionRow(user);
                                                },
                                              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionRow(Map<String, dynamic> user) {
    final profilePicture = user['profile_picture'];

    final name = user['name'] ?? 'Unknown User';

    final username = user['username'];

    final userId = user['userId'] as String;

    final friendStatus = user['friendStatus'] ?? 'none';

    final isRequested =
        _sentRequests.contains(userId) || friendStatus == 'pending';

    final isFriend = friendStatus == 'friend';

    final score = (user['score'] ?? 0) as num;

    String suggestionReason;

    if (isFriend) {
      suggestionReason = 'Added';
    } else if (friendStatus == 'pending') {
      suggestionReason = 'Request pending';
    } else if (score >= 100) {
      suggestionReason = 'Suggested based on location';
    } else if (score >= 50) {
      suggestionReason = 'You may know';
    } else {
      suggestionReason = 'Suggested for you';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,

        children: [
          // Profile Picture
          CircleAvatar(
            radius: 24, // Increased size

            backgroundColor: Colors.grey[800],

            backgroundImage:
                (profilePicture != null && profilePicture.startsWith('http'))
                    ? NetworkImage(profilePicture)
                    : const AssetImage('assets/noprofile.png') as ImageProvider,
          ),

          const SizedBox(width: 14),

          // Name and Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              mainAxisSize: MainAxisSize.min,

              children: [
                Text(
                  username != null && username.isNotEmpty ? username : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2,),
                Text(
                  suggestionReason,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.1,
                  ),

                  overflow: TextOverflow.ellipsis,

                  maxLines: 1,
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Add Button
          SizedBox(
            width: 60, // Reduced width
            height: 30,
            child: ElevatedButton(
              onPressed:
                  (isRequested || isFriend)
                      ? null
                      : () => _sendFriendRequest(userId),

              style: ElevatedButton.styleFrom(
                splashFactory: NoSplash.splashFactory,

                backgroundColor:
                    (isRequested || isFriend)
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white.withValues(alpha: 0.2), // Grey color

                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(100),
                ),

                elevation: 0,

                padding: EdgeInsets.zero,
              ),

              child: Text(
                isFriend ? "Friend" : (isRequested ? "Added" : "Add"),

                style: TextStyle(
                  fontSize: 13,

                  fontWeight: FontWeight.w600,

                  color:
                      (isRequested || isFriend)
                          ? Colors.grey[500]
                          : Colors.white, // White text

                  letterSpacing: -0.2,
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Dismiss Icon
          if (!isFriend && !isRequested)
            InkWell(
              onTap: () => _dismissSuggestion(userId),

              borderRadius: BorderRadius.circular(20),

              child: Icon(Icons.close, color: Colors.grey[700], size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[900]!,

      highlightColor: Colors.grey[800]!,

      child: ListView.builder(
        itemCount: 8,

        padding: const EdgeInsets.only(bottom: 20),

        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),

            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,

              children: [
                const CircleAvatar(
                  radius: 24, // Increased size

                  backgroundColor: Colors.black,
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,

                    mainAxisSize: MainAxisSize.min,

                    children: [
                      Container(
                        height: 16,

                        width: 140,

                        decoration: BoxDecoration(
                          color: Colors.black,

                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),

                      const SizedBox(height: 6),

                      Container(
                        height: 13,

                        width: 160,

                        decoration: BoxDecoration(
                          color: Colors.black,

                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                Container(
                  width: 60,

                  height: 30,

                  decoration: BoxDecoration(
                    color: Colors.black,

                    borderRadius: BorderRadius.circular(100),
                  ),
                ),

                const SizedBox(width: 8),

                Container(
                  width: 20,

                  height: 20,

                  decoration: const BoxDecoration(
                    color: Colors.black,

                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);

    _searchController.dispose();

    _debounceTimer?.cancel();

    super.dispose();
  }
}
