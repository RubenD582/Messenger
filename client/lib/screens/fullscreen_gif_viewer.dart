import 'dart:ui'; // Import for ImageFilter

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class FullscreenGifViewer extends StatelessWidget {
  final String gifUrl;
  final Object heroTag;

  const FullscreenGifViewer({
    super.key,
    required this.gifUrl,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(), // Close on any tap
      child: Stack(
        children: [
          // Blurry background
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: Container(
              color: Colors.black.withOpacity(0.2), // Lighter overlay for more transparency
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent, // Make Scaffold transparent to show blur
            appBar: AppBar(
              backgroundColor: Colors.transparent, // Transparent AppBar
              automaticallyImplyLeading: false, // Ensure no back button
              elevation: 0,
              toolbarHeight: 0, // Hide app bar completely
            ),
            body: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.8,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5), // More transparent content background
                  borderRadius: BorderRadius.circular(16.0),
                ),
                clipBehavior: Clip.antiAlias,
                child: Hero(
                  tag: heroTag,
                  child: InteractiveViewer(
                    panEnabled: true,
                    minScale: 0.5,
                    maxScale: 4.0,
                    child: CachedNetworkImage(
                      imageUrl: gifUrl,
                      placeholder: (context, url) => const Center(
                        child: CupertinoActivityIndicator(
                          radius: 14.0,
                          color: Colors.white,
                        ),
                      ),
                      errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
