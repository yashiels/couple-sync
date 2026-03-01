import 'package:flutter/material.dart';
import '../../../core/models/time_block.dart';
import '../../../core/theme/app_theme.dart';

class BlockOverlay extends StatelessWidget {
  const BlockOverlay({
    super.key,
    required this.block,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    this.onTap,
  });

  final TimeBlock block;
  final double top;
  final double height;
  final double left;
  final double width;
  final VoidCallback? onTap;

  Color get _blockColor =>
      block.owner == BlockOwner.me ? AppColors.rose : AppColors.partnerB;

  @override
  Widget build(BuildContext context) {
    final isCompact = height < 24;

    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _blockColor.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _blockColor,
              width: 1,
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 5,
            vertical: isCompact ? 2 : 4,
          ),
          child: isCompact
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      block.title ??
                          (block.owner == BlockOwner.me ? 'Busy' : 'Partner busy'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                      ),
                    ),
                    if (height > 40)
                      Text(
                        block.owner == BlockOwner.me ? 'You' : 'Partner',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Overlap highlight — a translucent gradient band on the calendar.
class OverlapOverlay extends StatelessWidget {
  const OverlapOverlay({
    super.key,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
    this.onTap,
  });

  final double top;
  final double height;
  final double left;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.overlapGradient,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: AppColors.lavender.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: height > 30
              ? Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite_rounded,
                        size: 9,
                        color: AppColors.lavenderDark.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Free',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.lavenderDark.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
