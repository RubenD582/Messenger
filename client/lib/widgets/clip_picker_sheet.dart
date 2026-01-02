import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../services/klipy_service.dart';
import '../config/klipy_config.dart';

class ClipPickerSheet extends StatefulWidget {
  final Function(KlipyClip) onClipSelected;
  final String searchQuery; // New parameter

  const ClipPickerSheet({
    super.key,
    required this.onClipSelected,
    this.searchQuery = '', // Default to empty
  });

  @override
  State<ClipPickerSheet> createState() => _ClipPickerSheetState();
}

class _ClipPickerSheetState extends State<ClipPickerSheet> {
  List<KlipyClip> _clips = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadClips(widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant ClipPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchQuery != widget.searchQuery) {
      _loadClips(widget.searchQuery);
    }
  }

  Future<void> _loadClips(String query) async {
    setState(() => _isLoading = true);
    List<KlipyClip> clips;
    if (query.trim().isEmpty) {
      clips = await KlipyService.getTrendingClips(limit: KlipyConfig.defaultLimit);
    } else {
      clips = await KlipyService.searchClips(query, limit: KlipyConfig.defaultLimit);
    }

    if (mounted) {
      setState(() {
        _clips = clips;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
                )
              : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _clips.length,
                    itemBuilder: (context, index) {
                      final clip = _clips[index];

                      return GestureDetector(
                        onTap: () {
                          widget.onClipSelected(clip);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: clip.previewUrl.isNotEmpty
                              ? Image.network(
                                  clip.previewUrl,
                                  fit: BoxFit.cover,
                                )
                              : _fallbackTile(),
                        ),
                      );
                    },
                  ),
          ),
      ],
    );
  }

  Widget _fallbackTile() => Container(
        color: Colors.grey.shade900,
        child: const Center(child: Icon(Icons.videocam, color: Colors.grey)),
      );
}
