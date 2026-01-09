// remix_editor_screen.dart - BeReal-style remix editor
import 'dart:io';
import 'dart:typed_data';
import 'package:client/models/remix_editor_result.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:matrix_gesture_detector/matrix_gesture_detector.dart';
import 'package:vector_math/vector_math_64.dart' as vector_math;
import 'dart:math' as math;

class RemixEditorScreen extends StatefulWidget {
  final Uint8List baseImageBytes;
  final String postId;

  const RemixEditorScreen({
    super.key,
    required this.baseImageBytes,
    required this.postId,
  });

  @override
  State<RemixEditorScreen> createState() => _RemixEditorScreenState();
}

class _RemixEditorScreenState extends State<RemixEditorScreen> with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _baseImageKey = GlobalKey();

  ValueNotifier<Matrix4> matrixNotifier = ValueNotifier(Matrix4.identity());

  Matrix4 _translationMatrix = Matrix4.identity();
  Matrix4 _scaleMatrix = Matrix4.identity();
  Matrix4 _rotationMatrix = Matrix4.identity();

  File? _overlayImageFile;
  Uint8List? _overlayImageBytes;
  bool _isProcessing = false;
  bool _showInstructions = true;

  late AnimationController _instructionsController;
  late Animation<double> _instructionsFade;

  @override
  void initState() {
    super.initState();
    _instructionsController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _instructionsFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _instructionsController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (photo == null) return;

    final bytes = await photo.readAsBytes();
    setState(() {
      _overlayImageFile = File(photo.path);
      _overlayImageBytes = bytes;

      // Hide instructions after picking image
      if (_showInstructions) {
        _instructionsController.forward().then((_) {
          setState(() => _showInstructions = false);
        });
      }
    });
  }

  Future<void> _onComplete() async {
    if (_overlayImageBytes == null) {
      _showCupertinoAlert(
        'No Image Selected',
        'Please select an image to add to your remix.',
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Get gesture transformations
      final translationDelta = _translationMatrix.getTranslation();
      final scaleComponents = vector_math.Vector3.zero();
      _scaleMatrix.decompose(vector_math.Vector3.zero(), vector_math.Quaternion.identity(), scaleComponents);
      final gestureScale = scaleComponents.x;
      final rotation = vector_math.Quaternion.identity();
      _rotationMatrix.decompose(vector_math.Vector3.zero(), rotation, vector_math.Vector3.zero());
      final rotationAngleDegrees = (2 * math.atan2(rotation.z, rotation.w)) * (180 / math.pi);

      // Get image geometries
      final RenderBox? baseImageRenderBox =
          _baseImageKey.currentContext?.findRenderObject() as RenderBox?;
      if (baseImageRenderBox == null) throw Exception("Could not get base image's render box.");
      final baseImageDisplayedSize = baseImageRenderBox.size;

      final img.Image? baseImage = img.decodeImage(widget.baseImageBytes);
      final img.Image? overlayImage = img.decodeImage(_overlayImageBytes!);
      if (baseImage == null || overlayImage == null) throw Exception("Could not decode images.");
      final baseImageOriginalSize = Size(baseImage.width.toDouble(), baseImage.height.toDouble());
      final overlayImageOriginalSize = Size(overlayImage.width.toDouble(), overlayImage.height.toDouble());

      // Calculate final position
      final viewCenter = MediaQuery.of(context).size.center(Offset.zero);
      final finalOverlayCenterGlobal = viewCenter + Offset(translationDelta.x, translationDelta.y);
      final finalOverlayCenterLocal = baseImageRenderBox.globalToLocal(finalOverlayCenterGlobal);
      final baseImageScaleFactor = baseImageOriginalSize.width / baseImageDisplayedSize.width;
      final imageSpaceCenterX = finalOverlayCenterLocal.dx * baseImageScaleFactor;
      final imageSpaceCenterY = finalOverlayCenterLocal.dy * baseImageScaleFactor;

      // Calculate final scale
      final screenSize = MediaQuery.of(context).size;
      final fittedOverlaySize = applyBoxFit(BoxFit.contain, overlayImageOriginalSize, screenSize).destination;
      final initialDownscale = fittedOverlaySize.width / overlayImageOriginalSize.width;
      final finalScale = initialDownscale * gestureScale;

      // Normalize coordinates
      final normalizedCenterX = imageSpaceCenterX / baseImageOriginalSize.width;
      final normalizedCenterY = imageSpaceCenterY / baseImageOriginalSize.height;

      // Create result
      final result = RemixEditorResult(
        overlayImageBytes: _overlayImageBytes!,
        normalizedCenterX: normalizedCenterX,
        normalizedCenterY: normalizedCenterY,
        scale: finalScale,
        rotation: rotationAngleDegrees,
      );

      // Return result
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Navigator.pop(context, result);
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _showCupertinoAlert('Error', 'Failed to process remix: $e');
      }
    }
  }

  void _showCupertinoAlert(String title, String message) {
    showCupertinoDialog(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.xmark,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        actions: [
          if (_overlayImageFile != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _isProcessing ? null : _onComplete,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isProcessing
                        ? Colors.white.withValues(alpha: 0.3)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Base image
          Positioned.fill(
            child: Image.memory(
              widget.baseImageBytes,
              key: _baseImageKey,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),

          // Overlay controls (Interactive image)
          if (_overlayImageFile != null)
            MatrixGestureDetector(
              onMatrixUpdate: (matrix, translationMatrix, scaleMatrix, rotationMatrix) {
                matrixNotifier.value = matrix;
                _translationMatrix = translationMatrix;
                _scaleMatrix = scaleMatrix;
                _rotationMatrix = rotationMatrix;
              },
              child: AnimatedBuilder(
                animation: matrixNotifier,
                builder: (context, child) {
                  return Transform(
                    transform: matrixNotifier.value,
                    child: child,
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Image.file(
                    _overlayImageFile!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

          // Instructions overlay
          if (_showInstructions && _overlayImageFile != null)
            FadeTransition(
              opacity: _instructionsFade,
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: Center(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 40),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.hand_draw,
                            size: 40,
                            color: Colors.black,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Position Your Image',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Drag to move\nPinch to resize\nRotate with two fingers',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.6),
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // Pick image button
          if (_overlayImageFile == null && !_isProcessing)
            Center(
              child: GestureDetector(
                onTap: _pickImage,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.photo_fill,
                        color: Colors.black,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Choose Photo',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Loading indicator
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoActivityIndicator(
                      color: Colors.white,
                      radius: 20,
                    ),
                    SizedBox(height: 14),
                    Text(
                      'Creating your remix...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
