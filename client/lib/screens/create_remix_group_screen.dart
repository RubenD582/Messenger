// create_remix_group_screen.dart - Bottom modal for creating remix groups
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:client/services/remix_service.dart';
import 'package:client/services/auth_service.dart';
import 'package:client/config/api_config.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class CreateRemixGroupScreen extends StatefulWidget {
  const CreateRemixGroupScreen({super.key});

  @override
  State<CreateRemixGroupScreen> createState() => _CreateRemixGroupScreenState();
}

class _CreateRemixGroupScreenState extends State<CreateRemixGroupScreen> {
  final RemixService _remixService = RemixService();

  List<Map<String, dynamic>> _friends = [];
  final Set<String> _selectedFriendIds = {};
  bool _isLoading = true;
  bool _isCreating = false;
  final TextEditingController _groupNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() => _isLoading = true);

    try {
      final token = await AuthService.getToken();
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/friends/list?status=accepted'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _friends = List<Map<String, dynamic>>.from(data['friends'] ?? []);
          _isLoading = false;
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _friends = [];
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load friends: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading friends: $e');
      }
      setState(() => _isLoading = false);
    }
  }

  void _toggleFriend(String friendId) {
    setState(() {
      if (_selectedFriendIds.contains(friendId)) {
        _selectedFriendIds.remove(friendId);
      } else {
        if (_selectedFriendIds.length < 4) {
          _selectedFriendIds.add(friendId);
        } else {
          // Show error - max 5 members including yourself
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Maximum 5 members per group (including you)'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    });
  }

  Future<void> _createGroup() async {
    if (_selectedFriendIds.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least 2 friends'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final groupName = _groupNameController.text.trim().isEmpty
          ? 'My Remix Group'
          : _groupNameController.text.trim();

      await _remixService.createGroup(
        name: groupName,
        memberIds: _selectedFriendIds.toList(),
      );

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Group created! Start remixing'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[700],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create Remix Group',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select 2-4 friends to start remixing',
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),

                // Group name input
                TextField(
                  controller: _groupNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Group name (optional)',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: Colors.grey[900],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Selected count
          if (_selectedFriendIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.checkmark_circle_fill,
                      color: Colors.blue,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedFriendIds.length + 1}/5 members selected',
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Friends grid
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : _friends.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.person_2,
                              size: 64,
                              color: Colors.grey[700],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No friends yet',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                          childAspectRatio: 0.75,
                        ),
                        itemCount: _friends.length,
                        itemBuilder: (context, index) {
                          final friend = _friends[index];
                          final friendId = friend['friend_id'] ?? friend['id'];
                          final isSelected = _selectedFriendIds.contains(friendId);
                          final firstName = friend['first_name'] ?? '';
                          final lastName = friend['last_name'] ?? '';
                          final username = friend['username'] ?? '';

                          return GestureDetector(
                            onTap: () => _toggleFriend(friendId),
                            child: Column(
                              children: [
                                // Profile picture with selection indicator
                                Stack(
                                  children: [
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.blue
                                              : Colors.transparent,
                                          width: 3,
                                        ),
                                      ),
                                      child: CircleAvatar(
                                        radius: 38,
                                        backgroundColor: Colors.grey[800],
                                        child: Text(
                                          firstName.isNotEmpty
                                              ? firstName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Checkmark indicator
                                    if (isSelected)
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: Colors.blue,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.black,
                                              width: 2,
                                            ),
                                          ),
                                          child: const Icon(
                                            CupertinoIcons.check_mark,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Name/username
                                Text(
                                  firstName.isNotEmpty
                                      ? '$firstName ${lastName}'.trim()
                                      : username,
                                  style: TextStyle(
                                    color: isSelected ? Colors.blue : Colors.white,
                                    fontSize: 12,
                                    fontWeight:
                                        isSelected ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),

          // Create button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCreating || _selectedFriendIds.length < 2
                      ? null
                      : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.grey[800],
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _selectedFriendIds.isEmpty
                              ? 'Select friends to create'
                              : 'Create Group (${_selectedFriendIds.length + 1} members)',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
