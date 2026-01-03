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

  // Available love gradient combinations - same color getting darker
  static const List<Map<String, dynamic>> loveGradients = [
    {
      'start': Color(0xFFFF69B4), // Hot Pink
      'end': Color(0xFFFF1493),   // Deep Pink (lighter)
      'id': 0xFF000001,
    },
    {
      'start': Color(0xFFDA70D6), // Orchid
      'end': Color(0xFFBA55D3),   // Medium Orchid (lighter)
      'id': 0xFF000002,
    },
    {
      'start': Color(0xFF57DEDB), // Turquoise
      'end': Color(0xFF20B2AA),   // Light Sea Green (lighter)
      'id': 0xFF000003,
    },
    {
      'start': Color(0xFFFEB202), // Yellow
      'end': Color(0xFFFFA500),   // Orange (lighter)
      'id': 0xFF000004,
    },
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
                                  width: 90,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: Column(
                                    children: [
                                      // Gift preview - EXACT same as actual gift message
                                      SizedBox(
                                        width: 90,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // The actual message bubble (base)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                color: color,
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: Text(
                                                'Gift',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
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

                          // Horizontal scrollable love gradient picker
                          SizedBox(
                            height: 80,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: loveGradients.length,
                              itemBuilder: (context, index) {
                                final gradient = loveGradients[index];
                                final gradientId = Color(gradient['id'] as int);
                                final isSelected = _selectedEffect == 'love' && _selectedColor == gradientId;

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedEffect = 'love';
                                      _selectedColor = gradientId;
                                    });
                                  },
                                  child: Container(
                                    width: 90,
                                    margin: const EdgeInsets.only(right: 24, top: 5),
                                    child: Column(
                                      children: [
                                        // Love preview with floating hearts - EXACT same as chat
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            // Base message bubble
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              constraints: BoxConstraints(
                                                minWidth: 70,
                                              ),
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    (gradient['start'] as Color).withValues(alpha: 0.85),
                                                    (gradient['end'] as Color).withValues(alpha: 0.85),
                                                  ],
                                                  begin: Alignment.topCenter,
                                                  end: Alignment.bottomCenter,
                                                ),
                                                borderRadius: BorderRadius.circular(18),
                                              ),
                                              child: Text(
                                                'Love',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  height: 1.4,
                                                ),
                                              ),
                                            ),
                                            // Selection border overlay (doesn't affect height)
                                            if (isSelected)
                                              Positioned.fill(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(18),
                                                    border: Border.all(
                                                      color: Colors.white,
                                                      width: 2,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            // Hearts with EXACT same positioning as chat
                                            _buildPreviewHeart(gradient, 18, -8, -6, null, null, 0.1),
                                            _buildPreviewHeart(gradient, 22, -10, null, null, -8, -0.2),
                                            _buildPreviewHeart(gradient, 14, null, -4, 0, null, 0.3),
                                            _buildPreviewHeart(gradient, 12, null, null, -8, -6, 0.15),
                                            _buildPreviewHeart(gradient, 15, -6, 12, null, null, -0.25),
                                          ],
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

  // Helper to build preview hearts - EXACT same as chat
  Widget _buildPreviewHeart(
    Map<String, dynamic> gradient,
    double size,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double rotation,
  ) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: Transform.rotate(
        angle: rotation,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [gradient['start'] as Color, gradient['end'] as Color],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds);
          },
          child: Icon(
            CupertinoIcons.heart_fill,
            size: size,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
