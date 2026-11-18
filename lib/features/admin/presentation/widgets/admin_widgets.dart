import 'package:flutter/material.dart';

/// Shared presentation helpers and components for the admin workspace.

const double kAdminRadius = 8;

String adminStatusLabel(String? status) {
  switch (status) {
    case 'pending':
      return 'Pending';
    case 'active':
      return 'Active';
    case 'rejected':
      return 'Rejected';
    case 'inactive':
      return 'Inactive';
    default:
      return 'Legacy';
  }
}

Color adminStatusColor(String? status, ColorScheme colors) {
  switch (status) {
    case 'pending':
      return colors.secondary;
    case 'active':
      return colors.tertiary;
    case 'rejected':
      return colors.error;
    default:
      return colors.onSurfaceVariant;
  }
}

String adminDateLabel(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  if (parsed == null) return '';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

/// Bordered, flat surface used for every panel.
class AdminPanel extends StatelessWidget {
  const AdminPanel({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(kAdminRadius),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          if (title != null) Divider(height: 1, color: colors.outlineVariant),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    required this.title,
    required this.description,
    super.key,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class AdminMetric extends StatelessWidget {
  const AdminMetric({
    required this.label,
    required this.value,
    this.caption,
    super.key,
  });

  final String label;
  final String value;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AdminPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: text.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small status marker: a dot and a label, rather than a filled badge.
class AdminStatus extends StatelessWidget {
  const AdminStatus({required this.status, super.key});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = adminStatusColor(status, colors);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          adminStatusLabel(status),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class AdminEmpty extends StatelessWidget {
  const AdminEmpty({required this.icon, required this.message, super.key});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: colors.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminNotAuthorised extends StatelessWidget {
  const AdminNotAuthorised({required this.onBack, super.key});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 32),
            const SizedBox(height: 12),
            Text('Not authorised',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            const Text(
              'This dashboard is available only to the authorised owner.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onBack, child: const Text('Go back')),
          ],
        ),
      ),
    );
  }
}

class AdminErrorState extends StatelessWidget {
  const AdminErrorState({
    required this.message,
    required this.onRetry,
    super.key,
  });
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 32),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
