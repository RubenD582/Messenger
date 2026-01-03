
import 'dart:async';
import 'dart:convert';
import 'package:client/services/api_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/services/location_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  _SearchPageState createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with TickerProviderStateMixin {
  late final ApiService _apiService;
  final LocationService _locationService = LocationService();

  String? _currentUserId;

  bool _isLoadingSuggestions = false;
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _filteredSuggestions = [];

  Set<String> _sentRequests = {};
  bool _locationChecked = false;

  // Search state
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late AnimationController _searchAnimationController;

  Timer? _debounceTimer;
  List<Map<String, dynamic>> _recentSearches = [];
  static const String _recentSearchesKey = 'recent_searches';

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();

    _searchAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _searchController.addListener(_onSearchChanged);
    _loadRecentSearches();
    _loadCurrentUserAndInit();
  }

  void _onSearchChanged() {
    // Cancel previous timer
    _debounceTimer?.cancel();

    // Start new timer - only search after 750ms of no typing
    _debounceTimer = Timer(const Duration(milliseconds: 750), () async {
      if (mounted) {
        final query = _searchController.text.trim();
        if (query.isEmpty) {
          setState(() {
            _filteredSuggestions = _suggestions;
          });
        } else {
          // Call API to search all users
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
      }
    });
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? recentJson = prefs.getString(_recentSearchesKey);
      if (recentJson != null) {
        final List<dynamic> decoded = json.decode(recentJson);
        setState(() {
          _recentSearches = decoded.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading recent searches: $e');
      }
    }
  }

  Future<void> _saveRecentSearch(Map<String, dynamic> user) async {
    try {
      // Remove if already exists
      _recentSearches.removeWhere((u) => u['userId'] == user['userId']);

      // Create a clean copy with only necessary fields
      final recentUser = {
        'userId': user['userId'],
        'name': user['name'],
        'username': user['username'],
        'profile_picture': user['profile_picture'],
      };

      // Add to front
      _recentSearches.insert(0, recentUser);

      // Keep only last 10
      if (_recentSearches.length > 10) {
        _recentSearches = _recentSearches.sublist(0, 10);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentSearchesKey, json.encode(_recentSearches));

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving recent search: $e');
      }
    }
  }

  Future<void> _removeRecentSearch(String userId) async {
    try {
      _recentSearches.removeWhere((u) => u['userId'] == userId);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_recentSearchesKey, json.encode(_recentSearches));

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error removing recent search: $e');
      }
    }
  }

  Future<void> _clearAllRecentSearches() async {
    try {
      _recentSearches.clear();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_recentSearchesKey);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error clearing recent searches: $e');
      }
    }
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (_isSearching) {
        _searchAnimationController.forward();
        _searchFocusNode.requestFocus();
      } else {
        _searchAnimationController.reverse();
        _searchFocusNode.unfocus(); // Good practice to unfocus
        _searchController.clear();
        _filteredSuggestions = _suggestions;
        _debounceTimer?.cancel();
      }
    });
  }

  Future<void> _loadCurrentUserAndInit() async {
    final userId = await AuthService.getUserUuid();
    if (mounted) {
      setState(() {
        _currentUserId = userId;
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
        // Refresh suggestions with new location data
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
      final suggestions = await _apiService.getFriendSuggestions(_currentUserId!);
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
      // Optionally show a toast or error message
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

    // Immediately update UI for responsiveness
    setState(() {
      _sentRequests.add(friendId);
    });

    try {
      final result = await _apiService.sendFriendRequest(friendId, _currentUserId!);

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

        // If auto-accepted, remove from suggestions
        if (result['autoAccepted'] == true) {
          setState(() {
            _suggestions.removeWhere((user) => user['userId'] == friendId);
          });
        }
      } else {
        // Request failed, remove from sent requests to allow retry
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

      // Rollback on error
      setState(() {
        _sentRequests.remove(friendId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error. Please try again.'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildMainContent() {
    return Column(
      key: const ValueKey('suggestions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const Text(
          'Find friends',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 20),
        // --- Suggestions List ---
        Expanded(
          child: _isLoadingSuggestions
              ? _buildSuggestionsShimmer()
              : _suggestions.isEmpty
                  ? Center(
                      child: Text(
                        'No suggestions available',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _suggestions.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemBuilder: (context, index) {
                        final user = _suggestions[index];
                        return _buildSuggestionRow(user);
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        leadingWidth: _isSearching ? 40 : null,
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                onPressed: _toggleSearch,
              )
            : null,
        title: Align(
          alignment: Alignment.centerLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeInOut,
            switchOutCurve: Curves.easeInOut,
            transitionBuilder: (Widget child, Animation<double> animation) {
              final offsetAnimation = Tween<Offset>(
                begin: const Offset(0.1, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));

              return SlideTransition(
                position: offsetAnimation,
                child: FadeTransition(
                  opacity: animation,
                  child: child,
                ),
              );
            },
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.centerLeft,
                children: <Widget>[
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: _isSearching
                ? Row(
                    key: const ValueKey('search-field'),
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            _searchFocusNode.requestFocus();
                          },
                          child: CupertinoSearchTextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: true,
                            placeholder: 'Search',
                            onSuffixTap: () {
                              _searchController.clear();
                              setState(() {
                                _filteredSuggestions = _suggestions;
                              });
                            },
                            placeholderStyle: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                            ),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w400,
                            ),
                            backgroundColor: Colors.grey[900],
                            itemColor: Colors.white,
                            prefixIcon: const SizedBox.shrink(),
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                          ),
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Discover',
                    key: ValueKey('discover-title'),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
        actions: _isSearching
            ? null
            : [
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: _toggleSearch,
                ),
              ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withAlpha(20),
                  width: 1,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14.0),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (Widget child, Animation<double> animation) {
            final offsetAnimation = Tween<Offset>(
              begin: const Offset(0.0, 0.015),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ));

            return SlideTransition(
              position: offsetAnimation,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: _isSearching
              ? _buildSearchContent()
              : _buildMainContent(),
        ),
      ),
    );
  }

  Widget _buildSuggestionRow(Map<String, dynamic> user, {bool isRecent = false}) {
    final profilePicture = user['profile_picture'] ?? 'assets/noprofile.png';
    final name = user['name'] ?? 'Unknown User';
    final username = user['username'];
    final userId = user['userId'] as String;
    final friendStatus = user['friendStatus'] ?? 'none';
    final isRequested = _sentRequests.contains(userId) || friendStatus == 'pending';
    final isFriend = friendStatus == 'friend';
    final score = (user['score'] ?? 0) as num;

    // Determine suggestion reason based on score
    String suggestionReason;
    if (isRecent) {
      suggestionReason = 'Recent search';
    } else if (isFriend) {
      suggestionReason = 'Added';
    } else if (friendStatus == 'pending') {
      suggestionReason = 'Request pending';
    } else if (score >= 100) {
      suggestionReason = 'Suggested based on location';
    } else if (score >= 50) {
      suggestionReason = 'Suggested based on mutual';
    } else {
      suggestionReason = 'Suggested for you';
    }

    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.grey.withAlpha(50),
      onTap: () {
        // Save to recent searches when tapped
        if (!isRecent) {
          _saveRecentSearch(user);
        }
        // You can add navigation to user profile here
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          // Profile Picture
          CircleAvatar(
            radius: 18,
            backgroundColor: Colors.grey[800],
            backgroundImage: (profilePicture != null && profilePicture.startsWith('http'))
                ? NetworkImage(profilePicture)
                : AssetImage(profilePicture ?? 'assets/noprofile.png') as ImageProvider,
          ),
          const SizedBox(width: 14),
          // Name and Subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  username != null && username.isNotEmpty
                      ? '$username'
                      : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (!isRecent) ...[
                  Text(
                    suggestionReason,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Add Button or Remove Icon
          if (isRecent)
            GestureDetector(
              onTap: () => _removeRecentSearch(userId),
              child: Icon(
                Icons.close,
                color: Colors.grey[600],
                size: 20,
              ),
            )
          else
            SizedBox(
              width: 68,
              height: 30,
              child: ElevatedButton(
                onPressed: (isRequested || isFriend) ? null : () => _sendFriendRequest(userId),
                style: ElevatedButton.styleFrom(
                  splashFactory: NoSplash.splashFactory,
                  backgroundColor: (isRequested || isFriend) ? const Color(0xFF2C2C2E) : const Color(0xFF5856D6),
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
                    color: (isRequested || isFriend) ? Colors.grey[600] : Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    return Column(
      key: const ValueKey('search'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        // Show recent searches when query is empty
        if (_searchController.text.isEmpty && _recentSearches.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
              GestureDetector(
                onTap: _clearAllRecentSearches,
                child: const Text(
                  'Clear all',
                  style: TextStyle(
                    color: Color(0xFF5856D6),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        Expanded(
          child: _searchController.text.isEmpty
              ? (ListView.builder(
                      itemCount: _recentSearches.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemBuilder: (context, index) {
                        final user = _recentSearches[index];
                        return _buildSuggestionRow(user, isRecent: true);
                      },
                    ))
              : (_filteredSuggestions.isEmpty
                  ? Center(
                      child: Text(
                        'No results found',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredSuggestions.length,
                      padding: const EdgeInsets.only(bottom: 20),
                      itemBuilder: (context, index) {
                        final user = _filteredSuggestions[index];
                        return _buildSuggestionRow(user);
                      },
                    )),
        ),
      ],
    );
  }

  Widget _buildSuggestionsShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[800]!,
      highlightColor: Colors.grey[700]!,
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
                  radius: 22,
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
                  width: 68,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(100),
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
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchAnimationController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
}