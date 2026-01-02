import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class EffectsPickerModal extends StatefulWidget {
  final Function(String effectType, Color color) onEffectSelected;

  const EffectsPickerModal({
    super.key,
    required this.onEffectSelected,
  });

  @override
  State<EffectsPickerModal> createState() => _EffectsPickerModalState();
}

class _EffectsPickerModalState extends State<EffectsPickerModal> {
  Color? _selectedColor;
  String? _selectedEffect; // 'gift' or 'love'
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Available gift colors
  static const List<Color> giftColors = [
    Color(0xFFFF69B4), // Pink
    Color(0xFF57DEDB), // Blue
    Color(0xFFFEB202), // Yellow
    Color(0xFFFE7100), // Orange
  ];

  // Available love colors (pink shades)
  static const List<Color> loveColors = [
    Color(0xFFFF69B4), // Hot pink
    Color(0xFFFFB6C1), // Light pink
    Color(0xFFFF1493), // Deep pink
    Color(0xFFFFC0CB), // Pink
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _showGiftSection {
    return _searchQuery.isEmpty ||
           'gift'.contains(_searchQuery.toLowerCase());
  }

  bool get _showLoveSection {
    return _searchQuery.isEmpty ||
           'love'.contains(_searchQuery.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _handleBar(),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: CupertinoSearchTextField(
              controller: _searchController,
              placeholder: 'Search for effects...',
              placeholderStyle: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w400,
              ),
              padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 12),
              backgroundColor: Colors.grey.shade800,
              itemColor: Colors.white,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: (_showGiftSection || _showLoveSection)
                ? SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Gift Section
                        if (_showGiftSection) ...[
                          // Section title
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Gift',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Horizontal scrollable gift color picker
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: giftColors.length,
                              itemBuilder: (context, index) {
                                final color = giftColors[index];
                                final isSelected = _selectedEffect == 'gift' && _selectedColor == color;

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedEffect = 'gift';
                                      _selectedColor = color;
                                    });
                                  },
                                child: Container(
                                  width: 75,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    children: [
                                      // Gift preview - EXACT same as actual gift message
                                      SizedBox(
                                        width: 75,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // The actual message bubble (base)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: color,
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: Text(
                                                'Gift',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),

                                            // Lid covering the message (EXACT same as actual)
                                            Positioned.fill(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: color,
                                                  borderRadius: BorderRadius.circular(18),
                                                  border: isSelected ? Border.all(
                                                    color: Colors.white,
                                                    width: 2,
                                                  ) : null,
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black.withValues(alpha: 0.3),
                                                      blurRadius: 6,
                                                      offset: const Offset(0, 3),
                                                    ),
                                                  ],
                                                ),
                                                child: Stack(
                                                  children: [
                                                    // Vertical ribbon
                                                    Positioned(
                                                      left: 0,
                                                      right: 0,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: Center(
                                                        child: Container(
                                                          width: 4,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                    // Horizontal ribbon
                                                    Positioned(
                                                      left: 0,
                                                      right: 0,
                                                      top: 0,
                                                      bottom: 0,
                                                      child: Center(
                                                        child: Container(
                                                          height: 4,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                    // Bow in the center
                                                    Center(
                                                      child: SvgPicture.asset(
                                                        'assets/bow.svg',
                                                        width: 16,
                                                        height: 16,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      // Selection indicator
                                      if (isSelected)
                                        Icon(
                                          CupertinoIcons.check_mark_circled_solid,
                                          color: Colors.white,
                                          size: 16,
                                        )
                                      else
                                        const SizedBox(height: 16),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        ],

                        // Love Section
                        if (_showLoveSection) ...[
                          const SizedBox(height: 24),

                          // Section title
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Love',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Horizontal scrollable love color picker
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: loveColors.length,
                              itemBuilder: (context, index) {
                                final color = loveColors[index];
                                final isSelected = _selectedEffect == 'love' && _selectedColor == color;

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedEffect = 'love';
                                      _selectedColor = color;
                                    });
                                  },
                                  child: Container(
                                    width: 75,
                                    margin: const EdgeInsets.only(right: 12),
                                    child: Column(
                                      children: [
                                        // Love preview with floating hearts
                                        SizedBox(
                                          width: 75,
                                          height: 50,
                                          child: Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              // Base message bubble
                                              Center(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 6,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF2C2C2E),
                                                    borderRadius: BorderRadius.circular(18),
                                                    border: isSelected ? Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ) : null,
                                                  ),
                                                  child: Text(
                                                    'Love',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              // Small hearts around
                                              _buildPreviewHeart(color, 8, -5, -5, 0.1),
                                              _buildPreviewHeart(color, 6, 55, -3, 0.3),
                                              _buildPreviewHeart(color, 7, 10, 35, -0.2),
                                              _buildPreviewHeart(color, 5, 60, 38, 0.4),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(height: 4),

                                        // Selection indicator
                                        if (isSelected)
                                          Icon(
                                            CupertinoIcons.check_mark_circled_solid,
                                            color: Colors.white,
                                            size: 16,
                                          )
                                        else
                                          const SizedBox(height: 16),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                : Center(
                    child: Text(
                      'No effects found',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ),
          ),

          // Send button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedColor == null || _selectedEffect == null
                    ? null
                    : () {
                        widget.onEffectSelected(_selectedEffect!, _selectedColor!);
                        Navigator.pop(context);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedColor == null
                      ? Colors.grey.shade800
                      : const Color(0xFF5856D6),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: Colors.grey.shade800,
                ),
                child: Text(
                  _selectedColor == null ? 'Select a color' : 'Continue',
                  style: TextStyle(
                    color: _selectedColor == null ? Colors.grey.shade600 : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _handleBar() {
    return Container(
      margin: const EdgeInsets.only(top: 12, bottom: 8),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // Helper to build preview hearts
  Widget _buildPreviewHeart(Color color, double size, double left, double top, double rotation) {
    return Positioned(
      left: left,
      top: top,
      child: Transform.rotate(
        angle: rotation,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.8),
                color.withValues(alpha: 0.3),
              ],
            ),
          ),
          child: Icon(
            CupertinoIcons.heart_fill,
            size: size,
            color: color,
          ),
        ),
      ),
    );
  }
}
