import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:client/models/status.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/cupertino.dart';

class StatusViewerScreen extends StatefulWidget {
  final List<Status> statuses;

  const StatusViewerScreen({
    super.key,
    required this.statuses,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  int _currentIndex = 0;
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode(); // Add FocusNode

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addListener(() {
        setState(() {});
      })..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStatus();
        }
      });

    _startStatus();

    // Add listener to focus node
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _animationController.stop(); // Pause animation when text field is active
      } else {
        if (_animationController.status != AnimationStatus.completed) {
          _animationController.forward(); // Resume animation when text field loses focus
        }
      }
    });
  }

  void _startStatus() {
    _animationController.stop();
    _animationController.reset();
    _animationController.forward();
  }

  void _nextStatus() {
    if (_currentIndex < widget.statuses.length - 1) {
      _currentIndex++;
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _startStatus();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStatus() {
    if (_currentIndex > 0) {
      _currentIndex--;
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _startStatus();
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final statusDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final timeString = '$hour:$minute';

    if (statusDate == today) {
      return 'Today at $timeString';
    } else {
      return 'Yesterday at $timeString';
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
    _replyFocusNode.dispose(); // Dispose FocusNode
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTapUp: (details) {
              final screenWidth = MediaQuery.of(context).size.width;
              if (details.globalPosition.dx < screenWidth / 3) {
                _previousStatus();
              } else if (details.globalPosition.dx > screenWidth * 2 / 3) {
                _nextStatus();
              }
            },
            child: Stack(
              children: [
                // PageView for statuses
                PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.statuses.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final status = widget.statuses[index];
                    final colorHex = status.backgroundColor.replaceFirst('#', '');
                    final color = Color(int.parse('FF$colorHex', radix: 16));

                    return Container(
                      color: color,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            status.textContent,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Top bar with progress indicators
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Column(
                      children: [
                        // Progress bars
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                          child: Row(
                            children: List.generate(widget.statuses.length, (index) {
                              return Expanded(
                                child: Container(
                                  height: 3,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: index < _currentIndex
                                          ? 1.0
                                          : index == _currentIndex
                                              ? _animationController.value
                                              : 0.0,
                                      backgroundColor: Colors.white.withOpacity(0.3),
                                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),

                        // User info and close button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 20,
                                backgroundImage: AssetImage('assets/noprofile.png'),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.statuses[_currentIndex].userName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      _formatTime(widget.statuses[_currentIndex].createdAt),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: IconButton(
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 8.0, // Adjusted padding
            left: 8, // Adjusted padding
            right: 8, // Adjusted padding
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25.0),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      padding: const EdgeInsets.only(left: 12.0, right: 0.0), // Adjusted horizontal padding
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoTextField(
                              controller: _replyController,
                              focusNode: _replyFocusNode, // Assign FocusNode
                              placeholder: 'Reply...',
                              placeholderStyle: TextStyle(color: Colors.white.withOpacity(0.6)),
                              style: const TextStyle(color: Colors.white),
                              decoration: const BoxDecoration(),
                              padding: const EdgeInsets.symmetric(vertical: 13.0), // Removed horizontal padding from here
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              // TODO: Implement send reply functionality
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Container(
                                width: 35, // Adjust size as needed
                                height: 35, // Adjust size as needed
                                decoration: BoxDecoration(
                                  color: Color(int.parse('FF${widget.statuses[_currentIndex].backgroundColor.replaceFirst('#', '')}', radix: 16)).withOpacity(0.8), // Dynamic background color
                                  borderRadius: BorderRadius.circular(20.0), // Rounded container
                                ),
                                // Removed explicit padding from here, relying on Center
                                child: Center(
                                  child: SvgPicture.asset(
                                    'assets/send.svg',
                                    width: 14, // Smaller SVG
                                    height: 14, // Smaller SVG
                                    colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                                  ),
                                ),
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
          ),
        ],
      ),
    );
  }
}
