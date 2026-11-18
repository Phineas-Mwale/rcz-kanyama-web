import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_accounts_view.dart';
import 'widgets/admin_widgets.dart';

enum _Section { overview, secretariat, mediaTeam }

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  bool _checkingOwner = true;
  bool _isOwner = false;
  bool _loading = false;
  String? _error;
  _Section _section = _Section.overview;
  String? _accountsFilter;

  List<Map<String, dynamic>> _secretariat = const [];
  List<Map<String, dynamic>> _mediaTeam = const [];
  Map<String, dynamic> _secretariatStats = const {};
  Map<String, dynamic> _mediaTeamStats = const {};
  List<Map<String, dynamic>> _recentSermons = const [];
  int? _sermonCount;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    unawaited(_verifyOwner());
  }

  Future<void> _verifyOwner() async {
    try {
      final result = await _client.rpc('is_owner_admin');
      if (!mounted) return;
      final owner = result == true;
      setState(() {
        _isOwner = owner;
        _checkingOwner = false;
      });
      if (owner) unawaited(_load());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isOwner = false;
        _checkingOwner = false;
        _error = 'Owner verification failed. ${_friendly(error)}';
      });
    }
  }

  Future<void> _load() async {
    if (!_isOwner) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.rpc('admin_list_secretariat'),
        _client.rpc('admin_list_media_team'),
        _client.rpc('admin_secretariat_stats'),
        _client.rpc('admin_media_team_stats'),
      ]);
      if (!mounted) return;
      setState(() {
        _secretariat = _asListOfMaps(results[0]);
        _mediaTeam = _asListOfMaps(results[1]);
        _secretariatStats = _asMap(results[2]);
        _mediaTeamStats = _asMap(results[3]);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendly(error);
      });
      return;
    }
    unawaited(_loadSermons());
  }

  /// Sermon figures come from the existing `sermons` table. A failure here is
  /// not fatal: the overview simply omits the sermon information.
  Future<void> _loadSermons() async {
    try {
      final rows = await _client
          .from('sermons')
          .select('id,title,published_at,created_at')
          .order('created_at', ascending: false)
          .limit(1000);
      if (!mounted) return;
      final list = _asListOfMaps(rows);
      setState(() {
        _sermonCount = list.length;
        _recentSermons = list.take(5).toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sermonCount = null;
        _recentSermons = const [];
      });
    }
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    }
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  int _stat(Map<String, dynamic> stats, String key) {
    final value = stats[key];
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? 0}') ?? 0;
  }

  int _total(Map<String, dynamic> stats) => [
        'pending',
        'active',
        'inactive',
        'rejected',
        'legacy',
      ].fold<int>(0, (sum, key) => sum + _stat(stats, key));

  String _friendly(Object error) {
    if (error is PostgrestException) {
      final msg = error.message.toLowerCase();
      if (msg.contains('not authorised') || error.code == '42501') {
        return 'This account is not authorised to perform this action.';
      }
      if (error.message.trim().isNotEmpty) return error.message.trim();
    }
    return 'Something went wrong. Check your connection and try again.';
  }

  // ---------------------------------------------------------------- actions

  Future<void> _confirmAndRun({
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() action,
    required String successMessage,
    bool destructive = false,
  }) async {
    final colors = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: colors.onError,
                  )
                : null,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(successMessage)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendly(error))));
    }
  }

  Future<String?> _chooseSecretariatRole(String name) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        var role = 'SEC';
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: const Text('Approve Secretariat account'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose the role to assign to $name.'),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: role,
                  onChanged: (value) => setLocal(() => role = value ?? role),
                  child: const Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('SEC'),
                        value: 'SEC',
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        title: Text('VSEC'),
                        value: 'VSEC',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, role),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );
  }

  String _nameOf(Map<String, dynamic> row) {
    final name = row['display_name']?.toString().trim() ?? '';
    return name.isEmpty ? 'this account' : name;
  }

  Future<void> _secretariatAction(
    AdminAccountAction action,
    Map<String, dynamic> row,
  ) async {
    final userId = row['user_id']?.toString();
    if (userId == null) return;
    final name = _nameOf(row);
    switch (action) {
      case AdminAccountAction.approve:
        final role = await _chooseSecretariatRole(name);
        if (role == null || !mounted) return;
        await _confirmAndRun(
          title: 'Approve account?',
          message: 'This will activate the Secretariat account for $name '
              'with the role $role.',
          confirmLabel: 'Approve',
          action: () => _client.rpc(
            'admin_approve_secretariat',
            params: {'p_user_id': userId, 'p_role': role},
          ),
          successMessage: 'Secretariat account approved.',
        );
      case AdminAccountAction.reject:
        await _confirmAndRun(
          title: 'Reject account?',
          message: 'This will mark the account for $name as rejected and '
              'keep it inactive.',
          confirmLabel: 'Reject',
          destructive: true,
          action: () => _client
              .rpc('admin_reject_secretariat', params: {'p_user_id': userId}),
          successMessage: 'Secretariat account rejected.',
        );
      case AdminAccountAction.deactivate:
        await _confirmAndRun(
          title: 'Deactivate account?',
          message: 'This will disable Secretariat access for $name.',
          confirmLabel: 'Deactivate',
          destructive: true,
          action: () => _client.rpc('admin_deactivate_secretariat',
              params: {'p_user_id': userId}),
          successMessage: 'Secretariat account deactivated.',
        );
      case AdminAccountAction.reactivate:
        await _confirmAndRun(
          title: 'Reactivate account?',
          message: 'This will restore Secretariat access for $name.',
          confirmLabel: 'Reactivate',
          action: () => _client.rpc('admin_reactivate_secretariat',
              params: {'p_user_id': userId}),
          successMessage: 'Secretariat account reactivated.',
        );
    }
  }

  Future<void> _mediaTeamAction(
    AdminAccountAction action,
    Map<String, dynamic> row,
  ) async {
    final userId = row['user_id']?.toString();
    if (userId == null) return;
    final name = _nameOf(row);
    switch (action) {
      case AdminAccountAction.approve:
        await _confirmAndRun(
          title: 'Approve Media Team account?',
          message: 'This will activate Media Team access for $name.',
          confirmLabel: 'Approve',
          action: () => _client
              .rpc('admin_approve_media_team', params: {'p_user_id': userId}),
          successMessage: 'Media Team account approved.',
        );
      case AdminAccountAction.reject:
        await _confirmAndRun(
          title: 'Reject Media Team account?',
          message: 'This will mark the account for $name as rejected and '
              'keep it inactive.',
          confirmLabel: 'Reject',
          destructive: true,
          action: () => _client
              .rpc('admin_reject_media_team', params: {'p_user_id': userId}),
          successMessage: 'Media Team account rejected.',
        );
      case AdminAccountAction.deactivate:
        await _confirmAndRun(
          title: 'Deactivate Media Team account?',
          message: 'This will disable Media Team access for $name.',
          confirmLabel: 'Deactivate',
          destructive: true,
          action: () => _client.rpc('admin_deactivate_media_team',
              params: {'p_user_id': userId}),
          successMessage: 'Media Team account deactivated.',
        );
      case AdminAccountAction.reactivate:
        await _confirmAndRun(
          title: 'Reactivate Media Team account?',
          message: 'This will restore Media Team access for $name.',
          confirmLabel: 'Reactivate',
          action: () => _client.rpc('admin_reactivate_media_team',
              params: {'p_user_id': userId}),
          successMessage: 'Media Team account reactivated.',
        );
    }
  }

  // ------------------------------------------------------------------ views

  void _go(_Section section, {String? filter}) {
    setState(() {
      _section = section;
      _accountsFilter = filter;
    });
  }

  static const _destinations = <(_Section, String, IconData, IconData)>[
    (_Section.overview, 'Overview', Icons.dashboard_outlined,
        Icons.dashboard_rounded),
    (_Section.secretariat, 'Secretariat', Icons.badge_outlined,
        Icons.badge_rounded),
    (_Section.mediaTeam, 'Media Team', Icons.video_library_outlined,
        Icons.video_library_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
        actions: [
          if (_isOwner)
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: _checkingOwner
          ? const Center(child: CircularProgressIndicator())
          : !_isOwner
              ? (_error != null
                  ? AdminErrorState(message: _error!, onRetry: () {
                      setState(() {
                        _checkingOwner = true;
                        _error = null;
                      });
                      unawaited(_verifyOwner());
                    })
                  : AdminNotAuthorised(
                      onBack: () => Navigator.of(context).pop()))
              : _loading && _secretariat.isEmpty && _mediaTeam.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? AdminErrorState(message: _error!, onRetry: _load)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 900;
                            final content = _buildSection(
                              compact: constraints.maxWidth < 640,
                            );
                            if (wide) {
                              return Row(
                                children: [
                                  _Sidebar(
                                    selected: _section,
                                    onSelect: _go,
                                  ),
                                  VerticalDivider(
                                    width: 1,
                                    color: colors.outlineVariant,
                                  ),
                                  Expanded(child: content),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                Expanded(child: content),
                                NavigationBar(
                                  selectedIndex: _Section.values
                                      .indexOf(_section),
                                  onDestinationSelected: (i) =>
                                      _go(_Section.values[i]),
                                  destinations: [
                                    for (final d in _destinations)
                                      NavigationDestination(
                                        icon: Icon(d.$3),
                                        selectedIcon: Icon(d.$4),
                                        label: d.$2,
                                      ),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
    );
  }

  Widget _buildSection({required bool compact}) {
    final Widget body;
    switch (_section) {
      case _Section.overview:
        body = _Overview(
          compact: compact,
          secretariatStats: _secretariatStats,
          mediaTeamStats: _mediaTeamStats,
          secretariatTotal: _total(_secretariatStats),
          mediaTeamTotal: _total(_mediaTeamStats),
          sermonCount: _sermonCount,
          recentSermons: _recentSermons,
          recentSecretariat: _recent(_secretariat),
          recentMediaTeam: _recent(_mediaTeam),
          stat: _stat,
          onReview: _go,
        );
      case _Section.secretariat:
        body = AdminAccountsView(
          key: ValueKey('sec-$_accountsFilter'),
          title: 'Secretariat accounts',
          description:
              'Approve, reject and manage access for Secretariat officers.',
          accounts: _secretariat,
          showRole: true,
          initialFilter: _accountsFilter,
          onAction: _secretariatAction,
        );
      case _Section.mediaTeam:
        body = AdminAccountsView(
          key: ValueKey('media-$_accountsFilter'),
          title: 'Media Team accounts',
          description: 'Approve, reject and manage access for Media Team '
              'members.',
          accounts: _mediaTeam,
          showRole: false,
          initialFilter: _accountsFilter,
          onAction: _mediaTeamAction,
        );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(compact ? 16 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: body,
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _recent(List<Map<String, dynamic>> rows) {
    final dated = rows
        .where((row) => DateTime.tryParse('${row['created_at']}') != null)
        .toList();
    dated.sort((a, b) => DateTime.parse('${b['created_at']}')
        .compareTo(DateTime.parse('${a['created_at']}')));
    return dated.take(5).toList(growable: false);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.onSelect,
  });

  final _Section selected;
  final void Function(_Section section, {String? filter}) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 236,
      child: ColoredBox(
        color: colors.surfaceContainerLow,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'WORKSPACE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      letterSpacing: 1.4,
                    ),
              ),
            ),
            for (final d in _AdminDashboardPageState._destinations)
              ListTile(
                dense: true,
                selected: selected == d.$1,
                selectedTileColor: colors.secondaryContainer,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kAdminRadius),
                ),
                leading: Icon(selected == d.$1 ? d.$4 : d.$3, size: 20),
                title: Text(d.$2),
                onTap: () => onSelect(d.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.compact,
    required this.secretariatStats,
    required this.mediaTeamStats,
    required this.secretariatTotal,
    required this.mediaTeamTotal,
    required this.sermonCount,
    required this.recentSermons,
    required this.recentSecretariat,
    required this.recentMediaTeam,
    required this.stat,
    required this.onReview,
  });

  final bool compact;
  final Map<String, dynamic> secretariatStats;
  final Map<String, dynamic> mediaTeamStats;
  final int secretariatTotal;
  final int mediaTeamTotal;
  final int? sermonCount;
  final List<Map<String, dynamic>> recentSermons;
  final List<Map<String, dynamic>> recentSecretariat;
  final List<Map<String, dynamic>> recentMediaTeam;
  final int Function(Map<String, dynamic>, String) stat;
  final void Function(_Section section, {String? filter}) onReview;

  @override
  Widget build(BuildContext context) {
    final secPending = stat(secretariatStats, 'pending');
    final mediaPending = stat(mediaTeamStats, 'pending');

    final metrics = <Widget>[
      AdminMetric(
        label: 'Secretariat accounts',
        value: '$secretariatTotal',
        caption: '${stat(secretariatStats, 'active')} active',
      ),
      AdminMetric(
        label: 'Media Team accounts',
        value: '$mediaTeamTotal',
        caption: '${stat(mediaTeamStats, 'active')} active',
      ),
      AdminMetric(
        label: 'Awaiting approval',
        value: '${secPending + mediaPending}',
        caption: 'Across both teams',
      ),
      if (sermonCount != null)
        AdminMetric(
          label: 'Sermons',
          value: '$sermonCount',
          caption: 'In the library',
        ),
    ];

    final recentAccounts = [
      ...recentSecretariat.map((r) => (r, 'Secretariat')),
      ...recentMediaTeam.map((r) => (r, 'Media Team')),
    ]..sort((a, b) => DateTime.parse('${b.$1['created_at']}')
        .compareTo(DateTime.parse('${a.$1['created_at']}')));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionHeader(
          title: 'Overview',
          description: 'The current state of the congregationâ€™s digital '
              'platform.',
        ),
        const SizedBox(height: 20),
        AdminPanel(
          title: 'Needs attention',
          child: (secPending + mediaPending) == 0
              ? AdminEmpty(
                  icon: Icons.check_circle_outline_rounded,
                  message: 'No accounts are waiting for approval.',
                )
              : Column(
                  children: [
                    if (secPending > 0)
                      _TaskRow(
                        text: '$secPending Secretariat '
                            '${secPending == 1 ? 'account' : 'accounts'} '
                            'awaiting approval',
                        onReview: () =>
                            onReview(_Section.secretariat, filter: 'pending'),
                      ),
                    if (mediaPending > 0)
                      _TaskRow(
                        text: '$mediaPending Media Team '
                            '${mediaPending == 1 ? 'account' : 'accounts'} '
                            'awaiting approval',
                        onReview: () =>
                            onReview(_Section.mediaTeam, filter: 'pending'),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760
                ? (metrics.length > 4 ? 4 : metrics.length)
                : 2;
            const gap = 12.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final metric in metrics)
                  SizedBox(width: width, child: metric),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final accountsPanel = AdminPanel(
              title: 'Recent registrations',
              padding: EdgeInsets.zero,
              child: recentAccounts.isEmpty
                  ? AdminEmpty(
                      icon: Icons.person_outline_rounded,
                      message: 'No registrations to show.',
                    )
                  : Column(
                      children: [
                        for (final (row, team) in recentAccounts.take(5))
                          _ActivityRow(
                            title: row['display_name']?.toString() ??
                                'Unnamed',
                            subtitle: team,
                            trailing: adminDateLabel(row['created_at']),
                          ),
                      ],
                    ),
            );
            final sermonsPanel = AdminPanel(
              title: 'Recently added sermons',
              padding: EdgeInsets.zero,
              child: recentSermons.isEmpty
                  ? AdminEmpty(
                      icon: Icons.play_circle_outline_rounded,
                      message: 'No sermons to show.',
                    )
                  : Column(
                      children: [
                        for (final row in recentSermons)
                          _ActivityRow(
                            title: row['title']?.toString() ?? 'Sermon',
                            subtitle: 'Added to the library',
                            trailing: adminDateLabel(row['created_at']),
                          ),
                      ],
                    ),
            );
            if (constraints.maxWidth >= 760) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: accountsPanel),
                  const SizedBox(width: 12),
                  Expanded(child: sermonsPanel),
                ],
              );
            }
            return Column(
              children: [
                accountsPanel,
                const SizedBox(height: 12),
                sermonsPanel,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.text, required this.onReview});
  final String text;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          TextButton(onPressed: onReview, child: const Text('Review')),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: text.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trailing,
              style:
                  text.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

