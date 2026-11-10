import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../bible_service.dart';
import '../data/bible_catalog_service.dart';
import 'bible_reader_pages.dart';

const _bibleInk = Color(0xFF172B4D);
const _bibleGold = Color(0xFFE5B85C);

class BibleHomePage extends StatefulWidget {
  const BibleHomePage({super.key});

  @override
  State<BibleHomePage> createState() => _BibleHomePageState();
}

class _BibleHomePageState extends State<BibleHomePage> {
  late final Future<BibleService> _serviceFuture = BibleService.create(
    Supabase.instance.client,
  );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BibleService>(
      future: _serviceFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _BibleErrorPage(
            message: 'The Bible library could not be opened on this device. Please try again.',
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
  const _BibleErrorPage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('The Bible')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, size: 52),
            const SizedBox(height: 16),
            const Text(
              'We couldn’t open the Bible library',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
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

  @override
  void initState() {
    super.initState();
    _refresh();
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
        translation.sha256 == null){
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
      if (!mounted){
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download could not be completed: $error')),
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
        title: const Text(
          'The Bible',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh library',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
          children: [
            _BibleHeroCard(installedCount: _installed.length),
            const SizedBox(height: 22),
            Row(
              children: [
                Text(
                  'Your Bible library',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (!_loading)
                  Text(
                    '${_installed.length} downloaded',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
                final isInstalling = _installingId == translation.id;
                return _TranslationCard(
                  translation: translation,
                  installed: installed,
                  installing: isInstalling,
                  progress: _progress,
                  onRead: () => _open(translation),
                  onDownload: () => _install(translation),
                  onRemove: () => _remove(translation),
                );
              }),
            const SizedBox(height: 10),
            Card(
              color: colors.surfaceContainerLow,
              child: const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.wifi_off_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Read anywhere',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Once a translation is downloaded, its books and chapters are stored on this device for offline reading.',
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
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_bibleInk, Color(0xFF344F78), Color(0xFF526B8A)],
        ),
        boxShadow: [
          BoxShadow(
            color: _bibleInk.withValues(alpha: .18),
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
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'SCRIPTURE • EVERY DAY',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Grow deeper\nin the Word.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Read, reflect and carry Scripture with you wherever life takes you.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .82),
                  height: 1.45,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(
                    Icons.download_done_rounded,
                    color: _bibleGold,
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

class _TranslationCard extends StatelessWidget {
  const _TranslationCard({
    required this.translation,
    required this.installed,
    required this.installing,
    required this.progress,
    required this.onRead,
    required this.onDownload,
    required this.onRemove,
  });
  final BibleCatalogTranslation translation;
  final bool installed;
  final bool installing;
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
                                  ? const Color(0xFF2E9D68)
                                  : available
                                  ? _bibleGold
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
                                  ? const Color(0xFF258657)
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
                        onPressed: onDownload,
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
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 34),
          const SizedBox(height: 8),
          const Text(
            'Could not load the Bible library',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    ),
  );
}
