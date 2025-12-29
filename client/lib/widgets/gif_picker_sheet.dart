import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/tenor_service.dart';

class GifPickerSheet extends StatefulWidget {
  final Function(TenorGif) onGifSelected;

  const GifPickerSheet({
    super.key,
    required this.onGifSelected,
  });

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<TenorGif> _gifs = [];
  bool _isLoading = false;
  String _currentQuery = '';
  bool _isSearchFocused = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadTrendingGifs();
    _focusNode.addListener(() {
      setState(() {
        _isSearchFocused = _focusNode.hasFocus;
      });
    });
  }

  Future<void> _loadTrendingGifs() async {
    setState(() => _isLoading = true);
    final gifs = await TenorService.getTrendingGifs(limit: 30);
    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchGifs(String query) async {
    if (query.trim().isEmpty) {
      _loadTrendingGifs();
      return;
    }

    setState(() => _isLoading = true);
    final gifs = await TenorService.searchGifs(query, limit: 30);
    if (mounted) {
      setState(() {
        _gifs = gifs;
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
              placeholder: "Search GIFs...",
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
                  _loadTrendingGifs();
                } else {
                  // Start new timer - search after 1 second of no typing
                  _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                    _searchGifs(value);
                  });
                }
              },
              onSubmitted: _searchGifs,
            ),
          ),

          // GIF Grid
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
                  )
                : _gifs.isEmpty
                    ? Center(
                        child: Text(
                          'No GIFs found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: _gifs.length,
                        itemBuilder: (context, index) {
                          final gif = _gifs[index];
                          return GestureDetector(
                            onTap: () {
                              widget.onGifSelected(gif);
                              Navigator.pop(context);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.network(
                                    gif.previewUrl,
                                    fit: BoxFit.cover,
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
                                  // Hover overlay effect
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        widget.onGifSelected(gif);
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

          // NOTE: Tenor's terms may require attribution
          // Uncomment if needed:
          // Padding(
          //   padding: const EdgeInsets.all(12),
          //   child: Text(
          //     'Powered by Tenor',
          //     style: TextStyle(
          //       color: Colors.grey.shade700,
          //       fontSize: 11,
          //     ),
          //   ),
          // ),
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
