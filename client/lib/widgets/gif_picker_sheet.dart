import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/tenor_service.dart';

class GifPickerSheet extends StatefulWidget {
  final Function(TenorGif) onGifSelected;
  final String searchQuery; // New parameter

  const GifPickerSheet({
    super.key,
    required this.onGifSelected,
    this.searchQuery = '', // Default to empty
  });

  @override
  State<GifPickerSheet> createState() => _GifPickerSheetState();
}

class _GifPickerSheetState extends State<GifPickerSheet> {
  List<TenorGif> _gifs = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadGifs(widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant GifPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _loadGifs(widget.searchQuery);
    }
  }

  Future<void> _loadGifs(String query) async {
    setState(() => _isLoading = true);
    List<TenorGif> gifs;
    if (query.trim().isEmpty) {
      gifs = await TenorService.getTrendingGifs(limit: 30);
    } else {
      gifs = await TenorService.searchGifs(query, limit: 30);
    }

    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      widget.onGifSelected(gif);
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
    );
  }
}
