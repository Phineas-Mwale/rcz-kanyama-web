import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../data/congregation_history_repository.dart';
import '../domain/congregation_history_models.dart';
import 'congregation_history_detail_page.dart';
import 'history_visuals.dart';

class CongregationHistoryPage extends StatefulWidget {
  const CongregationHistoryPage({super.key});

  @override
  State<CongregationHistoryPage> createState() =>
      _CongregationHistoryPageState();
}

class _CongregationHistoryPageState extends State<CongregationHistoryPage> {
  late final CongregationHistoryRepository _repository =
      CongregationHistoryRepository(Supabase.instance.client);
  List<CongregationHistoryEntry> _entries = const [];
  bool _loading = true;
  String? _error;
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final entries = await _repository.fetchPublishedEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        if (_category != 'All' &&
            !entries.any((entry) => entry.category == _category)) {
          _category = 'All';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
      debugPrint('Congregation history could not load: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      if (error.code == 'PGRST205' ||
          error.message.contains('schema cache') ||
          error.message.contains('Could not find the table')) {
        return 'The congregation history archive has not been set up in Supabase yet. Ask the church administrator to run the corrective migration.';
      }
      if (error.code == '42501' ||
          error.message.toLowerCase().contains('permission')) {
        return 'You do not have permission to view the archive right now.';
      }
    }
    return 'The congregation history could not be opened. Check your internet connection and try again.';
  }

  List<String> get _visibleCategories {
    final present = <String>{for (final entry in _entries) entry.category};
    final known = congregationHistoryCategories
        .where(present.contains)
        .toList();
    final extra =
        present
            .where(
              (category) => !congregationHistoryCategories.contains(category),
            )
            .toList()
          ..sort();
    return [...known, ...extra];
  }

  List<CongregationHistoryEntry> get _filteredEntries {
    if (_category == 'All') return _entries;
    return _entries
        .where((entry) => entry.category == _category)
        .toList(growable: false);
  }

  int _countFor(String category) {
    if (category == 'All') return _entries.length;
    return _entries.where((entry) => entry.category == category).length;
  }

  void _open(CongregationHistoryEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CongregationHistoryDetailPage(entry: entry),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kanyama Congregation History'),
        actions: [
          IconButton(
            tooltip: 'Refresh archive',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
              children: [
                const _HistoryHero(),
                const SizedBox(height: 18),
                const _ArchiveIntroduction(),
                const SizedBox(height: 22),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(42),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _ArchiveError(message: _error!, onRetry: _load)
                else ...[
                  if (_visibleCategories.isNotEmpty) ...[
                    _CategoryFilters(
                      categories: _visibleCategories,
                      selected: _category,
                      countFor: _countFor,
                      onSelected: (value) => setState(() => _category = value),
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (_filteredEntries.isEmpty)
                    _ArchiveEmpty(
                      hasArchive: _entries.isNotEmpty,
                      category: _category,
                    )
                  else ...[
                    Row(
                      children: [
                        Text(
                          _category == 'All' ? 'The story so far' : _category,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        Text(
                          '${_filteredEntries.length} ${_filteredEntries.length == 1 ? 'record' : 'records'}',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ..._filteredEntries.map(
                      (entry) => _HistoryTimelineCard(
                        entry: entry,
                        onTap: () => _open(entry),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Maintained by the RCZ Kanyama Media Team • Published records only',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryHero extends StatelessWidget {
  const _HistoryHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
      decoration: BoxDecoration(
        gradient: AppDecor.heroGradient(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppDecor.softShadow(context),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -20,
            top: -28,
            child: Icon(
              Icons.account_balance_rounded,
              size: 140,
              color: Colors.white.withValues(alpha: .07),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .12),
                  ),
                ),
                child: const Text(
                  'OUR STORY • RCZ KANYAMA',
                  style: TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 9.5,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'A congregation\nshaped by grace.',
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  color: Colors.white,
                  fontSize: 32,
                  height: 1.08,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The people, ministry and moments that have made Kanyama a home for generations of believers.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  height: 1.5,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchiveIntroduction extends StatelessWidget {
  const _ArchiveIntroduction();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 21,
                color: colors.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A living archive',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'This is the story of RCZ Kanyama Congregation itself: the pastors who shepherded us, the office bearers who served, and the milestones that mark our journey. It is separate from the RCZ-wide Church History page and is cared for by the congregation Media Team.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant, height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryFilters extends StatelessWidget {
  const _CategoryFilters({
    required this.categories,
    required this.selected,
    required this.countFor,
    required this.onSelected,
  });

  final List<String> categories;
  final String selected;
  final int Function(String) countFor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = ['All', ...categories];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          final active = value == selected;
          final accent = value == 'All'
              ? colors.primary
              : historyCategoryColor(value, colors);
          return Material(
            color: active ? accent : colors.surface,
            shape: StadiumBorder(
              side: BorderSide(color: active ? accent : colors.outlineVariant),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onSelected(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 13),
                child: Row(
                  children: [
                    if (value != 'All') ...[
                      Icon(
                        historyCategoryIcon(value),
                        size: 13,
                        color: active ? colors.onPrimary : accent,
                      ),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      value,
                      style: TextStyle(
                        color: active ? colors.onPrimary : colors.onSurface,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${countFor(value)}',
                      style: TextStyle(
                        color: active
                            ? colors.onPrimary.withValues(alpha: .72)
                            : colors.onSurfaceVariant,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HistoryTimelineCard extends StatelessWidget {
  const _HistoryTimelineCard({required this.entry, required this.onTap});

  final CongregationHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final years = entry.yearsLabel;
    final biography = entry.biography?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Column(
              children: [
                const SizedBox(height: 18),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: historyCategoryColor(entry.category, colors),
                    border: Border.all(color: colors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: historyCategoryColor(
                          entry.category,
                          colors,
                        ).withValues(alpha: .25),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (years != null)
                  Text(
                    years,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: colors.onSurfaceVariant,
                      height: 1.3,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (entry.coverUrl != null)
                      SizedBox(
                        height: 166,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            HistoryImage(
                              url: entry.coverUrl,
                              borderRadius: BorderRadius.zero,
                              placeholderIcon: historyCategoryIcon(
                                entry.category,
                              ),
                            ),
                            Positioned(
                              left: 12,
                              top: 12,
                              child: HistoryCategoryChip(
                                category: entry.category,
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entry.coverUrl == null) ...[
                            HistoryCategoryChip(
                              category: entry.category,
                              compact: true,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            entry.title,
                            style: const TextStyle(
                              fontFamily: 'SourceSerif4',
                              fontSize: 20,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (entry.peopleLine.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              entry.peopleLine,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                          if (biography.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              biography,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    height: 1.55,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Text(
                                'Open record',
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(
                                      color: colors.primary,
                                      fontSize: 11.5,
                                    ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: colors.primary,
                              ),
                              const Spacer(),
                              if (entry.photos.isNotEmpty) ...[
                                Icon(
                                  Icons.photo_library_outlined,
                                  size: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.photos.length}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveError extends StatelessWidget {
  const _ArchiveError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Icons.cloud_off_outlined,
                color: colors.onErrorContainer,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'The archive is unavailable',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveEmpty extends StatelessWidget {
  const _ArchiveEmpty({required this.hasArchive, required this.category});

  final bool hasArchive;
  final String category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          children: [
            Icon(
              Icons.collections_bookmark_outlined,
              size: 38,
              color: colors.primary,
            ),
            const SizedBox(height: 12),
            Text(
              hasArchive
                  ? 'No $category records yet'
                  : 'The archive is being prepared',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 7),
            Text(
              hasArchive
                  ? 'Choose another category or return to the full archive.'
                  : 'Published congregation records will appear here as the Media Team adds them.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
            ),
          ],
        ),
      ),
    );
  }
}
