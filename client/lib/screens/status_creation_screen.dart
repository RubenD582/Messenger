import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:client/services/api_service.dart';

class StatusCreationScreen extends StatefulWidget {
  final ApiService apiService;

  const StatusCreationScreen({
    super.key,
    required this.apiService,
  });

  @override
  State<StatusCreationScreen> createState() => _StatusCreationScreenState();
}

class _StatusCreationScreenState extends State<StatusCreationScreen> {
  final TextEditingController _textController = TextEditingController();
  int _currentColorIndex = 0;
  bool _isPublishing = false;

  // Hardcoded background colors (like WhatsApp)
  static const List<Color> _backgroundColors = [
    Color(0xFF5856D6), // Purple
    Color(0xFF007AFF), // Blue
    Color(0xFF34C759), // Green
    Color(0xFFFF3B30), // Red
    Color(0xFFFF9500), // Orange
    Color(0xFF00C7BE), // Teal
    Color(0xFFFF2D55), // Pink
    Color(0xFF1C1C1E), // Dark gray
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColors[_currentColorIndex],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 8.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              // Hide keyboard when tapping on background
              FocusScope.of(context).unfocus();
            },
            onHorizontalDragEnd: (details) {
              // Swipe left/right to change color
              if (details.primaryVelocity! < 0) {
                // Swipe left
                _nextColor();
              } else if (details.primaryVelocity! > 0) {
                // Swipe right
                _previousColor();
              }
            },
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -40), // Move up to compensate for AppBar
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: TextField(
                    controller: _textController,
                    textAlign: TextAlign.center,
                    cursorColor: Colors.white,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Type a status',
                      hintStyle: TextStyle(
                        color: Colors.white60,
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    maxLines: null,
                    autofocus: true,
                    enabled: !_isPublishing,
                  ),
                ),
              ),
            ),
          ),
          // Send button at bottom right
          Positioned(
            bottom: 32,
            right: 32,
            child: _isPublishing
                ? const SizedBox(
                    width: 52,
                    height: 52,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: const EdgeInsets.only(top: 3),
                      icon: SvgPicture.asset(
                        'assets/send.svg',
                        width: 14,
                        height: 14,
                        colorFilter: const ColorFilter.mode(
                          Colors.white,
                          BlendMode.srcIn,
                        ),
                      ),
                      onPressed: _isPublishing ? null : _publishStatus,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _nextColor() {
    if (_isPublishing) return;
    setState(() {
      _currentColorIndex = (_currentColorIndex + 1) % _backgroundColors.length;
    });
  }

  void _previousColor() {
    if (_isPublishing) return;
    setState(() {
      _currentColorIndex = (_currentColorIndex - 1) % _backgroundColors.length;
      if (_currentColorIndex < 0) {
        _currentColorIndex = _backgroundColors.length - 1;
      }
    });
  }

  Future<void> _publishStatus() async {
    // Prevent double-submission
    if (_isPublishing) return;

    final text = _textController.text.trim();

    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isPublishing = true;
    });

    try {
      final color = _backgroundColors[_currentColorIndex];
      // Convert Color to hex string (RRGGBB format)
      final r = (color.r * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final g = (color.g * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final b = (color.b * 255.0).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
      final colorHex = '#$r$g$b';

      await widget.apiService.createStatus(text, colorHex);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPublishing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
}
