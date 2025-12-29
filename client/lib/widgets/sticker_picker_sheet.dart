import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/tenor_service.dart';

class StickerPickerSheet extends StatefulWidget {
  final Function(TenorSticker) onStickerSelected;

  const StickerPickerSheet({
    super.key,
    required this.onStickerSelected,
  });

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<TenorSticker> _stickers = [];
  bool _isLoading = false;
  String _currentQuery = '';
  bool _isSearchFocused = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadTrendingStickers();
    _focusNode.addListener(() {
      setState(() {
        _isSearchFocused = _focusNode.hasFocus;
      });
    });
  }

  Future<void> _loadTrendingStickers() async {
    setState(() => _isLoading = true);
    final stickers = await TenorService.getTrendingStickers(limit: 30);
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchStickers(String query) async {
    if (query.trim().isEmpty) {
      _loadTrendingStickers();
      return;
    }

    setState(() => _isLoading = true);
    final stickers = await TenorService.searchStickers(query, limit: 30);
    if (mounted) {
      setState(() {
        _stickers = stickers;
        _currentQuery = query;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: MediaQuery.of(context).size.height * (_isSearchFocused ? 0.95 : 0.7),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: CupertinoSearchTextField(
              controller: _searchController,
              focusNode: _focusNode,
              placeholder: "Search Stickers...",
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
                setState(() {});

                // Cancel previous timer
                _debounceTimer?.cancel();

                if (value.isEmpty) {
                  _loadTrendingStickers();
                } else {
                  // Start new timer - search after 500ms of no typing
                  _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                    _searchStickers(value);
                  });
                }
              },
              onSubmitted: _searchStickers,
            ),
          ),

          // Sticker Grid
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
                  )
                : _stickers.isEmpty
                    ? Center(
                        child: Text(
                          'No stickers found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _stickers.length,
                        itemBuilder: (context, index) {
                          final sticker = _stickers[index];
                          return GestureDetector(
                            onTap: () {
                              widget.onStickerSelected(sticker);
                              Navigator.pop(context);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(
                                    color: Colors.grey.shade800,
                                    child: Image.network(
                                      sticker.previewUrl,
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          color: Colors.grey.shade900,
                                          child: const Center(
                                            child: CupertinoActivityIndicator(
                                              color: Colors.white,
                                              radius: 10,
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.grey.shade900,
                                          child: const Icon(
                                            Icons.error_outline,
                                            color: Colors.grey,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  // Tap overlay effect
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        widget.onStickerSelected(sticker);
                                        Navigator.pop(context);
                                      },
                                      splashColor: Colors.white.withOpacity(0.2),
                                      highlightColor: Colors.white.withOpacity(0.1),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
