import 'dart:async';
import 'package:flutter/material.dart';
import 'package:client/models/status.dart';

class StatusViewerScreen extends StatefulWidget {
  final List<Status> statuses;

  const StatusViewerScreen({
    super.key,
    required this.statuses,
  });

  @override
  State<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends State<StatusViewerScreen> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoAdvanceTimer;
  Timer? _progressTimer;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startTimers();
  }

  void _startTimers() {
    // Progress animation timer (updates every 50ms for smooth animation)
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _progress += 0.01; // 5 seconds = 100 * 50ms
        if (_progress >= 1.0) {
          _nextStatus();
        }
      });
    });
  }

  void _stopTimers() {
    _autoAdvanceTimer?.cancel();
    _progressTimer?.cancel();
  }

  void _nextStatus() {
    _stopTimers();
    if (_currentIndex < widget.statuses.length - 1) {
      _currentIndex++;
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _progress = 0.0;
      _startTimers();
    } else {
      Navigator.pop(context);
    }
  }

  void _previousStatus() {
    _stopTimers();
    if (_currentIndex > 0) {
      _currentIndex--;
      _pageController.animateToPage(
        _currentIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      _progress = 0.0;
      _startTimers();
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
    _stopTimers();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
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
                                          ? _progress
                                          : 0.0,
                                  backgroundColor: Colors.white.withValues(alpha: 0.3),
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
                              color: Colors.white.withValues(alpha: 0.2),
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
    );
  }
}
