import 'package:flutter/material.dart';

import 'widgets/admin_widgets.dart';

enum AdminAccountAction { approve, reject, deactivate, reactivate }

/// Searchable, filterable list of Secretariat or Media Team accounts.
class AdminAccountsView extends StatefulWidget {
  const AdminAccountsView({
    required this.title,
    required this.description,
    required this.accounts,
    required this.showRole,
    required this.onAction,
    this.initialFilter,
    super.key,
  });

  final String title;
  final String description;
  final List<Map<String, dynamic>> accounts;
  final bool showRole;
  final String? initialFilter;
  final Future<void> Function(AdminAccountAction, Map<String, dynamic>)
      onAction;

  @override
  State<AdminAccountsView> createState() => _AdminAccountsViewState();
}

class _AdminAccountsViewState extends State<AdminAccountsView> {
  final _search = TextEditingController();
  String? _filter;

  static const _filters = <String?, String>{
    null: 'All',
    'pending': 'Pending',
    'active': 'Active',
    'inactive': 'Inactive',
    'rejected': 'Rejected',
  };

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _statusOf(Map<String, dynamic> row) =>
      row['status']?.toString() ?? 'legacy';

  List<Map<String, dynamic>> get _visible {
    final query = _search.text.trim().toLowerCase();
    return widget.accounts.where((row) {
      if (_filter != null && _statusOf(row) != _filter) return false;
      if (query.isEmpty) return true;
      final haystack = [
        row['display_name'],
        row['email'],
        row['phone'],
        row['role'],
      ].map((value) => value?.toString().toLowerCase() ?? '').join(' ');
      return haystack.contains(query);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionHeader(
          title: widget.title,
          description: widget.description,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search by name, email or phone',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in _filters.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _filter == entry.key,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _filter = entry.key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '${rows.length} of ${widget.accounts.length} accounts',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        AdminPanel(
          padding: EdgeInsets.zero,
          child: rows.isEmpty
              ? AdminEmpty(
                  icon: Icons.person_search_outlined,
                  message: widget.accounts.isEmpty
                      ? 'No accounts have been registered yet.'
                      : 'No accounts match the current search or filter.',
                )
              : Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      if (i > 0)
                        Divider(height: 1, color: colors.outlineVariant),
                      _AccountRow(
                        row: rows[i],
                        showRole: widget.showRole,
                        onAction: widget.onAction,
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.row,
    required this.showRole,
    required this.onAction,
  });

  final Map<String, dynamic> row;
  final bool showRole;
  final Future<void> Function(AdminAccountAction, Map<String, dynamic>)
      onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = (row['display_name']?.toString().trim().isNotEmpty ?? false)
        ? row['display_name'].toString().trim()
        : 'Unnamed';
    final status = row['status']?.toString();
    final isActive = row['is_active'] == true;
    final role = row['role']?.toString();
    final details = [
      row['email'],
      row['phone'],
    ]
        .map((value) => value?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .join('  Â·  ');
    final registered = adminDateLabel(row['created_at']);

    final actions = <(AdminAccountAction, String, bool)>[
      if (!isActive) (AdminAccountAction.approve, 'Approve', true),
      if (isActive) (AdminAccountAction.deactivate, 'Deactivate', false),
      if (!isActive && status != 'rejected')
        (AdminAccountAction.reject, 'Reject', false),
      if (status == 'rejected' || status == 'inactive')
        (AdminAccountAction.reactivate, 'Reactivate', true),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 640;
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                details,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AdminStatus(status: status),
                if (showRole && role != null && role.isNotEmpty)
                  Text('Role: $role',
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
                if (registered.isNotEmpty)
                  Text('Registered $registered',
                      style: text.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
          ],
        );

        Widget buttons() {
          if (wide) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (action, label, primary) in actions)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: primary
                        ? FilledButton.tonal(
                            onPressed: () => onAction(action, row),
                            child: Text(label),
                          )
                        : OutlinedButton(
                            onPressed: () => onAction(action, row),
                            child: Text(label),
                          ),
                  ),
              ],
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (action, label, primary) in actions)
                  primary
                      ? FilledButton.tonal(
                          onPressed: () => onAction(action, row),
                          child: Text(label),
                        )
                      : OutlinedButton(
                          onPressed: () => onAction(action, row),
                          child: Text(label),
                        ),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [Expanded(child: info), buttons()],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [info, buttons()],
                ),
        );
      },
    );
  }
}

