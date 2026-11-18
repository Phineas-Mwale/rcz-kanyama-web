import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

IconData historyCategoryIcon(String category) {
  switch (category.toLowerCase()) {
    case 'pastors':
      return Icons.church_outlined;
    case 'executives':
      return Icons.groups_2_outlined;
    case 'secretariat':
      return Icons.assignment_ind_outlined;
    case 'milestones':
      return Icons.flag_outlined;
    case 'events':
      return Icons.event_note_outlined;
    default:
      return Icons.collections_bookmark_outlined;
  }
}

Color historyCategoryColor(String category, ColorScheme colors) {
  switch (category.toLowerCase()) {
    case 'pastors':
      return colors.secondary;
    case 'executives':
      return colors.primary;
    case 'secretariat':
      return colors.tertiary;
    case 'milestones':
      return colors.secondary;
    case 'events':
      return colors.primary;
    default:
      return colors.onSurfaceVariant;
  }
}

class HistoryCategoryChip extends StatelessWidget {
  const HistoryCategoryChip({
    required this.category,
    this.compact = false,
    super.key,
  });

  final String category;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = historyCategoryColor(category, colors);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: accent.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            historyCategoryIcon(category),
            size: compact ? 11 : 12,
            color: accent,
          ),
          const SizedBox(width: 5),
          Text(
            category.toUpperCase(),
            style: TextStyle(
              color: accent,
              fontSize: compact ? 8.5 : 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: .9,
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight, cache-friendly image with graceful missing/failed states.
class HistoryImage extends StatelessWidget {
  const HistoryImage({
    this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.photo_outlined,
    super.key,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(18);
    Widget child;
    if (url == null || url!.isEmpty) {
      child = _placeholder(context);
    } else {
      child = Image.network(
        url!,
        width: width,
        height: height,
        fit: fit,
        // Decode at a sensible size instead of the original camera resolution.
        cacheWidth: (width != null && width!.isFinite)
            ? (width! * 2).round()
            : null,
        frameBuilder: (context, image, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return image;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            child: image,
          );
        },
        loadingBuilder: (context, image, progress) {
          if (progress == null) return image;
          return _placeholder(context, loading: true);
        },
        errorBuilder: (_, _, _) => _placeholder(context),
      );
    }
    return ClipRRect(borderRadius: radius, child: child);
  }

  Widget _placeholder(BuildContext context, {bool loading = false}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      color: colors.surfaceContainerHigh,
      alignment: Alignment.center,
      child: loading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onSurfaceVariant.withValues(alpha: .55),
              ),
            )
          : Icon(
              placeholderIcon,
              size: 30,
              color: colors.onSurfaceVariant.withValues(alpha: .55),
            ),
    );
  }
}
