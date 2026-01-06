import 'package:flutter/material.dart';
import 'package:client/theme/colors.dart';
import 'package:client/theme/spacing.dart';

class ModernAvatar extends StatefulWidget {
  final String? imageUrl;
  final String? initials;
  final double size;
  final bool showOnlineStatus;
  final bool isOnline;
  final bool hasStory;
  final VoidCallback? onTap;

  const ModernAvatar({
    super.key,
    this.imageUrl,
    this.initials,
    this.size = Sizes.avatarMedium,
    this.showOnlineStatus = false,
    this.isOnline = false,
    this.hasStory = false,
    this.onTap,
  });

  @override
  State<ModernAvatar> createState() => _ModernAvatarState();
}

class _ModernAvatarState extends State<ModernAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _scaleController.forward();
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  String _getInitials() {
    if (widget.initials != null && widget.initials!.isNotEmpty) {
      return widget.initials!;
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    return GestureDetector(
      onTapDown: widget.onTap != null ? _handleTapDown : null,
      onTapUp: widget.onTap != null ? _handleTapUp : null,
      onTapCancel: widget.onTap != null ? _handleTapCancel : null,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: SizedBox(
          width: widget.size + (widget.hasStory ? 6 : 0),
          height: widget.size + (widget.hasStory ? 6 : 0),
          child: Stack(
            children: [
              // Story ring (gradient border)
              if (widget.hasStory)
                Container(
                  width: widget.size + 6,
                  height: widget.size + 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [
                        AppColors.primaryLight,
                        AppColors.primary,
                        AppColors.primaryDark,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Center(
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.background,
                      ),
                      child: _buildAvatar(hasImage),
                    ),
                  ),
                )
              else
                _buildAvatar(hasImage),

              // Online status indicator
              if (widget.showOnlineStatus && widget.isOnline)
                Positioned(
                  right: widget.hasStory ? 2 : 0,
                  bottom: widget.hasStory ? 2 : 0,
                  child: Container(
                    width: widget.size * 0.25,
                    height: widget.size * 0.25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.online,
                      border: Border.all(
                        color: AppColors.background,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(bool hasImage) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasImage ? null : AppColors.surfaceVariant,
        gradient: hasImage
            ? null
            : const LinearGradient(
                colors: [
                  AppColors.primaryDark,
                  AppColors.primary,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.asset(
              widget.imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildInitialsAvatar();
              },
            )
          : _buildInitialsAvatar(),
    );
  }

  Widget _buildInitialsAvatar() {
    final fontSize = widget.size * 0.4;
    return Center(
      child: Text(
        _getInitials().toUpperCase(),
        style: TextStyle(
          fontSize: fontSize,
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
