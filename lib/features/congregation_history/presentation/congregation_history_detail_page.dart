import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../domain/congregation_history_models.dart';
import 'history_visuals.dart';

class CongregationHistoryDetailPage extends StatelessWidget {
  const CongregationHistoryDetailPage({
    required this.entry,
    this.preview = false,
    super.key,
  });

  final CongregationHistoryEntry entry;
  final bool preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final biography = entry.biography?.trim() ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(preview ? 'Preview record' : 'Archive record'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
            children: [
              if (preview)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 17,
                        color: colors.onSecondaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Preview only. This record is not visible to members until it is published.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (entry.coverUrl != null)
                SizedBox(
                  height: 280,
                  child: HistoryImage(
                    url: entry.coverUrl,
                    borderRadius: BorderRadius.circular(24),
                    placeholderIcon: historyCategoryIcon(entry.category),
                  ),
                )
              else
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: AppDecor.heroGradient(context),
                  ),
                  child: Center(
                    child: Icon(
                      historyCategoryIcon(entry.category),
                      size: 52,
                      color: Colors.white.withValues(alpha: .5),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  HistoryCategoryChip(category: entry.category),
                  const Spacer(),
                  if (entry.yearsLabel != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        entry.yearsLabel!,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                entry.title,
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 32,
                  height: 1.14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
              if (entry.peopleLine.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  entry.peopleLine,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              if (biography.isNotEmpty) ...[
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.secondary,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'THE STORY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.secondary,
                        letterSpacing: 1.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SelectableText(
                  biography,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(height: 1.75, color: colors.onSurface),
                ),
              ],
              if (entry.photos.isNotEmpty) ...[
                const SizedBox(height: 28),
                Row(
                  children: [
                    Text(
                      'Photographs',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Text(
                      '${entry.photos.length} ${entry.photos.length == 1 ? 'image' : 'images'}',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _HistoryGallery(entry: entry),
              ] else if (entry.coverUrl != null) ...[
                const SizedBox(height: 24),
                Text(
                  'No additional photographs have been added to this record.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              Divider(color: colors.outlineVariant),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview
                          ? 'Preview from the RCZ Kanyama Media Team'
                          : 'Published by the RCZ Kanyama Media Team',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryGallery extends StatefulWidget {
  const _HistoryGallery({required this.entry});

  final CongregationHistoryEntry entry;

  @override
  State<_HistoryGallery> createState() => _HistoryGalleryState();
}

class _HistoryGalleryState extends State<_HistoryGallery> {
  late final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openFullScreen(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HistoryPhotoViewer(
          photos: widget.entry.photos,
          initialPage: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final photos = widget.entry.photos;
    final current = photos[_page < photos.length ? _page : photos.length - 1];
    final caption = current.caption?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 250,
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: photos.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  return GestureDetector(
                    onTap: () => _openFullScreen(index),
                    child: HistoryImage(
                      url: photo.url,
                      borderRadius: BorderRadius.circular(20),
                      placeholderIcon: Icons.photo_outlined,
                    ),
                  );
                },
              ),
              if (photos.length > 1) ...[
                Positioned(
                  left: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryArrow(
                      icon: Icons.chevron_left_rounded,
                      onTap: _page == 0
                          ? null
                          : () => _controller.previousPage(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                            ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _GalleryArrow(
                      icon: Icons.chevron_right_rounded,
                      onTap: _page == photos.length - 1
                          ? null
                          : () => _controller.nextPage(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                            ),
                    ),
                  ),
                ),
              ],
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '${_page + 1} / ${photos.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (caption.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
        if (photos.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              photos.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: index == _page ? 18 : 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: index == _page
                      ? colors.secondary
                      : colors.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          'Tap a photograph to open it full screen and zoom.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant, fontSize: 10.5),
        ),
      ],
    );
  }
}

class _GalleryArrow extends StatelessWidget {
  const _GalleryArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: .42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(
            icon,
            size: 22,
            color: Colors.white.withValues(alpha: onTap == null ? .3 : .9),
          ),
        ),
      ),
    );
  }
}

class _HistoryPhotoViewer extends StatefulWidget {
  const _HistoryPhotoViewer({required this.photos, required this.initialPage});

  final List<CongregationHistoryPhoto> photos;
  final int initialPage;

  @override
  State<_HistoryPhotoViewer> createState() => _HistoryPhotoViewerState();
}

class _HistoryPhotoViewerState extends State<_HistoryPhotoViewer> {
  late final PageController _controller = PageController(
    initialPage: widget.initialPage,
  );
  late int _page = widget.initialPage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current =
        widget.photos[_page < widget.photos.length
            ? _page
            : widget.photos.length - 1];
    final caption = current.caption?.trim() ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          '${_page + 1} of ${widget.photos.length}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.photos.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (context, index) {
                  final photo = widget.photos[index];
                  return InteractiveViewer(
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: HistoryImage(
                        url: photo.url,
                        fit: BoxFit.contain,
                        borderRadius: BorderRadius.zero,
                        placeholderIcon: Icons.broken_image_outlined,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (caption.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
