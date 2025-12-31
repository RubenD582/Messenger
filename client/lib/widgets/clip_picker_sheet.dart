import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:audioplayers/audioplayers.dart';

import '../services/klipy_service.dart';
import '../config/klipy_config.dart';

class ClipPickerSheet extends StatefulWidget {
  final Function(KlipyClip) onClipSelected;

  const ClipPickerSheet({
    super.key,
    required this.onClipSelected,
  });

  @override
  State<ClipPickerSheet> createState() => _ClipPickerSheetState();
}

class _ClipPickerSheetState extends State<ClipPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<KlipyClip> _clips = [];
  bool _isLoading = false;
  bool _isSearchFocused = false;
  Timer? _debounceTimer;

  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _playingIndex;
  bool _isMuted = true;

  @override
  void initState() {
    super.initState();
    _loadTrendingClips();
    _focusNode.addListener(() {
      setState(() {
        _isSearchFocused = _focusNode.hasFocus;
      });
    });
  }

  Future<void> _loadTrendingClips() async {
    setState(() => _isLoading = true);
    final clips = await KlipyService.getTrendingClips(limit: KlipyConfig.defaultLimit);
    if (mounted) {
      setState(() {
        _clips = clips;
        _isLoading = false;
      });
    }
  }

  Future<void> _searchClips(String query) async {
    if (query.trim().isEmpty) {
      _loadTrendingClips();
      return;
    }

    setState(() => _isLoading = true);
    final clips = await KlipyService.searchClips(query, limit: KlipyConfig.defaultLimit);
    if (mounted) {
      setState(() {
        _clips = clips;
        _isLoading = false;
      });
    }
  }

  /// Play only audio from clip
  Future<void> _playAudio(KlipyClip clip, int index) async {
    if (clip.videoUrl.isEmpty) return;

    if (_playingIndex == index) {
      // Already playing, do nothing
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(
      UrlSource(clip.videoUrl),
      volume: _isMuted ? 0 : 1,
    );

    setState(() {
      _playingIndex = index;
      _isMuted = true;
    });
  }

  void _toggleMute() {
    if (_playingIndex == null) return;

    _isMuted = !_isMuted;
    _audioPlayer.setVolume(_isMuted ? 0 : 1);
    setState(() {});
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
          _handleBar(),
          _searchBar(),
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
                      final isPlaying = _playingIndex == index;

                      return GestureDetector(
                        onTap: () {
                          widget.onClipSelected(clip);
                          Navigator.pop(context);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              clip.previewUrl.isNotEmpty
                                  ? Image.network(
                                      clip.previewUrl,
                                      fit: BoxFit.cover,
                                    )
                                  : _fallbackTile(),

                              // Mute/unmute button
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () {
                                    if (_playingIndex == index) {
                                      _toggleMute();
                                    } else {
                                      _playAudio(clip, index);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Icon(
                                      isPlaying
                                          ? (_isMuted ? Icons.volume_off : Icons.volume_up)
                                          : Icons.volume_off,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
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

  Widget _handleBar() => Container(
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _searchBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: CupertinoSearchTextField(
          controller: _searchController,
          focusNode: _focusNode,
          placeholder: "Search Clips...",
          style: const TextStyle(color: Colors.white),
          backgroundColor: Colors.grey.shade800,
          onChanged: (value) {
            _debounceTimer?.cancel();
            _debounceTimer = Timer(const Duration(milliseconds: 500), () => _searchClips(value));
          },
        ),
      );

  Widget _fallbackTile() => Container(
        color: Colors.grey.shade900,
        child: const Center(child: Icon(Icons.videocam, color: Colors.grey)),
      );

  @override
  void dispose() {
    _audioPlayer.dispose();
    _debounceTimer?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
