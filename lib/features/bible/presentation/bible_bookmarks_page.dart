import 'dart:async';

import 'package:flutter/material.dart';

import '../bible_service.dart';
import '../data/bible_reader_store.dart';
import '../domain/bible_models.dart';
import 'bible_reader_pages.dart';

class BibleBookmarksPage extends StatefulWidget {
  const BibleBookmarksPage({required this.service, super.key});

  final BibleService service;

  @override
  State<BibleBookmarksPage> createState() => _BibleBookmarksPageState();
}

class _BibleBookmarksPageState extends State<BibleBookmarksPage> {
  final BibleReaderStore _store = BibleReaderStore.instance;
  late final Future<void> _ready = _store.ensureLoaded();
  String? _openingId;

  Future<void> _open(BibleBookmark bookmark) async {
    if (_openingId != null) return;
    setState(() => _openingId = bookmark.id);
    try {
      final manifest = await widget.service.repository.translation(
        bookmark.translationId,
      );
      BibleBook? book;
      for (final candidate in manifest.books) {
        if (candidate.id == bookmark.bookId ||
            candidate.osisId == bookmark.bookId) {
          book = candidate;
          break;
        }
      }
      if (book == null) {
        throw StateError('The book is not present in this translation.');
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BibleReaderPage(
            service: widget.service,
            translationId: manifest.id,
            manifest: manifest,
            book: book!,
            chapter: bookmark.chapter,
            initialVerse: bookmark.verse,
          ),
        ),
      );
    } catch (error) {
      debugPrint('Bookmarked passage could not be opened: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This translation is not available on this device. Download it from the Bible library to open the bookmark.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarked verses')),
      body: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListenableBuilder(
            listenable: _store,
            builder: (context, _) {
              final bookmarks = _store.bookmarks;
              if (bookmarks.isEmpty) {
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(32),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.bookmarks_outlined,
                              size: 28,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No bookmarked verses yet',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tap a verse while reading and choose Bookmark verse. Your bookmarks stay on this device.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  height: 1.55,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                    itemCount: bookmarks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final bookmark = bookmarks[index];
                      final opening = _openingId == bookmark.id;
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: opening ? null : () => _open(bookmark),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: colors.secondaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.bookmark_rounded,
                                    size: 19,
                                    color: colors.onSecondaryContainer,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        bookmark.reference,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        bookmark.translationName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        bookmark.text,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: colors.onSurfaceVariant,
                                              height: 1.45,
                                            ),
                                      ),
                                      if (opening) ...[
                                        const SizedBox(height: 8),
                                        const SizedBox(
                                          height: 14,
                                          width: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove bookmark',
                                  onPressed: () =>
                                      _store.removeBookmark(bookmark.id),
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
