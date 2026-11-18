import 'dart:async';

import 'package:flutter/material.dart';

import '../bible_service.dart';
import '../domain/bible_models.dart';
import '../domain/bible_repository.dart';
import 'bible_reader_pages.dart';

/// Offline search across the translations already installed on this device.
/// No Supabase query and no online Bible API is involved.
class BibleSearchPage extends StatefulWidget {
  const BibleSearchPage({required this.service, super.key});

  final BibleService service;

  @override
  State<BibleSearchPage> createState() => _BibleSearchPageState();
}

class _BibleSearchPageState extends State<BibleSearchPage> {
  final TextEditingController _queryController = TextEditingController();
  final List<BibleTranslationManifest> _translations = [];
  String? _selectedId;
  List<BibleSearchHit> _results = const [];
  Timer? _debounce;
  bool _loadingTranslations = true;
  bool _searching = false;
  bool _hasSearched = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTranslations());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _loadTranslations() async {
    try {
      final ids = await widget.service.store.installedTranslationIds();
      for (final id in ids) {
        try {
          _translations.add(await widget.service.repository.translation(id));
        } catch (error) {
          debugPrint('Installed translation $id could not be read: $error');
        }
      }
      _translations.sort((a, b) => a.name.compareTo(b.name));
    } catch (error) {
      debugPrint('Installed translations could not be listed: $error');
    }
    if (!mounted) return;
    setState(() {
      _selectedId ??= _translations.isEmpty ? null : _translations.first.id;
      _loadingTranslations = false;
    });
  }

  BibleTranslationManifest? get _selectedManifest {
    for (final manifest in _translations) {
      if (manifest.id == _selectedId) return manifest;
    }
    return null;
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    setState(() {});
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _hasSearched = false;
        _searching = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(query),
    );
  }

  Future<void> _runSearch(String query) async {
    final manifest = _selectedManifest;
    if (manifest == null) return;
    final request = ++_requestId;
    setState(() {
      _searching = true;
      _hasSearched = true;
      _error = null;
    });
    try {
      final hits = await widget.service.repository.search(
        translationId: manifest.id,
        query: query,
      );
      if (!mounted || request != _requestId) return;
      setState(() {
        _results = hits;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || request != _requestId) return;
      debugPrint('Offline Bible search failed: $error');
      setState(() {
        _results = const [];
        _searching = false;
        _error = 'Search could not be completed. Check that the translation is still downloaded.';
      });
    }
  }

  void _selectTranslation(String id) {
    if (id == _selectedId) return;
    setState(() {
      _selectedId = id;
      _results = const [];
      _hasSearched = false;
      _error = null;
    });
    final query = _queryController.text.trim();
    if (query.length >= 2) {
      unawaited(_runSearch(query));
    }
  }

  void _openHit(BibleSearchHit hit) {
    final manifest = _selectedManifest;
    if (manifest == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleReaderPage(
          service: widget.service,
          translationId: manifest.id,
          manifest: manifest,
          book: hit.book,
          chapter: hit.chapter,
          initialVerse: hit.verse,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final manifest = _selectedManifest;
    return Scaffold(
      appBar: AppBar(title: const Text('Search the Bible')),
      body: _loadingTranslations
          ? const Center(child: CircularProgressIndicator())
          : _translations.isEmpty
          ? _EmptySearchState(
              icon: Icons.menu_book_rounded,
              title: 'No Bible downloaded',
              message: 'Download a translation from the Bible library first. Search works fully offline afterwards.',
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                      child: TextField(
                        controller: _queryController,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: _onQueryChanged,
                        decoration: InputDecoration(
                          hintText: 'Search words or phrases',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _queryController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    _queryController.clear();
                                    _onQueryChanged('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    if (_translations.length > 1)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _translations
                                .map(
                                  (item) => ChoiceChip(
                                    label: Text(item.shortName),
                                    selected: item.id == _selectedId,
                                    onSelected: (_) =>
                                        _selectTranslation(item.id),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ),
                      ),
                    Expanded(child: _buildResults(context, manifest, colors)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    BibleTranslationManifest? manifest,
    ColorScheme colors,
  ) {
    if (_searching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Searching your offline Bible\u2026',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 6),
              Text(
                'The first search prepares a local index.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return _EmptySearchState(
        icon: Icons.error_outline_rounded,
        title: 'Search unavailable',
        message: _error!,
      );
    }
    if (!_hasSearched) {
      return _EmptySearchState(
        icon: Icons.search_rounded,
        title: 'Search without internet',
        message:
            'Type at least two letters to find verses in ${manifest?.name ?? 'your downloaded Bible'}. Everything stays on this device.',
      );
    }
    if (_results.isEmpty) {
      return _EmptySearchState(
        icon: Icons.search_off_rounded,
        title: 'No verses found',
        message:
            'No verse in ${manifest?.shortName ?? 'this translation'} matched your search. Try a different word or translation.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
      itemCount: _results.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
            child: Text(
              '${_results.length} ${_results.length == 1 ? 'match' : 'matches'} in ${manifest?.name ?? ''}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          );
        }
        final hit = _results[index - 1];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openHit(hit),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hit.reference,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Text(
                        manifest?.shortName ?? '',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    hit.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.5, color: colors.onSurface),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
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
                child: Icon(icon, size: 28, color: colors.primary),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
