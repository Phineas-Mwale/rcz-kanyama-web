import 'package:flutter/material.dart';

import '../bible_service.dart';
import '../domain/bible_models.dart';

const _readerAccent = Color(0xFFB78635);

class BibleBooksPage extends StatefulWidget {
  const BibleBooksPage({required this.service, required this.translationId, required this.translationName, super.key});
  final BibleService service;
  final String translationId;
  final String translationName;

  @override
  State<BibleBooksPage> createState() => _BibleBooksPageState();
}

class _BibleBooksPageState extends State<BibleBooksPage> {
  late final Future<BibleTranslationManifest> _manifestFuture = widget.service.repository.translation(widget.translationId);
  String _query = '';

  Future<void> _chooseChapter(BibleTranslationManifest manifest, BibleBook book) async {
    final chapter = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _ChapterPicker(book: book),
    );
    if (chapter == null || !mounted) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BibleReaderPage(service: widget.service, translationId: widget.translationId, manifest: manifest, book: book, chapter: chapter)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.translationName, style: const TextStyle(fontWeight: FontWeight.w800))),
      body: FutureBuilder<BibleTranslationManifest>(
        future: _manifestFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Could not read this translation. ${snapshot.error}', textAlign: TextAlign.center)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final manifest = snapshot.data!;
          final filtered = manifest.books.where((book) => book.name.toLowerCase().contains(_query.toLowerCase()) || book.englishName.toLowerCase().contains(_query.toLowerCase())).toList();
          final oldBooks = filtered.where((book) => book.testament == 'old').toList();
          final newBooks = filtered.where((book) => book.testament == 'new').toList();
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 16), child: Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), color: colors.primaryContainer), child: Row(children: [Icon(Icons.auto_stories_rounded, size: 34, color: colors.onPrimaryContainer), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(manifest.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: colors.onPrimaryContainer)), const SizedBox(height: 3), Text('${manifest.books.length} books  •  ${manifest.books.fold<int>(0, (sum, book) => sum + book.chapterCount)} chapters  •  Offline', style: TextStyle(fontSize: 11, color: colors.onPrimaryContainer.withValues(alpha: .8)))]))])))),
            SliverPadding(padding: const EdgeInsets.fromLTRB(18, 0, 18, 12), sliver: SliverToBoxAdapter(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Find a book', isDense: true), onChanged: (value) => setState(() => _query = value)))),
            if (oldBooks.isNotEmpty) ...[
              _SectionHeading(title: 'OLD TESTAMENT', count: oldBooks.length),
              _BookGrid(books: oldBooks, onTap: (book) => _chooseChapter(manifest, book)),
            ],
            if (newBooks.isNotEmpty) ...[
              _SectionHeading(title: 'NEW TESTAMENT', count: newBooks.length),
              _BookGrid(books: newBooks, onTap: (book) => _chooseChapter(manifest, book)),
            ],
            if (filtered.isEmpty) const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(28), child: Center(child: Text('No books match your search.')))),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ]);
        },
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.count});
  final String title;
  final int count;
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 10), child: Row(children: [Text(title, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.3)), const SizedBox(width: 8), Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant)), const SizedBox(width: 8), Text('$count', style: Theme.of(context).textTheme.labelSmall)])));
}

class _BookGrid extends StatelessWidget {
  const _BookGrid({required this.books, required this.onTap});
  final List<BibleBook> books;
  final ValueChanged<BibleBook> onTap;
  @override
  Widget build(BuildContext context) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        sliver: SliverGrid.builder(
          itemCount: books.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 9, crossAxisSpacing: 9, childAspectRatio: 2.35),
          itemBuilder: (context, index) {
            final book = books[index];
            return Material(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(15), child: InkWell(borderRadius: BorderRadius.circular(15), onTap: () => onTap(book), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), child: Row(children: [Container(width: 32, height: 32, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(10)), alignment: Alignment.center, child: Text('${index + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onPrimaryContainer))), const SizedBox(width: 9), Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(book.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)), Text('${book.chapterCount} chapters', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))])), const Icon(Icons.chevron_right_rounded, size: 17)]))));
          },
        ),
      );
}

class _ChapterPicker extends StatelessWidget {
  const _ChapterPicker({required this.book});
  final BibleBook book;
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(book.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text('Choose a chapter to begin reading', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)), const SizedBox(height: 18), SizedBox(height: 300, child: GridView.builder(itemCount: book.chapterCount, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 9, crossAxisSpacing: 9), itemBuilder: (context, index) => Material(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(13), child: InkWell(borderRadius: BorderRadius.circular(13), onTap: () => Navigator.pop(context, index + 1), child: Center(child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.w800)))))))])));
}

class BibleReaderPage extends StatefulWidget {
  const BibleReaderPage({required this.service, required this.translationId, required this.manifest, required this.book, required this.chapter, super.key});
  final BibleService service;
  final String translationId;
  final BibleTranslationManifest manifest;
  final BibleBook book;
  final int chapter;

  @override
  State<BibleReaderPage> createState() => _BibleReaderPageState();
}

class _BibleReaderPageState extends State<BibleReaderPage> {
  late BibleBook _book = widget.book;
  late int _chapterNumber = widget.chapter;
  late Future<BibleChapter> _chapterFuture = _load();
  double _fontSize = 18;

  Future<BibleChapter> _load() => widget.service.repository.chapter(translationId: widget.translationId, bookId: _book.id, chapter: _chapterNumber);

  void _changeChapter(int delta) {
    final next = _chapterNumber + delta;
    if (next < 1 || next > _book.chapterCount) return;
    setState(() { _chapterNumber = next; _chapterFuture = _load(); });
  }

  Future<void> _selectBook() async {
    final selected = await showModalBottomSheet<BibleBook>(context: context, isScrollControlled: true, showDragHandle: true, builder: (context) => SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(18, 0, 18, 24), shrinkWrap: true, children: [Padding(padding: const EdgeInsets.all(8), child: Text('Choose a book', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))), ...widget.manifest.books.map((book) => ListTile(title: Text(book.name), subtitle: Text('${book.chapterCount} chapters'), trailing: book.id == _book.id ? const Icon(Icons.check_circle_rounded) : null, onTap: () => Navigator.pop(context, book)))])));
    if (selected == null || !mounted) return;
    final selectedChapter = await showModalBottomSheet<int>(context: context, showDragHandle: true, builder: (_) => _ChapterPicker(book: selected));
    if (selectedChapter == null || !mounted) return;
    setState(() { _book = selected; _chapterNumber = selectedChapter; _chapterFuture = _load(); });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(onTap: _selectBook, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_book.name, style: const TextStyle(fontWeight: FontWeight.w900)), Text('Chapter $_chapterNumber  •  ${widget.manifest.shortName}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant))])),
        actions: [IconButton(tooltip: 'Decrease text size', onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(14, 26).toDouble()), icon: const Icon(Icons.text_decrease_rounded)), IconButton(tooltip: 'Increase text size', onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(14, 26).toDouble()), icon: const Icon(Icons.text_increase_rounded))],
      ),
      body: FutureBuilder<BibleChapter>(
        future: _chapterFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('This chapter could not be opened. ${snapshot.error}', textAlign: TextAlign.center)));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final chapter = snapshot.data!;
          return Column(children: [
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(22, 20, 22, 24), children: [
              Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6), decoration: BoxDecoration(color: colors.secondaryContainer, borderRadius: BorderRadius.circular(30)), child: Text('${_book.name.toUpperCase()}  •  CHAPTER $_chapterNumber', style: TextStyle(color: colors.onSecondaryContainer, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900)))),
              const SizedBox(height: 22),
              Center(child: Text(_book.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.5))),
              Center(child: Text('$_chapterNumber', style: TextStyle(fontSize: 42, height: 1.15, fontWeight: FontWeight.w900, color: _readerAccent.withValues(alpha: .9)))),
              const SizedBox(height: 20),
              ...chapter.verses.map((verse) => Padding(padding: const EdgeInsets.only(bottom: 13), child: SelectableText.rich(TextSpan(children: [TextSpan(text: '${verse.number}  ', style: TextStyle(fontSize: _fontSize * .68, fontWeight: FontWeight.w900, color: _readerAccent)), TextSpan(text: verse.text, style: TextStyle(fontSize: _fontSize, height: 1.72, letterSpacing: .05, color: colors.onSurface))])))),
              const SizedBox(height: 16),
              if (widget.manifest.attribution != null) Text(widget.manifest.attribution!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant)),
            ])),
            Container(padding: const EdgeInsets.fromLTRB(16, 10, 16, 14), decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.outlineVariant.withValues(alpha: .55)))), child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: _chapterNumber > 1 ? () => _changeChapter(-1) : null, icon: const Icon(Icons.chevron_left_rounded), label: const Text('Previous'))), const SizedBox(width: 12), Expanded(child: FilledButton.icon(onPressed: _chapterNumber < _book.chapterCount ? () => _changeChapter(1) : null, icon: const Icon(Icons.chevron_right_rounded), label: const Text('Next chapter'), iconAlignment: IconAlignment.end))])),
          ]);
        },
      ),
    );
  }
}
