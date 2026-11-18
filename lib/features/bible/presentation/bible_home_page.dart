import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../theme/app_theme.dart';
import '../bible_service.dart';
import '../data/bible_catalog_service.dart';
import '../data/bible_download_manager.dart';
import 'bible_bookmarks_page.dart';
import 'bible_reader_pages.dart';
import 'bible_search_page.dart';

class BibleHomePage extends StatefulWidget {
  const BibleHomePage({super.key});

  @override
  State<BibleHomePage> createState() => _BibleHomePageState();
}

class _BibleHomePageState extends State<BibleHomePage> {
  late Future<BibleService> _serviceFuture = BibleService.create(
    Supabase.instance.client,
  );

  void _retry() {
    setState(() {
      _serviceFuture = BibleService.create(Supabase.instance.client);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BibleService>(
      future: _serviceFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BibleErrorPage(
            message: 'The Bible library could not be opened on this device. Please try again.',
            onRetry: _retry,
          );
        }
        if (!snapshot.hasData) return const _BibleLoadingPage();
        return _BibleLibraryView(service: snapshot.data!);
      },
    );
  }
}

class _BibleLoadingPage extends StatelessWidget {
  const _BibleLoadingPage();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('The Bible')),
    body: const Center(child: CircularProgressIndicator()),
  );
}

class _BibleErrorPage extends StatelessWidget {
  const _BibleErrorPage({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('The Bible')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 29,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'We couldn’t open the Bible library',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Try again'),
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

class _BibleLibraryView extends StatefulWidget {
  const _BibleLibraryView({required this.service});
  final BibleService service;

  @override
  State<_BibleLibraryView> createState() => _BibleLibraryViewState();
}

class _BibleLibraryViewState extends State<_BibleLibraryView> {
  List<BibleCatalogTranslation> _translations = [];
  List<String> _installed = [];
  bool _loading = true;
  String? _error;
  String? _installingId;
  double _progress = 0;
  BibleDownloadManager? _downloads;
  int _lastBackgroundCompletion = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    unawaited(_listenToDownloads());
  }

  @override
  void dispose() {
    _downloads?.removeListener(_onDownloadsChanged);
    super.dispose();
  }

  Future<void> _listenToDownloads() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final manager = await BibleDownloadManager.create(
        client: Supabase.instance.client,
        preferences: preferences,
      );
      if (!mounted) return;
      manager.addListener(_onDownloadsChanged);
      setState(() => _downloads = manager);
      unawaited(manager.startIfNeeded());
    } catch (error) {
      debugPrint('Bible download manager could not start: $error');
    }
  }

  void _onDownloadsChanged() {
    if (!mounted) return;
    final manager = _downloads;
    if (manager != null &&
        manager.completed != _lastBackgroundCompletion &&
        !manager.running) {
      _lastBackgroundCompletion = manager.completed;
      unawaited(_reloadInstalled());
    }
    setState(() {});
  }

  Future<void> _reloadInstalled() async {
    try {
      final installedIds = await widget.service.store.installedTranslationIds();
      final localTranslations = <BibleCatalogTranslation>[];
      for (final id in installedIds) {
        try {
          final manifest = await widget.service.repository.translation(id);
          localTranslations.add(
            BibleCatalogTranslation(
              id: manifest.id,
              name: manifest.name,
              shortName: manifest.shortName,
              languageCode: manifest.languageCode,
              status: 'available',
              version: manifest.version,
              licenseLabel: manifest.license,
            ),
          );
        } catch (_) {
          // Keep the rest of the library usable if one manifest is damaged.
        }
      }
      if (!mounted) return;
      setState(() {
        _installed = installedIds;
        final merged = <String, BibleCatalogTranslation>{
          for (final translation in _translations) translation.id: translation,
          for (final translation in localTranslations)
            translation.id: translation,
        };
        _translations = merged.values.toList(growable: false);
      });
    } catch (error) {
      debugPrint('Installed Bible refresh failed: $error');
    }
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // Load the on-device library first. This must never depend on Supabase
    // being reachable: downloaded translations are meant to work offline.
    try {
      final installedIds = await widget.service.store.installedTranslationIds();
      final localTranslations = <BibleCatalogTranslation>[];

      for (final id in installedIds) {
        try {
          final manifest = await widget.service.repository.translation(id);
          localTranslations.add(
            BibleCatalogTranslation(
              id: manifest.id,
              name: manifest.name,
              shortName: manifest.shortName,
              languageCode: manifest.languageCode,
              status: 'available',
              version: manifest.version,
              licenseLabel: manifest.license,
            ),
          );
        } catch (_) {
          // One damaged/missing manifest should not hide other installed
          // translations. The reader will report a friendly issue if opened.
        }
      }

      if (!mounted) return;
      setState(() {
        _installed = installedIds;
        _translations = localTranslations;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installed = [];
        _translations = [];
        _error =
            'Your downloaded Bible library could not be opened on this device.';
        _loading = false;
      });
      return;
    }

    // Refresh the online catalogue separately. If the device is offline,
    // keep the locally installed translations visible and usable.
    try {
      final onlineTranslations = await widget.service.catalog.fetchCatalog();
      if (!mounted) return;
      final merged = <String, BibleCatalogTranslation>{
        for (final translation in _translations) translation.id: translation,
        for (final translation in onlineTranslations)
          translation.id: translation,
      };
      setState(() {
        _translations = merged.values.toList(growable: false);
      });
    } catch (_) {
      // Expected when offline. Do not expose DNS/Supabase exceptions to users.
    }
  }

  Future<void> _install(BibleCatalogTranslation translation) async {
    if (!translation.isAvailable ||
        translation.packagePath == null ||
        translation.sha256 == null) {
      return;
    }
    if (_downloads?.running ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A Bible download is already in progress. Please wait.',
          ),
        ),
      );
      return;
    }
    if (_installingId != null ||
        _downloads?.activeTranslationId == translation.id) {
      return;
    }
    setState(() {
      _installingId = translation.id;
      _progress = 0;
    });
    try {
      await widget.service.installer.install(
        translationId: translation.id,
        packageUrl: translation.packagePath!,
        expectedSha256: translation.sha256!,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      widget.service.repository.clearCache();
      await _downloads?.allowAutomaticDownload(translation.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _installed = [
          ..._installed.where((id) => id != translation.id),
          translation.id,
        ];
        _installingId = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${translation.shortName} is ready for offline reading.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _installingId = null);
      debugPrint('Manual Bible download failed: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The download could not be completed. Check your connection and free storage, then try again.',
          ),
        ),
      );
    }
  }

  Future<void> _remove(BibleCatalogTranslation translation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${translation.shortName}?'),
        content: const Text(
          'The downloaded Bible will be removed from this device. You can download it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.service.installer.uninstall(translation.id);
    widget.service.repository.clearCache();
    await _downloads?.skipAutomaticDownload(translation.id);
    if (mounted) setState(() => _installed.remove(translation.id));
  }

  void _open(BibleCatalogTranslation translation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BibleBooksPage(
          service: widget.service,
          translationId: translation.id,
          translationName: translation.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('The Bible'),
        actions: [
          IconButton(
            tooltip: 'Search the Bible',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BibleSearchPage(service: widget.service),
              ),
            ),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Bookmarked verses',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BibleBookmarksPage(service: widget.service),
              ),
            ),
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: 'Refresh library',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                _BibleHeroCard(installedCount: _installed.length),
                if (_downloads != null) ...[
                  const SizedBox(height: 14),
                  _BibleDownloadCard(
                    manager: _downloads!,
                    onRetry: () => unawaited(_downloads!.retryFailed()),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Text(
                      'Your Bible library',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (!_loading)
                      Text(
                        '${_installed.length} downloaded',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'Choose a translation and keep the Word close, even when you are offline.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  _ErrorCard(message: _error!, onRetry: _refresh)
                else if (_translations.isEmpty)
                  const _EmptyBibleLibraryCard()
                else
                  ..._translations.map((translation) {
                    final installed = _installed.contains(translation.id);
                    final background =
                        _downloads?.activeTranslationId == translation.id;
                    final isInstalling =
                        _installingId == translation.id || background;
                    final canStartDownload =
                        _installingId == null &&
                        !(_downloads?.running ?? false);
                    return _TranslationCard(
                      translation: translation,
                      installed: installed,
                      installing: isInstalling,
                      canDownload: canStartDownload,
                      progress: background
                          ? _downloads!.activeProgress
                          : _progress,
                      onRead: () => _open(translation),
                      onDownload: () => _install(translation),
                      onRemove: () => _remove(translation),
                    );
                  }),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            Icons.wifi_off_rounded,
                            size: 19,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Read anywhere',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Once a translation is downloaded, its books and chapters are stored on this device for offline reading.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      height: 1.55,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Translation availability depends on content and distribution permissions. Source and attribution notices are retained with each package.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBibleLibraryCard extends StatelessWidget {
  const _EmptyBibleLibraryCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.menu_book_rounded, size: 38, color: colors.primary),
            const SizedBox(height: 10),
            const Text(
              'No Bible translation downloaded yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'You need to download a Bible translation first to access it offline. Connect to the internet to browse and download available translations.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _BibleHeroCard extends StatelessWidget {
  const _BibleHeroCard({required this.installedCount});
  final int installedCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: AppDecor.heroGradient(context),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDeep.withValues(alpha: .18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            top: -24,
            child: Icon(
              Icons.auto_stories_rounded,
              size: 132,
              color: Colors.white.withValues(alpha: .075),
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
                  'SCRIPTURE • EVERY DAY',
                  style: TextStyle(
                    color: AppColors.goldLight,
                    fontSize: 9.5,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Grow deeper\nin the Word.',
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Read, reflect and carry Scripture with you wherever life takes you.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .78),
                  height: 1.45,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.download_done_rounded,
                    color: AppColors.goldLight,
                    size: 18,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$installedCount ${installedCount == 1 ? 'translation' : 'translations'} ready offline',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BibleDownloadCard extends StatelessWidget {
  const _BibleDownloadCard({required this.manager, required this.onRetry});

  final BibleDownloadManager manager;
  final VoidCallback onRetry;

  String get _status {
    if (manager.running) {
      final name = manager.activeTranslationName;
      if (name != null) {
        return 'Downloading $name… ${(manager.activeProgress * 100).round()}%';
      }
      return 'Checking your offline library…';
    }
    final failed = manager.failedTranslationIds.length;
    if (failed > 0) {
      return '$failed ${failed == 1 ? 'translation needs' : 'translations need'} another attempt.';
    }
    return manager.message ??
        'Available translations download quietly when you are online.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.cloud_download_outlined,
                    size: 19,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline downloads',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _status,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                if (manager.running)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      value: manager.activeTranslationName == null
                          ? null
                          : manager.activeProgress,
                    ),
                  )
                else if (manager.failedTranslationIds.isNotEmpty)
                  IconButton(
                    tooltip: 'Retry failed downloads',
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
              ],
            ),
            if (manager.running && manager.activeTranslationName != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(
                  value: manager.activeProgress,
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                manager.total > 0
                    ? '${manager.completed} of ${manager.total} translations ready'
                    : 'Preparing translations',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 4),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: manager.autoDownloadEnabled,
              onChanged: (value) => manager.setAutoDownloadEnabled(value),
              title: Text(
                'Download automatically',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: manager.wifiOnly,
              onChanged: manager.autoDownloadEnabled
                  ? (value) => manager.setWifiOnly(value)
                  : null,
              title: Text(
                'Wi-Fi only',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: manager.autoDownloadEnabled
                      ? colors.onSurface
                      : colors.onSurfaceVariant,
                ),
              ),
              subtitle: Text(
                'Protect mobile data on phones and tablets',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({
    required this.translation,
    required this.installed,
    required this.installing,
    required this.canDownload,
    required this.progress,
    required this.onRead,
    required this.onDownload,
    required this.onRemove,
  });
  final BibleCatalogTranslation translation;
  final bool installed;
  final bool installing;
  final bool canDownload;
  final double progress;
  final VoidCallback onRead;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final available = translation.isAvailable;
    final label = installed
        ? 'AVAILABLE OFFLINE'
        : available
        ? 'READY TO DOWNLOAD'
        : 'COMING SOON';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 54,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      translation.shortName.length > 4
                          ? translation.shortName.substring(0, 3).toUpperCase()
                          : translation.shortName.toUpperCase(),
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translation.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${translation.shortName}  •  ${translation.languageCode.toUpperCase()}',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: installed
                                  ? colors.tertiary
                                  : available
                                  ? colors.secondary
                                  : colors.outline,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: .8,
                              fontWeight: FontWeight.w800,
                              color: installed
                                  ? colors.tertiary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (installed)
                  IconButton(
                    tooltip: 'Remove download',
                    onPressed: onRemove,
                    icon: const Icon(Icons.more_vert_rounded),
                  ),
              ],
            ),
            if (installing) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: LinearProgressIndicator(value: progress, minHeight: 7),
              ),
              const SizedBox(height: 6),
              Text(
                'Preparing your Bible… ${(progress * 100).round()}%',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ] else ...[
              const SizedBox(height: 13),
              SizedBox(
                width: double.infinity,
                child: installed
                    ? FilledButton.icon(
                        onPressed: onRead,
                        icon: const Icon(Icons.menu_book_rounded, size: 18),
                        label: const Text('Open Bible'),
                      )
                    : available
                    ? OutlinedButton.icon(
                        onPressed: canDownload ? onDownload : null,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          'Download${translation.packageBytes == null ? '' : ' • ${(translation.packageBytes! / (1024 * 1024)).toStringAsFixed(1)} MB'}',
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.lock_clock_rounded, size: 18),
                        label: const Text('Coming soon'),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 26,
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Could not load the Bible library',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 14),
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
