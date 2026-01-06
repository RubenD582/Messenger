import 'package:flutter/material.dart';
import 'package:client/components/modern_avatar.dart';
import 'package:client/theme/colors.dart';
import 'package:client/theme/spacing.dart';

class ChatCard extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final String? username;
  final String? lastMessage;
  final String? timestamp;
  final int unreadCount;
  final bool isPinned;
  final bool isOnline;
  final bool isTyping;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const ChatCard({
    super.key,
    this.avatarUrl,
    required this.name,
    this.username,
    this.lastMessage,
    this.timestamp,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isOnline = false,
    this.isTyping = false,
    this.onTap,
    this.onLongPress,
  });

  String _getInitials() {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return name.substring(0, name.length >= 2 ? 2 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashColor: AppColors.ripple,
        highlightColor: AppColors.ripple,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm,
            vertical: Spacing.xs,
          ),
          child: Row(
            children: [
              // Avatar with online status
              ModernAvatar(
                imageUrl: avatarUrl,
                initials: _getInitials(),
                size: Sizes.avatarMedium,
                showOnlineStatus: true,
                isOnline: isOnline,
              ),

              const SizedBox(width: Spacing.sm),

              // Content (name, message, etc.)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Name with pin indicator
                        Expanded(
                          child: Row(
                            children: [
                              if (isPinned)
                                Padding(
                                  padding: const EdgeInsets.only(right: Spacing.xxs),
                                  child: Icon(
                                    Icons.push_pin,
                                    size: 14,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Timestamp
                        if (timestamp != null)
                          Text(
                            timestamp!,
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? AppColors.primary
                                  : AppColors.textTertiary,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: Spacing.xxs),

                    // Last message or typing indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: isTyping
                              ? _buildTypingIndicator()
                              : Text(
                                  lastMessage ?? 'Tap to send a message',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: unreadCount > 0
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                        ),

                        // Unread badge
                        if (unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: Spacing.xs),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Spacing.xs,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 20,
                              minHeight: 20,
                            ),
                            child: Center(
                              child: Text(
                                unreadCount > 99 ? '99+' : unreadCount.toString(),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Row(
      children: [
        const Text(
          'typing',
          style: TextStyle(
            color: AppColors.typing,
            fontSize: 14,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(width: 4),
        _TypingDots(),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.0, end: -4.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _animations[index].value),
              child: Container(
                margin: const EdgeInsets.only(right: 2),
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: AppColors.typing,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
