import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:client/widgets/gif_picker_sheet.dart';
import 'package:client/widgets/sticker_picker_sheet.dart';
import 'package:client/widgets/clip_picker_sheet.dart';

import 'package:client/services/tenor_service.dart'; // For TenorGif
import 'package:client/services/klipy_service.dart'; // For KlipySticker, KlipyClip

enum MediaType { gif, sticker, clip, drawing }

class MediaPickerModal extends StatefulWidget {
  final Function(TenorGif) onGifSelected;
  final Function(KlipySticker) onStickerSelected;
  final Function(KlipyClip) onClipSelected;
  final VoidCallback? onDrawingSelected;

  const MediaPickerModal({
    super.key,
    required this.onGifSelected,
    required this.onStickerSelected,
    required this.onClipSelected,
    this.onDrawingSelected,
  });

  @override
  State<MediaPickerModal> createState() => _MediaPickerModalState();
}

class _MediaPickerModalState extends State<MediaPickerModal> {
  MediaType _selectedMediaType = MediaType.gif;
  final PageController _pageController = PageController();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String _currentSearchQuery = '';
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        // Trigger rebuild to adjust modal height based on keyboard visibility
      });
    });
  }

  // Helper to determine modal height based on keyboard and search focus
  double get _modalHeight {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    // If keyboard is up, make it full screen-ish
    if (keyboardHeight > 0) {
      return screenHeight * 0.95;
    }
    // If search is focused but keyboard isn't up (e.g., external keyboard)
    if (_focusNode.hasFocus) {
      return screenHeight * 0.95;
    }
    // Default height
    return screenHeight * 0.75;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: _modalHeight,
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
              focusNode: _focusNode,
              placeholder: _getPlaceholderText(),
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
                // Cancel previous timer
                _debounceTimer?.cancel();

                // Start new timer - update search query after 500ms of no typing
                _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    setState(() {
                      _currentSearchQuery = value;
                    });
                  }
                });
              },
              onSubmitted: (value) {
                if (mounted) {
                  setState(() {
                    _currentSearchQuery = value;
                  });
                }
              },
            ),
          ),

          const SizedBox(height: 4,),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<MediaType>(
                backgroundColor: Colors.grey.shade800,
                thumbColor: CupertinoColors.systemGrey,
                groupValue: _selectedMediaType,
                onValueChanged: (MediaType? value) {
                  if (value != null) {
                    setState(() {
                      _selectedMediaType = value;
                      _pageController.jumpToPage(value.index);
                    });
                  }
                },
                children: const <MediaType, Widget>{
                  MediaType.gif: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'GIFs',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  MediaType.sticker: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Stickers',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  MediaType.clip: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Clips',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  MediaType.drawing: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Draw',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                },
              ),
            ),
          ),

          const SizedBox(height: 8,),

          // PageView for content
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _selectedMediaType = MediaType.values[index];
                });
              },
              children: [
                GifPickerSheet(
                  onGifSelected: widget.onGifSelected,
                  searchQuery: _currentSearchQuery,
                ),
                StickerPickerSheet(
                  onStickerSelected: widget.onStickerSelected,
                  searchQuery: _currentSearchQuery,
                ),
                ClipPickerSheet(
                  onClipSelected: widget.onClipSelected,
                  searchQuery: _currentSearchQuery,
                ),
                _buildDrawingTab(),
              ],
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

  Widget _buildDrawingTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.paintbrush_fill,
            size: 80,
            color: Colors.grey[700],
          ),
          const SizedBox(height: 24),
          Text(
            'Start Drawing',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tap the button below to start drawing',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDrawingSelected?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5856D6),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Start Drawing',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getPlaceholderText() {
    switch (_selectedMediaType) {
      case MediaType.gif:
        return 'Search GIFs...';
      case MediaType.sticker:
        return 'Search Stickers...';
      case MediaType.clip:
        return 'Search for Clips...';
      case MediaType.drawing:
        return 'Drawing mode';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
}
