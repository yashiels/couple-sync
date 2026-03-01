import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/time_block.dart';
import '../../../core/theme/app_theme.dart';

class WindowCard extends StatelessWidget {
  const WindowCard({
    super.key,
    required this.window,
    required this.myUtcOffset,
    required this.partnerUtcOffset,
    this.onTap,
  });

  final FreeWindow window;
  final Duration myUtcOffset;
  final Duration partnerUtcOffset;
  final VoidCallback? onTap;

  String _fmt(DateTime utc, Duration offset) {
    return DateFormat('h:mm a').format(utc.add(offset));
  }

  bool get _isSoon {
    final diff = window.startUtc.difference(DateTime.now().toUtc());
    return diff.inHours < 12 && diff.isNegative == false;
  }

  @override
  Widget build(BuildContext context) {
    final myStart = _fmt(window.startUtc, myUtcOffset);
    final myEnd = _fmt(window.endUtc, myUtcOffset);
    final partnerStart = _fmt(window.startUtc, partnerUtcOffset);
    final partnerEnd = _fmt(window.endUtc, partnerUtcOffset);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.lavender.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: _isSoon
              ? Border.all(color: AppColors.lavender.withValues(alpha: 0.6), width: 1.5)
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Left: duration badge
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Text(
                window.durationLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Center: time ranges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TimeRow(
                    city: window.cityA,
                    timeRange: '$myStart – $myEnd',
                    dotColor: AppColors.rose,
                  ),
                  const SizedBox(height: 5),
                  _TimeRow(
                    city: window.cityB,
                    timeRange: '$partnerStart – $partnerEnd',
                    dotColor: AppColors.partnerB,
                  ),
                  if (window.suggestedActivity != null) ...[
                    const SizedBox(height: 8),
                    _ActivityChip(label: window.suggestedActivity!),
                  ],
                ],
              ),
            ),
            // Right: soon badge + arrow
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isSoon)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.roseLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.roseDark,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.onSurfaceMuted,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.city,
    required this.timeRange,
    required this.dotColor,
  });

  final String city;
  final String timeRange;
  final Color dotColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          city,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceMuted,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            timeRange,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActivityChip extends StatelessWidget {
  const _ActivityChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.lavenderLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 10, color: AppColors.lavenderDark),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.lavenderDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
