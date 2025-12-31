import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/klipy_service.dart';

class StickerPickerSheet extends StatefulWidget {
  final Function(KlipySticker) onStickerSelected;
  final String searchQuery; // New parameter

  const StickerPickerSheet({
    super.key,
    required this.onStickerSelected,
    this.searchQuery = '', // Default to empty
  });

  @override
  State<StickerPickerSheet> createState() => _StickerPickerSheetState();
}

class _StickerPickerSheetState extends State<StickerPickerSheet> {
  List<KlipySticker> _stickers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadStickers(widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant StickerPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _loadStickers(widget.searchQuery);
    }
  }

  Future<void> _loadStickers(String query) async {
    setState(() => _isLoading = true);
    List<KlipySticker> stickers;
    if (query.trim().isEmpty) {
      stickers = await KlipyService.getTrendingStickers(limit: 30);
    } else {
      stickers = await KlipyService.searchStickers(query, limit: 30);
    }

    if (mounted) {
      setState(() {
        _stickers = stickers;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
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
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.network(
                                  sticker.previewUrl,
                                  fit: BoxFit.contain,
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.transparent,
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
                                      color: Colors.transparent,
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
                                      widget.onStickerSelected(sticker);
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
