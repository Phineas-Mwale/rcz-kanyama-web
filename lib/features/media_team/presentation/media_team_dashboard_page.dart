import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../../congregation_history/data/congregation_history_repository.dart';
import '../../congregation_history/domain/congregation_history_models.dart';
import '../../congregation_history/presentation/congregation_history_detail_page.dart';
import '../../congregation_history/presentation/history_visuals.dart';
import 'congregation_history_editor_page.dart';

/// The working dashboard for approved Media Team members.
///
/// Authorisation is re-checked against `media_team_accounts` on entry. The
/// dashboard only offers controls for actions the active account is allowed to
/// perform, and every write is still enforced by Supabase RLS.
class MediaTeamDashboardPage extends StatefulWidget {
  const MediaTeamDashboardPage({required this.displayName, super.key});

  final String displayName;

  @override
  State<MediaTeamDashboardPage> createState() => _MediaTeamDashboardPageState();
}

class _MediaTeamDashboardPageState extends State<MediaTeamDashboardPage> {
  late final CongregationHistoryRepository _repository =
      CongregationHistoryRepository(Supabase.instance.client);
  final TextEditingController _search = TextEditingController();

  List<CongregationHistoryEntry> _entries = const [];
  bool _checkingAccess = true;
  bool _loading = true;
  bool _ordering = false;
  String? _accessError;
  String? _loadError;
  String _status = 'all';
  String _category = 'All';

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    unawaited(_start());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _start() async {
    final authorised = await _verifyAccess();
    if (!authorised) return;
    await _load();
  }

  Future<bool> _verifyAccess({bool showSpinner = true}) async {
    if (mounted) {
      setState(() {
        if (showSpinner) _checkingAccess = true;
        _accessError = null;
      });
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      if (!mounted) return false;
      setState(() {
        _checkingAccess = false;
        _accessError =
            'Your session has ended. Sign in again to manage the archive.';
      });
      return false;
    }
    try {
      final row = await client
          .from('media_team_accounts')
          .select('is_active')
          .eq('user_id', user.id)
          .maybeSingle();
      if (!mounted) return false;
      if (row == null || row['is_active'] != true) {
        setState(() {
          _checkingAccess = false;
          _accessError = 'This account is no longer an active Media Team account. Ask a church administrator to review it.';
        });
        return false;
      }
      setState(() => _checkingAccess = false);
      return true;
    } on PostgrestException catch (error) {
      if (!mounted) return false;
      setState(() {
        _checkingAccess = false;
        _accessError = _friendlyError(error);
      });
      return false;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _checkingAccess = false;
        _accessError = 'Media Team access could not be checked. Check your connection and try again.';
      });
      debugPrint('Media Team dashboard access check failed: $error');
      return false;
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (Supabase.instance.client.auth.currentUser == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _accessError =
            'Your session has ended. Sign in again to manage the archive.';
      });
      return;
    }
    if (mounted && !silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final entries = await _repository.fetchAllEntries();
      if (!mounted) return;
      setState(() {
        _entries = entries;
        if (_category != 'All' &&
            !entries.any((entry) => entry.category == _category)) {
          _category = 'All';
        }
        _loadError = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (silent && _entries.isNotEmpty) {
        _message('The latest archive changes could not be loaded.');
      } else {
        setState(() {
          _loading = false;
          _loadError = _friendlyError(error);
        });
      }
      if (silent) setState(() => _loading = false);
      debugPrint('Media Team archive load failed: $error');
    }
  }

  /// Re-checks that the account is still active before showing the archive.
  /// RLS protects every write, but this keeps a revoked account from seeing a
  /// misleading partial list.
  Future<void> _refresh() async {
    final authorised = await _verifyAccess(showSpinner: false);
    if (authorised) await _load();
  }

  String _friendlyError(Object error) {
    if (error is PostgrestException) {
      final message = error.message.toLowerCase();
      if (error.code == 'PGRST205' ||
          error.code == 'PGRST202' ||
          message.contains('schema cache') ||
          message.contains('could not find the table') ||
          message.contains('could not find the function')) {
        return 'The archive tables have not been created in Supabase yet. Ask the church administrator to run the corrective migration.';
      }
      if (error.code == '42703' || message.contains('does not exist')) {
        return 'The archive database is out of date. Ask the church administrator to run the corrective migration.';
      }
      if (error.code == '42501' || message.contains('permission')) {
        return 'This account does not have permission to manage the archive. Ask a church administrator to activate Media Team access.';
      }
      final trimmed = error.message.trim();
      if (trimmed.isNotEmpty) {
        return 'The archive could not be loaded: $trimmed';
      }
    }
    if (error is StorageException) {
      return 'Archive photographs could not be loaded: ${error.message}';
    }
    return 'The archive could not be loaded. Check your internet connection and try again.';
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<String> get _categories {
    final present = <String>{for (final entry in _entries) entry.category};
    final known = congregationHistoryCategories
        .where(present.contains)
        .toList(growable: false);
    final extra =
        present
            .where(
              (category) => !congregationHistoryCategories.contains(category),
            )
            .toList()
          ..sort();
    return [...known, ...extra];
  }

  List<CongregationHistoryEntry> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _entries
        .where((entry) {
          if (_status == 'published' && !entry.isPublished) return false;
          if (_status == 'draft' && entry.isPublished) return false;
          if (_category != 'All' && entry.category != _category) return false;
          if (query.isEmpty) return true;
          final haystack = [
            entry.title,
            entry.personName ?? '',
            entry.position ?? '',
            entry.biography ?? '',
            entry.category,
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  int get _publishedCount =>
      _entries.where((entry) => entry.isPublished).length;

  int get _draftCount => _entries.length - _publishedCount;

  /// Reordering is only meaningful against the full, unfiltered list. Moving a
  /// visible row past a hidden one would otherwise look like nothing happened.
  bool get _reorderAvailable =>
      _status == 'all' && _category == 'All' && _search.text.trim().isEmpty;

  Future<void> _create() async {
    final suggestedOrder = _entries.isEmpty
        ? 0
        : _entries
                  .map((entry) => entry.displayOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CongregationHistoryEditorPage(
          repository: _repository,
          suggestedOrder: suggestedOrder,
        ),
      ),
    );
    if (saved == true) {
      _message('Archive record saved.');
      await _load(silent: true);
    }
  }

  Future<void> _edit(CongregationHistoryEntry entry) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CongregationHistoryEditorPage(
          repository: _repository,
          entry: entry,
        ),
      ),
    );
    if (saved == true) {
      _message('Archive record updated.');
      await _load(silent: true);
    }
  }

  Future<void> _preview(CongregationHistoryEntry entry) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CongregationHistoryDetailPage(
          entry: entry,
          preview: !entry.isPublished,
        ),
      ),
    );
  }

  Future<void> _togglePublished(CongregationHistoryEntry entry) async {
    final publish = !entry.isPublished;
    try {
      await _repository.updateEntry(entry.id, {
        'is_published': publish,
        'published_at': publish
            ? entry.publishedAt?.toUtc().toIso8601String() ??
                  DateTime.now().toUtc().toIso8601String()
            : null,
      });
      _message(publish ? 'Record published.' : 'Record moved back to drafts.');
      await _load(silent: true);
    } catch (error) {
      _message(
        publish
            ? 'The record could not be published. Try again.'
            : 'The record could not be unpublished. Try again.',
      );
      debugPrint('History publish toggle failed: $error');
    }
  }

  Future<void> _delete(CongregationHistoryEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: Text(
          '“${entry.title}” and its gallery photographs will be permanently removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _repository.deleteEntry(entry.id);
      try {
        await _repository.removePhotos(entry.allPhotoPaths);
      } catch (error) {
        // The database record is already gone; orphaned files are harmless.
        debugPrint('Deleted record photos could not be cleaned up: $error');
      }
      _message('Archive record deleted.');
      await _load(silent: true);
    } catch (error) {
      _message('The record could not be deleted. Try again.');
      debugPrint('History record deletion failed: $error');
    }
  }

  Future<void> _move(CongregationHistoryEntry entry, int delta) async {
    if (_ordering || !_reorderAvailable) return;
    final index = _entries.indexWhere((item) => item.id == entry.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _entries.length) return;

    setState(() => _ordering = true);
    final reordered = [..._entries];
    final moved = reordered.removeAt(index);
    reordered.insert(target, moved);
    try {
      for (var position = 0; position < reordered.length; position++) {
        if (reordered[position].displayOrder == position) continue;
        await _repository.updateDisplayOrder(reordered[position].id, position);
      }
      await _load(silent: true);
    } catch (error) {
      _message('The archive order could not be changed. Try again.');
      debugPrint('History order change failed: $error');
    } finally {
      if (mounted) setState(() => _ordering = false);
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of Media Team?'),
        content: const Text(
          'You can sign in again with the same email address and password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      debugPrint('Media Team sign-out failed: $error');
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Team'),
        actions: [
          if (_accessError == null)
            IconButton(
              tooltip: 'Refresh archive',
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: _accessError == null && !_checkingAccess
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New record'),
            )
          : null,
      body: _checkingAccess
          ? const Center(child: CircularProgressIndicator())
          : _accessError != null
          ? _DashboardStateCard(
              icon: Icons.lock_outline_rounded,
              title: 'Media Team access unavailable',
              message: _accessError!,
              primaryLabel: 'Try again',
              onPrimary: _start,
              secondaryLabel: 'Sign out',
              onSecondary: _signOut,
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                    children: [
                      _DashboardHero(
                        displayName: widget.displayName,
                        published: _publishedCount,
                        drafts: _draftCount,
                        totalPhotos: _entries.fold<int>(
                          0,
                          (sum, entry) => sum + entry.photos.length,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SearchField(controller: _search),
                      const SizedBox(height: 12),
                      _StatusFilters(
                        status: _status,
                        published: _publishedCount,
                        drafts: _draftCount,
                        onChanged: (value) => setState(() => _status = value),
                      ),
                      if (_categories.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _CategoryDropdown(
                          categories: _categories,
                          value: _category,
                          onChanged: (value) =>
                              setState(() => _category = value),
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(44),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_loadError != null)
                        _DashboardStateCard(
                          icon: Icons.cloud_off_outlined,
                          title: 'The archive could not be loaded',
                          message: _loadError!,
                          primaryLabel: 'Try again',
                          onPrimary: () => _start(),
                        )
                      else if (_entries.isEmpty)
                        _DashboardStateCard(
                          icon: Icons.collections_bookmark_outlined,
                          title: 'Start the congregation archive',
                          message: 'Create the first record for pastors, office bearers, milestones or events. Saved drafts stay hidden from members until you publish them.',
                          primaryLabel: 'Create first record',
                          onPrimary: _create,
                        )
                      else if (_filtered.isEmpty)
                        const _DashboardStateCard(
                          icon: Icons.search_off_rounded,
                          title: 'No records match',
                          message: 'Try a different search, category or status filter.',
                        )
                      else ...[
                        Row(
                          children: [
                            Text(
                              '${_filtered.length} ${_filtered.length == 1 ? 'record' : 'records'}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            if (_ordering)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (var index = 0; index < _filtered.length; index++)
                          Builder(
                            builder: (context) {
                              final entry = _filtered[index];
                              final globalIndex = _entries.indexWhere(
                                (item) => item.id == entry.id,
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _DashboardEntryCard(
                                  entry: entry,
                                  canMoveEarlier:
                                      _reorderAvailable &&
                                      !_ordering &&
                                      globalIndex > 0,
                                  canMoveLater:
                                      _reorderAvailable &&
                                      !_ordering &&
                                      globalIndex >= 0 &&
                                      globalIndex < _entries.length - 1,
                                  onEdit: () => _edit(entry),
                                  onPreview: () => _preview(entry),
                                  onTogglePublished: () =>
                                      _togglePublished(entry),
                                  onDelete: () => _delete(entry),
                                  onMoveEarlier: () => _move(entry, -1),
                                  onMoveLater: () => _move(entry, 1),
                                ),
                              );
                            },
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.displayName,
    required this.published,
    required this.drafts,
    required this.totalPhotos,
  });

  final String displayName;
  final int published;
  final int drafts;
  final int totalPhotos;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: AppDecor.heroGradient(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: AppDecor.softShadow(context),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            top: -26,
            child: Icon(
              Icons.perm_media_rounded,
              size: 128,
              color: Colors.white.withValues(alpha: .08),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MEDIA TEAM WORKSPACE',
                style: TextStyle(
                  color: AppColors.goldLight,
                  fontSize: 9.5,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Welcome, ${displayName.isEmpty ? 'Media Team' : displayName}',
                style: const TextStyle(
                  fontFamily: 'SourceSerif4',
                  color: Colors.white,
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Care for the congregation story. Draft privately, publish when ready, and keep every photograph in order.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  height: 1.5,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _HeroStat(value: '$published', label: 'Published'),
                  _HeroStat(value: '$drafts', label: 'Drafts'),
                  _HeroStat(value: '$totalPhotos', label: 'Photographs'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .72),
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search titles, people and stories',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: controller.clear,
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.status,
    required this.published,
    required this.drafts,
    required this.onChanged,
  });

  final String status;
  final int published;
  final int drafts;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final items = [
      ('all', 'All', published + drafts),
      ('published', 'Published', published),
      ('draft', 'Drafts', drafts),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in items)
          _FilterChipButton(
            label: '${item.$2}  ${item.$3}',
            selected: status == item.$1,
            color: colors.primary,
            onTap: () => onChanged(item.$1),
          ),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? color : colors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? color : colors.outlineVariant),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.onPrimary : colors.onSurface,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  const _CategoryDropdown({
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  final List<String> categories;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = categories.contains(value) ? value : 'All';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selected,
          isExpanded: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.expand_more_rounded),
          items: [
            const DropdownMenuItem(value: 'All', child: Text('All categories')),
            for (final category in categories)
              DropdownMenuItem(value: category, child: Text(category)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _DashboardEntryCard extends StatelessWidget {
  const _DashboardEntryCard({
    required this.entry,
    required this.canMoveEarlier,
    required this.canMoveLater,
    required this.onEdit,
    required this.onPreview,
    required this.onTogglePublished,
    required this.onDelete,
    required this.onMoveEarlier,
    required this.onMoveLater,
  });

  final CongregationHistoryEntry entry;
  final bool canMoveEarlier;
  final bool canMoveLater;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback onTogglePublished;
  final VoidCallback onDelete;
  final VoidCallback onMoveEarlier;
  final VoidCallback onMoveLater;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = entry.isPublished ? colors.secondary : colors.tertiary;
    final biography = entry.biography?.trim() ?? '';
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 92,
                height: 96,
                child: HistoryImage(
                  url: entry.coverUrl,
                  borderRadius: BorderRadius.circular(14),
                  placeholderIcon: historyCategoryIcon(entry.category),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              HistoryCategoryChip(
                                category: entry.category,
                                compact: true,
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: .13),
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.pill,
                                  ),
                                ),
                                child: Text(
                                  entry.isPublished ? 'PUBLISHED' : 'DRAFT',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: .7,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Record actions',
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                onEdit();
                              case 'preview':
                                onPreview();
                              case 'publish':
                                onTogglePublished();
                              case 'earlier':
                                onMoveEarlier();
                              case 'later':
                                onMoveLater();
                              case 'delete':
                                onDelete();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(Icons.edit_outlined, size: 19),
                                title: Text('Edit record'),
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'preview',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.visibility_outlined,
                                  size: 19,
                                ),
                                title: Text('Preview'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'publish',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  entry.isPublished
                                      ? Icons.unpublished_outlined
                                      : Icons.publish_rounded,
                                  size: 19,
                                ),
                                title: Text(
                                  entry.isPublished
                                      ? 'Unpublish'
                                      : 'Publish record',
                                ),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'earlier',
                              enabled: canMoveEarlier,
                              child: const ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 19,
                                ),
                                title: Text('Move earlier'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'later',
                              enabled: canMoveLater,
                              child: const ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 19,
                                ),
                                title: Text('Move later'),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 19,
                                  color: colors.error,
                                ),
                                title: Text(
                                  'Delete record',
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'SourceSerif4',
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (entry.peopleLine.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        entry.peopleLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (biography.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        biography,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (entry.yearsLabel != null)
                          _MetaLabel(
                            icon: Icons.calendar_today_outlined,
                            text: entry.yearsLabel!,
                          ),
                        _MetaLabel(
                          icon: Icons.photo_library_outlined,
                          text: '${entry.photos.length} photos',
                        ),
                        _MetaLabel(
                          icon: Icons.sort_rounded,
                          text: 'Order ${entry.displayOrder}',
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
}

class _MetaLabel extends StatelessWidget {
  const _MetaLabel({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _DashboardStateCard extends StatelessWidget {
  const _DashboardStateCard({
    required this.icon,
    required this.title,
    required this.message,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

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
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, size: 26, color: colors.onSecondaryContainer),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
            ),
            if (primaryLabel != null || secondaryLabel != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (primaryLabel != null)
                    FilledButton.icon(
                      onPressed: onPrimary,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(primaryLabel!),
                    ),
                  if (secondaryLabel != null)
                    OutlinedButton(
                      onPressed: onSecondary,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
