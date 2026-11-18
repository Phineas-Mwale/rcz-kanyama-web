import 'dart:async';
import 'dart:convert';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart'
    show FlutterQuillLocalizations;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'supabase_config.dart';
import 'features/bible/data/bible_download_manager.dart';
import 'features/bible/presentation/bible_home_page.dart';
import 'features/congregation_history/presentation/congregation_history_page.dart';
import 'features/media_team/presentation/media_team_access_page.dart';
import 'features/admin/presentation/admin_dashboard_page.dart';
import 'features/notices/notice_read_service.dart';
import 'features/notes/data/notes_repository.dart';
import 'features/notes/domain/note.dart';
import 'features/notes/presentation/note_editor_page.dart';
import 'features/notes/presentation/note_view_page.dart';
import 'theme/app_theme.dart';

const _sections = [
  'A1',
  'A2',
  'A3',
  'B1',
  'B2',
  'B3',
  'C1',
  'C2',
  'C3',
  'D1',
  'D2',
  'D3',
  'E1',
  'E2',
  'F1',
  'F2',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabasePublishableKey,
  );
  final preferences = await SharedPreferences.getInstance();
  runApp(RczKanyamaApp(preferences: preferences));
}

class RczKanyamaApp extends StatefulWidget {
  const RczKanyamaApp({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<RczKanyamaApp> createState() => _RczKanyamaAppState();
}

class _RczKanyamaAppState extends State<RczKanyamaApp> {
  late bool _isDark = widget.preferences.getBool('dark_mode') ?? false;
  late double _textScale =
      widget.preferences.getDouble('reader_font_scale') ?? 1.0;
  late String? _name = widget.preferences.getString('member_name');
  late String? _section = widget.preferences.getString('member_section');
  late String? _phone = widget.preferences.getString('member_phone');

  bool get _hasProfile => _name != null && _section != null && _phone != null;

  @override
  void initState() {
    super.initState();
    if (_hasProfile) {
      unawaited(_syncMember(_name!, _phone!, _section!));
    }
    unawaited(_prepareBibleDownloads());
  }

  Future<void> _prepareBibleDownloads() async {
    try {
      final manager = await BibleDownloadManager.create(
        client: Supabase.instance.client,
        preferences: widget.preferences,
      );
      await manager.startIfNeeded();
    } catch (error) {
      debugPrint('Bible offline preparation could not start: $error');
    }
  }

  Future<void> _saveProfile(String name, String phone, String section) async {
    // Save to the device only after Supabase confirms the profile update.
    await _syncMember(name, phone, section, throwOnFailure: true);

    await widget.preferences.setString('member_name', name);
    await widget.preferences.setString('member_phone', phone);
    await widget.preferences.setString('member_section', section);

    if (!mounted) return;
    setState(() {
      _name = name;
      _phone = phone;
      _section = section;
    });
  }

  Future<void> _syncMember(
    String name,
    String phone,
    String section, {
    bool throwOnFailure = false,
  }) async {
    try {
      final client = Supabase.instance.client;

      // Member profiles use anonymous Supabase authentication.
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }

      // Keep the same device ID so an edit updates the existing member row.
      final deviceId =
          widget.preferences.getString('device_id') ?? const Uuid().v4();

      await widget.preferences.setString('device_id', deviceId);

      await client.rpc(
        'register_member',
        params: {
          'p_device_id': deviceId,
          'p_name': name,
          'p_phone': phone,
          'p_section': section,
          'p_app_version': '1.0.0',
        },
      );

      debugPrint('Member profile synced successfully.');
    } on AuthException catch (error) {
      debugPrint('Member authentication could not sync: ${error.message}');
      if (throwOnFailure) rethrow;
    } on PostgrestException catch (error) {
      debugPrint('Member profile could not sync: ${error.message}');
      if (throwOnFailure) rethrow;
    } catch (error) {
      debugPrint('Member profile could not sync: $error');
      if (throwOnFailure) rethrow;
    }
  }

  void _toggleTheme() {
    final value = !_isDark;
    widget.preferences.setBool('dark_mode', value);
    setState(() => _isDark = value);
  }

  void _setTextScale(double value) {
    widget.preferences.setDouble('reader_font_scale', value);
    setState(() => _textScale = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RCZ - Kanyama',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(_textScale)),
        child: child!,
      ),
      home: _hasProfile
          ? MainShell(
              name: _name!,
              section: _section!,
              phone: _phone!,
              onSaveProfile: _saveProfile,
              preferences: widget.preferences,
              isDark: _isDark,
              onToggleTheme: _toggleTheme,
              onTextScaleChanged: _setTextScale,
            )
          : OnboardingScreen(onComplete: _saveProfile),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComplete, super.key});

  final Future<void> Function(String name, String phone, String section)
  onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _section;
  int _step = 0;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_saving) return;
    if (_step == 0 && _nameController.text.trim().isEmpty) {
      _showMessage('Please enter your name first.');
      return;
    }
    if (_step == 1 &&
        !RegExp(r'^0\d{9}$').hasMatch(_phoneController.text.trim())) {
      _showMessage('Enter a valid 10-digit Zambian number starting with 0.');
      return;
    }
    if (_step == 2 && _section == null) {
      _showMessage('Please choose your section.');
      return;
    }
    if (_step == 2) {
      setState(() => _saving = true);
      try {
        await widget.onComplete(
          _nameController.text.trim(),
          _phoneController.text.trim(),
          _section!,
        );
      } catch (error) {
        debugPrint('Initial member profile could not be saved: $error');
        if (mounted) {
          _showMessage(
            'We could not save your details. Please check your connection and try again.',
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    setState(() => _step++);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _softGlow(Color color) {
    return Container(
      width: 320,
      height: 320,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }

  Widget _stepField(BuildContext context) {
    final isNameStep = _step == 0;
    final isPhoneStep = _step == 1;
    if (isNameStep) {
      return TextField(
        controller: _nameController,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _next(),
        decoration: const InputDecoration(
          labelText: 'Your name',
          hintText: 'e.g. Chanda Mwale',
          prefixIcon: Icon(Icons.person_outline_rounded),
        ),
      );
    }
    if (isPhoneStep) {
      return TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        decoration: const InputDecoration(
          labelText: 'Mobile number',
          hintText: '0971234567',
          prefixIcon: Icon(Icons.phone_outlined),
          counterText: '',
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.75,
      ),
      itemCount: _sections.length,
      itemBuilder: (_, index) {
        final section = _sections[index];
        final selected = _section == section;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.6 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: .22),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _section = section),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (selected) ...[
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: colors.onPrimary,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      section,
                      style: TextStyle(
                        color: selected ? colors.onPrimary : colors.onSurface,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isNameStep = _step == 0;
    final isPhoneStep = _step == 1;
    final heading = isNameStep
        ? 'Welcome home'
        : isPhoneStep
        ? 'Stay connected'
        : 'Find your section';
    final description = isNameStep
        ? 'Tell us how you would like to be greeted.'
        : isPhoneStep
        ? 'Add your Zambian mobile number so the church can reach you.'
        : 'Choose the section you worship with each Sunday.';

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: -140,
            right: -100,
            child: _softGlow(colors.primary.withValues(alpha: .10)),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: _softGlow(AppColors.gold.withValues(alpha: .14)),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 34),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.navy,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: colors.outlineVariant),
                              boxShadow: AppDecor.softShadow(context),
                            ),
                            child: Image.asset(
                              'assets/logo_white.png',
                              errorBuilder: (_, _, _) => Icon(
                                Icons.church_rounded,
                                color: colors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'RCZ KANYAMA',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: colors.primary,
                                        letterSpacing: 2.2,
                                      ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Reformed Church in Zambia',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 38),
                      Row(
                        children: List.generate(3, (index) {
                          final active = index <= _step;
                          return Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 240),
                              height: 5,
                              margin: EdgeInsets.only(
                                right: index == 2 ? 0 : 7,
                              ),
                              decoration: BoxDecoration(
                                color: active
                                    ? colors.primary
                                    : colors.outlineVariant,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 30),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 280),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final offset = Tween<Offset>(
                            begin: const Offset(0, .04),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: offset,
                              child: child,
                            ),
                          );
                        },
                        child: Column(
                          key: ValueKey(_step),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'STEP ${_step + 1} OF 3',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.secondary,
                                    letterSpacing: 1.8,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              heading,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              description,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                            const SizedBox(height: 24),
                            _stepField(context),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      FilledButton(
                        onPressed: _saving ? null : _next,
                        child: _saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onPrimary,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _step == 2 ? 'Enter the app' : 'Continue',
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Your details stay private and can be updated later.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    required this.name,
    required this.section,
    required this.phone,
    required this.onSaveProfile,
    required this.preferences,
    required this.isDark,
    required this.onToggleTheme,
    required this.onTextScaleChanged,
    super.key,
  });

  final String name;
  final String section;
  final String phone;
  final Future<void> Function(String name, String phone, String section)
  onSaveProfile;
  final SharedPreferences preferences;
  final bool isDark;
  final VoidCallback onToggleTheme;
  final ValueChanged<double> onTextScaleChanged;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;
  int _noticeCount = 0;
  RealtimeChannel? _noticesChannel;
  late final NoticeReadService _noticeReads = NoticeReadService(
    widget.preferences,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialiseNotices());
    _noticesChannel = Supabase.instance.client
        .channel('notice-count')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'church_notices',
          callback: (_) => unawaited(_refreshNoticeCount()),
        )
        .subscribe();
  }

  Future<void> _initialiseNotices() async {
    await _noticeReads.mergeRemoteReceipts();
    await _refreshNoticeCount();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _noticesChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshNoticeCount());
    }
  }

  Future<void> _refreshNoticeCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('church_notices')
          .select('id')
          .eq('is_published', true);
      final unread = _noticeReads.unreadCount(rows.map((row) => row['id']));
      if (mounted && unread != _noticeCount) {
        setState(() => _noticeCount = unread);
      }
    } catch (error) {
      debugPrint('Notice badge refresh failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        name: widget.name,
        section: widget.section,
        onOpenPage: (index) => setState(() => _index = index),
        noticeCount: _noticeCount,
      ),
      SermonsPage(preferences: widget.preferences),
      HymnsPage(preferences: widget.preferences),
      NotesPage(preferences: widget.preferences),
      NoticesPage(
        readService: _noticeReads,
        onUnreadChanged: (count) {
          if (mounted && count != _noticeCount) {
            setState(() => _noticeCount = count);
          }
        },
      ),
      MorePage(
        name: widget.name,
        section: widget.section,
        phone: widget.phone,
        onSaveProfile: widget.onSaveProfile,
        isDark: widget.isDark,
        preferences: widget.preferences,
        onToggleTheme: widget.onToggleTheme,
        onTextScaleChanged: widget.onTextScaleChanged,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _AppNavigationBar(
        index: _index,
        noticeCount: _noticeCount,
        onSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _AppNavigationBar extends StatelessWidget {
  const _AppNavigationBar({
    required this.index,
    required this.noticeCount,
    required this.onSelected,
  });

  final int index;
  final int noticeCount;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const destinations = [
      (Icons.home_outlined, Icons.home_rounded, 'Home'),
      (
        Icons.play_circle_outline_rounded,
        Icons.play_circle_fill_rounded,
        'Sermons',
      ),
      (Icons.menu_book_outlined, Icons.menu_book_rounded, 'Nyimbo'),
      (Icons.edit_note_outlined, Icons.edit_note_rounded, 'Notes'),
      (Icons.campaign_outlined, Icons.campaign_rounded, 'Notices'),
      (Icons.grid_view_outlined, Icons.grid_view_rounded, 'More'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: AppTheme.isDark(context) ? .25 : .05,
            ),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: List.generate(destinations.length, (i) {
              final destination = destinations[i];
              final selected = i == index;
              return Expanded(
                child: _NavDestination(
                  icon: selected ? destination.$2 : destination.$1,
                  label: destination.$3,
                  selected: selected,
                  badge: i == 4 ? noticeCount : 0,
                  onTap: () => onSelected(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavDestination extends StatelessWidget {
  const _NavDestination({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? colors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 21, color: active),
                ),
                if (badge > 0)
                  Positioned(
                    right: 0,
                    top: -5,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 16),
                      height: 16,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colors.secondary,
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: colors.surface, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: TextStyle(
                          color: colors.onSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: .1,
                color: active,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.name,
    required this.section,
    required this.onOpenPage,
    this.noticeCount = 0,
    super.key,
  });

  final String name;
  final String section;
  final ValueChanged<int> onOpenPage;
  final int noticeCount;

  static const _verses = [
    (
      '“The Lord is my shepherd; I shall not want.”',
      'Psalm 23:1',
      '“Ambuye ndiye m\'busa wanga; sindidzasowa kanthu.”',
    ),
    (
      '“I can do all things through Christ who strengthens me.”',
      'Philippians 4:13',
      '“Ndikhoza zonse mwa Kristu wondipatsa mphamvu.”',
    ),
    (
      '“The Lord is my light and my salvation—whom shall I fear?”',
      'Psalm 27:1',
      '“Ambuye ndiye kuunika kwanga ndi chipulumutso changa; ndidzaopa ndani?”',
    ),
    (
      '“Be strong and courageous. Do not be afraid.”',
      'Joshua 1:9',
      '“Ulimbe mtima ndi kukhala wolimba mtima. Usaope.”',
    ),
    (
      '“Those who hope in the Lord will renew their strength.”',
      'Isaiah 40:31',
      '“Koma iwo akuyembekeza Yehova adzapeza mphamvu zatsopano.”',
    ),
    (
      '“The joy of the Lord is your strength.”',
      'Nehemiah 8:10',
      '“Chimwemwe cha Yehova ndicho mphamvu yanu.”',
    ),
    (
      '“Cast all your anxiety on him because he cares for you.”',
      '1 Peter 5:7',
      '“Ponyani nkhawa zanu zonse pa iye, chifukwa amakusamalirani.”',
    ),
    (
      '“Your word is a lamp for my feet, a light on my path.”',
      'Psalm 119:105',
      '“Mawu anu ndi nyale ya kumapazi anga, ndi kuunika kwa panjira panga.”',
    ),
    (
      '“The Lord bless you and keep you.”',
      'Numbers 6:24',
      '“Yehova akudalitseni ndi kukusungani.”',
    ),
    (
      '“Let all that you do be done in love.”',
      '1 Corinthians 16:14',
      '“Zonse zimene muchita zichitike mwachikondi.”',
    ),
    (
      '“God is our refuge and strength, an ever-present help in trouble.”',
      'Psalm 46:1',
      '“Mulungu ndiye pothawirapo pathu ndi mphamvu yathu.”',
    ),
    (
      '“Give thanks to the Lord, for he is good; his love endures forever.”',
      'Psalm 107:1',
      '“Yamikani Yehova, pakuti iye ndi wabwino; chikondi chake nchosatha.”',
    ),
  ];

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _verseIndex =
      DateTime.now().microsecondsSinceEpoch % HomePage._verses.length;
  Timer? _verseTimer;

  @override
  void initState() {
    super.initState();
    _verseTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) {
        setState(
          () => _verseIndex = (_verseIndex + 1) % HomePage._verses.length,
        );
      }
    });
  }

  @override
  void dispose() {
    _verseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final verse = HomePage._verses[_verseIndex];
    final colors = Theme.of(context).colorScheme;
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    return SafeArea(
      bottom: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              _HomeHeader(
                initials: _initials(widget.name),
                onOpenNotices: () => widget.onOpenPage(4),
                onOpenProfile: () => widget.onOpenPage(5),
                noticeCount: widget.noticeCount,
              ),
              const SizedBox(height: 26),
              Text(
                '$greeting,',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetaPill(
                    icon: Icons.groups_2_outlined,
                    label: 'Section ${widget.section}',
                  ),
                  const _MetaPill(
                    icon: Icons.location_on_outlined,
                    label: 'Kanyama',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _VerseShowcase(
                verse: verse,
                index: _verseIndex,
                total: HomePage._verses.length,
                onNext: () => setState(
                  () =>
                      _verseIndex = (_verseIndex + 1) % HomePage._verses.length,
                ),
              ),
              const SizedBox(height: 28),
              const _SectionHeading(
                eyebrow: 'THIS WEEK',
                title: 'Gather with us',
                subtitle: 'Two Sunday services, every week',
              ),
              const SizedBox(height: 12),
              _ServiceTimesCard(
                onOpenEvents: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const EventsPage()),
                ),
              ),
              const SizedBox(height: 28),
              const _SectionHeading(
                eyebrow: 'TIYENI LIMODZI',
                title: 'Quick access',
                subtitle: 'Together in worship and fellowship',
              ),
              const SizedBox(height: 12),
              _QuickActionGrid(onOpenPage: widget.onOpenPage),
              const SizedBox(height: 14),
              _BiblePromoCard(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BibleHomePage(),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const _SectionHeading(
                eyebrow: 'DISCOVER',
                title: 'Life at Kanyama',
                subtitle: 'Announcements, gatherings and our story',
              ),
              const SizedBox(height: 12),
              _ExploreChurchCard(
                onOpenNotices: () => widget.onOpenPage(4),
                onOpenEvents: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const EventsPage()),
                ),
                onOpenHistory: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChurchHistoryPage(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _AboutChurchCard(),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'RCZ';
    if (parts.length == 1) {
      final single = parts.first;
      return (single.length > 1 ? single.substring(0, 2) : single)
          .toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class SermonVideo {
  const SermonVideo({
    required this.id,
    required this.title,
    this.publishedAt,
    this.thumbnail,
    this.createdAt,
    this.scheduledStart,
    this.isLive = false,
  });

  final String id;
  final String title;
  final DateTime? publishedAt;
  final String? thumbnail;
  final DateTime? createdAt;
  final DateTime? scheduledStart;
  final bool isLive;

  bool get isUpcoming {
    final start = scheduledStart;
    return !isLive && start != null && start.isAfter(DateTime.now());
  }

  /// The best available "newness" value. A null YouTube publication date must
  /// never outrank a real one, so the database creation time is only a
  /// fallback and is never treated as a publication timestamp.
  DateTime? get sortDate => publishedAt ?? createdAt;

  factory SermonVideo.fromJson(Map<String, dynamic> json) {
    final idValue = json['videoId'] ??
        json['video_id'] ??
        json['youtube_video_id'] ??
        json['id'];
    final id = parseYoutubeVideoId(
          idValue is Map
              ? (idValue['videoId'] ?? idValue['video_id'] ?? '').toString()
              : (idValue ?? '').toString(),
        ) ??
        '';
    final published =
        json['publishedAt'] ?? json['published_at'] ?? json['publishedTime'];
    final created = json['createdAt'] ?? json['created_at'];
    final scheduled =
        json['scheduledStart'] ?? json['scheduled_start'] ?? json['startTime'];
    final liveValue = json['isLive'] ?? json['is_live'];
    final publishedAt = _sermonDate(published);
    final scheduledStart = _sermonDate(scheduled);
    final rawLive = liveValue == true || liveValue?.toString() == 'true';
    return SermonVideo(
      id: id,
      title: (json['title'] ?? 'RCZ - Kanyama service').toString(),
      publishedAt: publishedAt,
      createdAt: _sermonDate(created),
      scheduledStart: scheduledStart,
      isLive: _isLiveNow(rawLive, scheduledStart ?? publishedAt),
      thumbnail:
          json['thumbnail']?.toString() ??
          json['thumbnailUrl']?.toString() ??
          json['thumbnail_url']?.toString(),
    );
  }

  /// A badge must never outlive the service. When the sync function has not
  /// cleared an old flag, a stream that started more than twelve hours ago is
  /// treated as an ordinary past video.
  static bool _isLiveNow(bool rawLive, DateTime? reference) {
    if (!rawLive) return false;
    if (reference == null) return true;
    return DateTime.now().difference(reference) < const Duration(hours: 12);
  }
}

String _sermonDateLabel(DateTime value) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final local = value.toLocal();
  return '${local.day} ${months[local.month - 1]} ${local.year}';
}

DateTime? _sermonDate(Object? value) {
  if (value == null) return null;
  if (value is num) {
    // YouTube scheduled starts are sometimes returned as Unix seconds.
    final milliseconds = value > 100000000000
        ? value.toInt()
        : value.toInt() * 1000;
    return DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toLocal();
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}

class SermonsPage extends StatefulWidget {
  const SermonsPage({required this.preferences, super.key});
  final SharedPreferences preferences;

  @override
  State<SermonsPage> createState() => _SermonsPageState();
}

/// Extracts an 11-character YouTube video ID from a bare ID or from the common
/// URL shapes (watch, youtu.be, embed, shorts, live). Returns null when the
/// value does not contain a valid ID, so a bad row can never reach the player.
String? parseYoutubeVideoId(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  final idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');
  if (idPattern.hasMatch(value)) return value;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  final host = uri.host.toLowerCase();
  String? candidate;
  if (host == 'youtu.be' || host == 'www.youtu.be') {
    candidate = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host.endsWith('youtube.com') ||
      host.endsWith('youtube-nocookie.com')) {
    candidate = uri.queryParameters['v'];
    if (candidate == null && uri.pathSegments.length >= 2) {
      const prefixes = {'embed', 'shorts', 'live', 'v'};
      if (prefixes.contains(uri.pathSegments.first)) {
        candidate = uri.pathSegments[1];
      }
    }
  }
  if (candidate != null && idPattern.hasMatch(candidate)) return candidate;
  return null;
}

class _SermonsPageState extends State<SermonsPage> {
  // The controller is created once, when the first valid sermon is known, and
  // is only closed in dispose(). Selecting another sermon reuses it.
  YoutubePlayerController? _controller;
  StreamSubscription<YoutubePlayerValue>? _playerSubscription;
  Timer? _failureTimer;
  Timer? _refreshTimer;

  final Set<String> _favourites = {};
  List<SermonVideo> _videos = const [];
  int _selectedVideo = 0;
  bool _loading = false;
  bool _showSavedOnly = false;
  bool _playerFailed = false;
  int _failureCode = 0;

  SermonVideo? get _current {
    if (_videos.isEmpty) return null;
    final index = _selectedVideo < _videos.length ? _selectedVideo : 0;
    return _videos[index];
  }

  @override
  void initState() {
    super.initState();
    _favourites.addAll(
      widget.preferences.getStringList('sermon_favourites') ?? const [],
    );
    _refreshSermons(showMessage: false);
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _refreshSermons(showMessage: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _failureTimer?.cancel();
    _playerSubscription?.cancel();
    _controller?.close();
    super.dispose();
  }

  void _createController(String videoId) {
    final controller = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableJavaScript: true,
        playsInline: false,
        origin: null,
        userAgent:
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      ),
    );
    _playerSubscription = controller.stream.listen(_onPlayerValue);
    _controller = controller;
  }

  /// YouTube reports an error and then often recovers while buffering, so an
  /// error only becomes visible if it is still unresolved a few seconds later.
  void _onPlayerValue(YoutubePlayerValue value) {
    final hasError = value.error != YoutubeError.none;
    final state = value.playerState;
    if (state == PlayerState.playing) {
      _failureTimer?.cancel();
      if (_playerFailed && mounted) setState(() => _playerFailed = false);
      return;
    }
    if (hasError) {
      if (kDebugMode) {
        debugPrint('[SERMON_PLAYER] state=$state error=${value.error} '
            '(code ${value.error.code})');
      }
      _failureTimer?.cancel();
      _failureTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) return;
        final latest = _controller?.value;
        if (latest == null ||
            latest.error == YoutubeError.none ||
            latest.playerState == PlayerState.playing) {
          return;
        }
        setState(() {
          _playerFailed = true;
          _failureCode = latest.error.code;
        });
      });
    }
  }

  Future<void> _showVideo(SermonVideo video, {required bool autoPlay}) async {
    final controller = _controller;
    if (controller == null) return;
    _failureTimer?.cancel();
    if (_playerFailed) setState(() => _playerFailed = false);
    try {
      if (autoPlay) {
        await controller.loadVideoById(videoId: video.id);
      } else {
        await controller.cueVideoById(videoId: video.id);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('[SERMON_PLAYER] load failed: $error');
      if (mounted) setState(() => _playerFailed = true);
    }
  }

  Future<void> _refreshSermons({bool showMessage = true}) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      try {
        await Supabase.instance.client.functions.invoke('sync-youtube-sermons');
      } catch (error) {
        if (kDebugMode) debugPrint('YouTube sermon sync unavailable: $error');
      }
      final response = await Supabase.instance.client
          .from('sermons')
          .select()
          .order('published_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false)
          .limit(30);
      final seen = <String>{};
      final loaded = <SermonVideo>[];
      for (final item in response) {
        final video = SermonVideo.fromJson(item);
        // fromJson yields an empty id for anything that is not a valid
        // YouTube ID; such rows and duplicates are skipped.
        if (video.id.isNotEmpty && seen.add(video.id)) loaded.add(video);
      }
      final sorted = _sortSermons(loaded);
      if (!mounted) return;
      if (sorted.isNotEmpty) {
        final currentId = _current?.id;
        final keepIndex = currentId == null
            ? -1
            : sorted.indexWhere((video) => video.id == currentId);
        setState(() {
          _videos = sorted;
          _selectedVideo = keepIndex >= 0 ? keepIndex : 0;
        });
        if (_controller == null && kIsWeb) {
          setState(() => _createController(sorted.first.id));
        } else if (keepIndex < 0 && kIsWeb) {
          // Only the previously selected video disappeared; cue (do not
          // autoplay) the new first one.
          await _showVideo(sorted.first, autoPlay: false);
        }
      }
    } catch (error) {
      if (kDebugMode) debugPrint('Sermon refresh failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (showMessage && mounted && _videos.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sermons refreshed.')));
    }
  }

  List<SermonVideo> _sortSermons(List<SermonVideo> input) {
    final now = DateTime.now();
    final live = input.where((video) => video.isLive).toList();
    final upcoming = input
        .where(
          (video) =>
              !video.isLive &&
              video.scheduledStart != null &&
              video.scheduledStart!.isAfter(now),
        )
        .toList();
    final regular = input
        .where(
          (video) =>
              !video.isLive &&
              (video.scheduledStart == null ||
                  !video.scheduledStart!.isAfter(now)),
        )
        .toList();

    live.sort((a, b) => _compareSermonDates(b.sortDate, a.sortDate));
    upcoming.sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
    final hasPublishedDates = regular.any((video) => video.publishedAt != null);
    regular.sort((a, b) {
      if (hasPublishedDates) {
        if (a.publishedAt == null && b.publishedAt == null) {
          return _compareSermonDates(b.createdAt, a.createdAt);
        }
        if (a.publishedAt == null) return 1;
        if (b.publishedAt == null) return -1;
        final byDate = b.publishedAt!.compareTo(a.publishedAt!);
        if (byDate != 0) return byDate;
      } else {
        final byDate = _compareSermonDates(b.createdAt, a.createdAt);
        if (byDate != 0) return byDate;
      }
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return [...live, ...upcoming, ...regular];
  }

  int _compareSermonDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  Future<void> _toggleFavourite(String id) async {
    setState(() {
      if (!_favourites.add(id)) _favourites.remove(id);
    });
    await widget.preferences.setStringList(
      'sermon_favourites',
      _favourites.toList(),
    );
  }

  Future<void> _shareVideo(SermonVideo video) async {
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${video.title}\nhttps://www.youtube.com/watch?v=${video.id}\nRCZ - Kanyama',
      ),
    );
  }

  Future<void> _openOnYoutube(SermonVideo video) async {
    await launchUrl(
      Uri.parse('https://www.youtube.com/watch?v=${video.id}'),
      mode: LaunchMode.externalApplication,
    );
  }

  String get _failureMessage {
    switch (_failureCode) {
      case 100:
        return 'This video is private or has been removed.';
      case 101:
      case 150:
        return 'The video owner has not allowed this video to be played '
            'inside other apps.';
      default:
        return 'This video could not be played right now.';
    }
  }

  Widget _buildPlayerArea(Widget? player) {
    final video = _current;
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (player != null)
              player
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            if (_playerFailed && video != null)
              Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(16),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_disabled_rounded,
                        color: Colors.white70, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      _failureMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => _showVideo(video, autoPlay: true),
                          child: const Text('Try again'),
                        ),
                        TextButton(
                          onPressed: () => _openOnYoutube(video),
                          child: const Text('Watch on YouTube'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (kIsWeb) {
      if (controller == null) return _buildPage(context, null);
      return YoutubePlayerScaffold(
        controller: controller,
        aspectRatio: 16 / 9,
        builder: (context, player) => _buildPage(context, player),
      );
    }
    // Android: load the embed URL directly in a WebView so YouTube does not
    // require an HTTP Referer (the iframe-in-local-HTML approach fails with
    // error 153).
    return _buildPage(context, _AndroidEmbedPlayer(videoId: _current?.id));
  }

  Widget _buildPage(BuildContext context, Widget? player) {
    final colors = Theme.of(context).colorScheme;
    final visible = _videos
        .asMap()
        .entries
        .where(
          (entry) => !_showSavedOnly || _favourites.contains(entry.value.id),
        )
        .toList();
    final nowPlayingTitle = _current?.title ?? 'Sermons from RCZ Kanyama';
    return AppPage(
      title: 'Sermons',
      subtitle: 'Mauthenga a moyo • Watch and grow in the Word',
      actions: [
        IconButton(
          tooltip: 'Refresh sermons',
          onPressed: _loading ? null : () => _refreshSermons(),
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildPlayerArea(player),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: colors.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _videos.isEmpty ? 'SERMON LIBRARY' : 'NOW PLAYING',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colors.secondary,
                                    letterSpacing: 1.6,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          nowPlayingTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_loading) ...[
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: const LinearProgressIndicator(minHeight: 3),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _refreshSermons(showMessage: false),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Latest messages',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _showSavedOnly
                                  ? '${_favourites.length} saved '
                                        '${_favourites.length == 1 ? 'sermon' : 'sermons'}'
                                  : '${_videos.length} available to watch',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      _FilterToggle(
                        icon: _showSavedOnly
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        label: 'Saved',
                        selected: _showSavedOnly,
                        onTap: () =>
                            setState(() => _showSavedOnly = !_showSavedOnly),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: _EmptyState(
                        icon: _showSavedOnly
                            ? Icons.bookmark_border_rounded
                            : Icons.play_circle_outline_rounded,
                        title: _showSavedOnly
                            ? 'No saved sermons'
                            : 'Sermons will appear here',
                        message: _showSavedOnly
                            ? 'Tap the bookmark on a sermon to keep it close.'
                            : 'Connect to the internet to load the latest messages.',
                      ),
                    )
                  else
                    ...visible.map((entry) {
                      final index = entry.key;
                      final video = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SermonTile(
                          video: video,
                          isPlaying: index == _selectedVideo,
                          saved: _favourites.contains(video.id),
                          onTap: () {
                            if (index == _selectedVideo && !_playerFailed) {
                              return;
                            }
                            setState(() => _selectedVideo = index);
                            _showVideo(video, autoPlay: true);
                          },
                          onToggleSaved: () => _toggleFavourite(video.id),
                          onShare: () => _shareVideo(video),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HymnLanguageSwitch extends StatelessWidget {
  const _HymnLanguageSwitch({required this.english, required this.onChanged});

  final bool english;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LanguageOption(
            label: 'Chichewa',
            selected: !english,
            onTap: () => onChanged(false),
          ),
          _LanguageOption(
            label: 'English',
            selected: english,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? colors.primary : colors.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SermonTile extends StatelessWidget {
  const _SermonTile({
    required this.video,
    required this.isPlaying,
    required this.saved,
    required this.onTap,
    required this.onToggleSaved,
    required this.onShare,
  });

  final SermonVideo video;
  final bool isPlaying;
  final bool saved;
  final VoidCallback onTap;
  final VoidCallback onToggleSaved;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final live = video.isLive;
    final upcoming = video.isUpcoming;
    final statusColor = live ? colors.error : colors.secondary;
    final statusText = live
        ? 'LIVE'
        : upcoming
        ? 'UPCOMING'
        : null;
    final date = video.publishedAt ?? video.createdAt;
    final subtitle = isPlaying
        ? 'Now playing'
        : live
        ? 'Live now'
        : upcoming
        ? 'Starts ${_sermonDateLabel(video.scheduledStart!)}'
        : date == null
        ? 'Tap to watch'
        : _sermonDateLabel(date);
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: BorderSide(
          color: live
              ? colors.error
              : isPlaying
              ? colors.primary
              : colors.outlineVariant,
          width: live || isPlaying ? 1.4 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.network(
                      video.thumbnail ??
                          'https://img.youtube.com/vi/${video.id}/mqdefault.jpg',
                      width: 118,
                      height: 74,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 118,
                        height: 74,
                        color: colors.surfaceContainerHigh,
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .45),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .6),
                        ),
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
                    if (statusText != null)
                      Positioned(
                        left: 5,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: live ? colors.onError : colors.onSecondary,
                              fontSize: 7.5,
                              letterSpacing: .8,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontSize: 13.5, height: 1.4),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isPlaying
                            ? colors.primary
                            : live
                            ? colors.error
                            : upcoming
                            ? colors.secondary
                            : colors.onSurfaceVariant,
                        fontWeight: isPlaying || live || upcoming
                            ? FontWeight.w700
                            : null,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _MiniIconButton(
                          tooltip: saved ? 'Remove from saved' : 'Save sermon',
                          onPressed: onToggleSaved,
                          icon: saved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          active: saved,
                        ),
                        _MiniIconButton(
                          tooltip: 'Share sermon',
                          onPressed: onShare,
                          icon: Icons.ios_share_rounded,
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

class _MiniIconButton extends StatelessWidget {
  const _MiniIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.active = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
      iconSize: 18,
      icon: Icon(
        icon,
        color: active ? colors.primary : colors.onSurfaceVariant,
      ),
    );
  }
}

Map<int, String> _decodeBook(String raw) {
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final entries = decoded['hymns'] as List<dynamic>;
  final result = <int, String>{};
  for (final rawEntry in entries) {
    final entry = rawEntry as Map<String, dynamic>;
    final number = entry['number'] as int;
    final stanzas = entry['stanzas'];
    if (stanzas is List) {
      final lines = <String>[];
      for (final rawStanza in stanzas) {
        final stanza = rawStanza as Map<String, dynamic>;
        final type = stanza['type']?.toString();
        final stanzaNumber = stanza['number'];
        if (type == 'chorus') lines.add('Kwaya:');
        if (type == 'verse' && stanzaNumber != null) {
          lines.add('$stanzaNumber.');
        }
        final stanzaLines = stanza['lines'];
        if (stanzaLines is List) {
          lines.addAll(stanzaLines.map((line) => line.toString()));
        }
        lines.add('');
      }
      result[number] = lines.join('\n').trim();
    } else {
      result[number] = (entry['text'] ?? entry['lyrics'] ?? '').toString();
    }
  }
  return result;
}

String _cleanLyrics(String lyrics) {
  // Preserve stanza breaks and the original line structure from the hymnbook.
  final lines = lyrics
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .toList();
  final cleaned = <String>[];
  var previousWasBlank = false;
  for (final line in lines) {
    if (line.isEmpty) {
      if (cleaned.isNotEmpty && !previousWasBlank) cleaned.add('');
      previousWasBlank = true;
    } else {
      cleaned.add(line);
      previousWasBlank = false;
    }
  }
  while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
    cleaned.removeLast();
  }
  return cleaned.join('\n');
}

String _hymnTitle(String lyrics, int number) {
  final lines = _cleanLyrics(lyrics)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .take(2)
      .map(
        (line) => line
            .replaceFirst(RegExp(r'^(?:\d+[.)]?|[IVX]+[.)])\s*'), '')
            .trim(),
      )
      .where((line) => line.isNotEmpty)
      .toList();
  return lines.isEmpty ? 'Hymn $number' : lines.join('\n');
}

class HymnsPage extends StatefulWidget {
  const HymnsPage({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<HymnsPage> createState() => _HymnsPageState();
}

class _HymnsPageState extends State<HymnsPage> {
  final _searchController = TextEditingController();
  late final Future<List<Hymn>> _hymnsFuture = _loadHymns();
  final _favourites = <int>{};
  bool _english = false;
  bool _showFavouritesOnly = false;

  @override
  void initState() {
    super.initState();
    _favourites.addAll(
      widget.preferences.getStringList('hymn_favourites')?.map(int.parse) ??
          const <int>[],
    );
  }

  Future<List<Hymn>> _loadHymns() async {
    final books = await Future.wait([
      rootBundle.loadString('assets/chichewa_hymns.json'),
      rootBundle.loadString('assets/english_hymns.json'),
    ]);
    final chichewa = _decodeBook(books[0]);
    final english = _decodeBook(books[1]);
    final numbers = List<int>.generate(384, (index) => index + 1);
    return numbers
        .map(
          (number) => Hymn(
            number: number,
            chichewaText: _cleanLyrics(chichewa[number] ?? ''),
            englishText: _cleanLyrics(english[number] ?? ''),
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppPage(
      title: 'Nyimbo',
      subtitle: 'Offline hymnbook • Chichewa and English',
      child: FutureBuilder<List<Hymn>>(
        future: _hymnsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const _EmptyState(
              icon: Icons.menu_book_outlined,
              title: 'Hymnbook unavailable',
              message: 'The Chichewa or English hymn JSON could not be loaded. Check that both hymn JSON files are listed in pubspec.yaml.',
            );
          }
          final query = _searchController.text.trim().toLowerCase();
          final visible = snapshot.data!.where((hymn) {
            if (_showFavouritesOnly && !_favourites.contains(hymn.number)) {
              return false;
            }
            final title = (_english ? hymn.englishTitle : hymn.chichewaTitle)
                .toLowerCase();
            return query.isEmpty ||
                hymn.number.toString() == query ||
                title.contains(query) ||
                (_english ? hymn.englishText : hymn.chichewaText)
                    .toLowerCase()
                    .contains(query);
          }).toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search by number, title or lyrics',
                        prefixIcon: const Icon(Icons.search_rounded, size: 21),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded, size: 19),
                              ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _HymnLanguageSwitch(
                          english: _english,
                          onChanged: (value) =>
                              setState(() => _english = value),
                        ),
                        const Spacer(),
                        _FilterToggle(
                          icon: _showFavouritesOnly
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          label: 'Favourites',
                          selected: _showFavouritesOnly,
                          onTap: () => setState(
                            () => _showFavouritesOnly = !_showFavouritesOnly,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    Text(
                      query.isEmpty ? 'All hymns' : 'Search results',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${visible.length} shown',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: visible.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
                        children: [
                          _EmptyState(
                            icon: _showFavouritesOnly
                                ? Icons.favorite_border_rounded
                                : Icons.search_off_rounded,
                            title: _showFavouritesOnly
                                ? 'No favourite hymns yet'
                                : 'No hymns found',
                            message: _showFavouritesOnly
                                ? 'Open a hymn and tap the heart to save it here.'
                                : 'Try a hymn number, a title or a line from the lyrics.',
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        itemCount: visible.length,
                        itemBuilder: (_, index) {
                          final hymn = visible[index];
                          final title = _english
                              ? hymn.englishTitle
                              : hymn.chichewaTitle;
                          final favourite = _favourites.contains(hymn.number);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _openHymn(hymn),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    11,
                                    10,
                                    11,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: colors.primaryContainer,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${hymn.number}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                color:
                                                    colors.onPrimaryContainer,
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontSize: 13.5,
                                                    height: 1.35,
                                                  ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              (_english
                                                          ? hymn.englishText
                                                          : hymn.chichewaText)
                                                      .trim()
                                                      .isEmpty
                                                  ? 'Lyrics not yet available'
                                                  : (_english
                                                        ? 'English edition'
                                                        : 'Chichewa edition'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        colors.onSurfaceVariant,
                                                    fontSize: 11.5,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (favourite)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 4,
                                          ),
                                          child: Icon(
                                            Icons.favorite_rounded,
                                            size: 15,
                                            color: colors.secondary,
                                          ),
                                        ),
                                      Icon(
                                        Icons.chevron_right_rounded,
                                        size: 19,
                                        color: colors.onSurfaceVariant
                                            .withValues(alpha: .7),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openHymn(Hymn hymn) {
    final text = _english ? hymn.englishText : hymn.chichewaText;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HymnReaderPage(
          hymn: hymn,
          lyrics: text,
          languageLabel: _english ? 'English edition' : 'Chichewa edition',
          isFavourite: _favourites.contains(hymn.number),
          fontScale: 1.0,
          onFavouriteChanged: (value) {
            setState(() {
              if (value) {
                _favourites.add(hymn.number);
              } else {
                _favourites.remove(hymn.number);
              }
            });
            widget.preferences.setStringList(
              'hymn_favourites',
              _favourites.map((value) => value.toString()).toList(),
            );
          },
        ),
      ),
    );
  }
}

class HymnReaderPage extends StatefulWidget {
  const HymnReaderPage({
    required this.hymn,
    required this.lyrics,
    required this.languageLabel,
    required this.isFavourite,
    required this.fontScale,
    required this.onFavouriteChanged,
    super.key,
  });

  final Hymn hymn;
  final String lyrics;
  final String languageLabel;
  final bool isFavourite;
  final double fontScale;
  final ValueChanged<bool> onFavouriteChanged;

  @override
  State<HymnReaderPage> createState() => _HymnReaderPageState();
}

class _HymnReaderPageState extends State<HymnReaderPage> {
  late bool _isFavourite = widget.isFavourite;
  late double _readerScale = widget.fontScale;

  Future<void> _changeSize() async {
    var value = _readerScale;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Reading size',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Slider(
                value: value,
                min: .8,
                max: 1.5,
                divisions: 7,
                label: '${(value * 100).round()}%',
                onChanged: (next) {
                  setSheetState(() => value = next);
                  setState(() => _readerScale = next);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<InlineSpan> _buildLyrics() {
    final spans = <InlineSpan>[];
    var hasVerse = false;
    for (final raw in _cleanLyrics(widget.lyrics).split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) {
        spans.add(const TextSpan(text: '\n'));
        continue;
      }
      final isChorus = RegExp(
        r'^(chorus|refrain|kwaya)',
        caseSensitive: false,
      ).hasMatch(line);
      final isVerse = RegExp(r'^(?:\d+|[IVX]+)[.)]?\s+').hasMatch(line);
      if (isVerse && hasVerse) spans.add(const TextSpan(text: '\n'));
      hasVerse = true;
      spans.add(
        TextSpan(
          text: '$line\n',
          style: isChorus
              ? const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .4)
              : null,
        ),
      );
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: Text('Nyimbo ${widget.hymn.number}'),
        actions: [
          IconButton(
            tooltip: 'Reading size',
            onPressed: _changeSize,
            icon: const Icon(Icons.format_size),
          ),
          IconButton(
            tooltip: 'Share hymn',
            onPressed: () => SharePlus.instance.share(
              ShareParams(
                text:
                    '${_hymnTitle(widget.lyrics, widget.hymn.number)}\n\n${widget.lyrics}\n\nRCZ - Kanyama',
              ),
            ),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: _isFavourite ? 'Remove favourite' : 'Add to favourites',
            onPressed: () {
              setState(() => _isFavourite = !_isFavourite);
              widget.onFavouriteChanged(_isFavourite);
            },
            icon: Icon(
              _isFavourite ? Icons.favorite : Icons.favorite_border,
              color: _isFavourite ? Colors.redAccent : null,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.surface,
                colors.primary.withValues(alpha: .035),
                colors.surface,
              ],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(26, 26, 26, 48),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 74)
                      .clamp(0.0, 100000.0)
                      .toDouble(),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(
                            'HYMN ${widget.hymn.number}  •  ${widget.languageLabel.toUpperCase()}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                              letterSpacing: 1.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          widget.lyrics.trim().isEmpty
                              ? 'Hymn ${widget.hymn.number}'
                              : _hymnTitle(widget.lyrics, widget.hymn.number),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.35,
                                color: colors.primary,
                              ),
                        ),
                        const SizedBox(height: 24),
                        Divider(
                          color: colors.primary.withValues(alpha: .22),
                          indent: 70,
                          endIndent: 70,
                        ),
                        const SizedBox(height: 24),
                        if (widget.lyrics.trim().isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'The lyrics for this hymn are not yet present in the supplied ${widget.languageLabel.toLowerCase()} JSON file.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: SelectableText.rich(
                              TextSpan(
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      fontFamily: 'SourceSerif4',
                                      fontSize: 20.0 * _readerScale,
                                      height: 1.55,
                                      letterSpacing: .1,
                                      color: colors.onSurface,
                                    ),
                                children: _buildLyrics(),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        const SizedBox(height: 34),
                        Text(
                          'RCZ - Kanyama',
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                letterSpacing: 1.2,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Hymn {
  const Hymn({
    required this.number,
    required this.chichewaText,
    required this.englishText,
  });

  final int number;
  final String chichewaText;
  final String englishText;

  String get chichewaTitle => _hymnTitle(chichewaText, number);
  String get englishTitle => _hymnTitle(englishText, number);
}

class NotesPage extends StatefulWidget {
  const NotesPage({required this.preferences, super.key});

  final SharedPreferences preferences;

  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _searchController = TextEditingController();
  final NotesRepository _repository = NotesRepository.instance;
  List<Note> _notes = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _repository.addListener(_onNotesChanged);
    unawaited(_loadNotes());
  }

  Future<void> _loadNotes() async {
    await _repository.ensureLoaded(widget.preferences);
    if (!mounted) return;
    setState(() {
      _notes = _repository.notes;
      _isLoading = false;
    });
  }

  void _onNotesChanged() {
    if (!mounted) return;
    setState(() => _notes = _repository.notes);
  }

  @override
  void dispose() {
    _repository.removeListener(_onNotesChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _editNote([Note? note]) async {
    final result = await Navigator.of(context).push<Note>(
      MaterialPageRoute<Note>(builder: (_) => NoteEditorPage(note: note)),
    );
    if (result != null) {
      await _repository.save(result);
    }
  }

  Future<void> _viewNote(Note note) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NoteViewPage(
          note: note,
          onEdit: () async {
            Navigator.of(context).pop();
            await _editNote(note);
          },
        ),
      ),
    );
  }

  Future<void> _deleteNote(Note note) async {
    if (note.isPinned) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unpin this note before deleting it.')),
      );
      return;
    }
    await _repository.delete(note.id);
  }

  Future<void> _togglePin(Note note) => _repository.togglePin(note.id);

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final colors = Theme.of(context).colorScheme;
    final query = _searchController.text.trim();
    final notes = _repository.search(query);
    return AppPage(
      title: 'Notes',
      subtitle: 'Keep what speaks to your heart',
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search your notes',
                        prefixIcon: const Icon(Icons.search_rounded, size: 21),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded, size: 19),
                              ),
                      ),
                    ),
                    if (_notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            query.isEmpty ? 'All notes' : 'Search results',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  letterSpacing: 1.2,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            '${notes.length} ${notes.length == 1 ? 'note' : 'notes'}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11.5,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: notes.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 30, 20, 24),
                        children: [
                          _EmptyState(
                            icon: query.isEmpty
                                ? Icons.edit_note_rounded
                                : Icons.search_off_rounded,
                            title: query.isEmpty
                                ? 'Start a new note'
                                : 'No matching notes',
                            message: query.isEmpty
                                ? 'Write sermon highlights, prayer points and reflections, or save a verse from the Bible. Your notes are only visible to you.'
                                : 'Try a different word or clear the search to see all your notes.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (_, index) {
                          final note = notes[index];
                          final source = note.source;
                          return Dismissible(
                            key: ValueKey(note.id),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 22),
                              decoration: BoxDecoration(
                                color: colors.primary,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.card,
                                ),
                              ),
                              child: Icon(
                                Icons.push_pin_rounded,
                                color: colors.onPrimary,
                              ),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 22),
                              decoration: BoxDecoration(
                                color: colors.error,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.card,
                                ),
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                color: colors.onError,
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                await _togglePin(note);
                                return false;
                              }
                              if (note.isPinned) {
                                await _deleteNote(note);
                                return false;
                              }
                              return true;
                            },
                            onDismissed: (_) async {
                              await _repository.delete(note.id);
                            },
                            child: Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _viewNote(note),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    13,
                                    6,
                                    13,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _TintIcon(
                                        icon: source != null
                                            ? Icons.auto_stories_rounded
                                            : note.isPinned
                                            ? Icons.push_pin_rounded
                                            : Icons.sticky_note_2_outlined,
                                        size: 40,
                                        radius: 11,
                                        background: note.isPinned
                                            ? colors.secondaryContainer
                                            : source != null
                                            ? colors.primaryContainer
                                            : null,
                                        foreground: note.isPinned
                                            ? colors.onSecondaryContainer
                                            : source != null
                                            ? colors.onPrimaryContainer
                                            : null,
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    note.title.isEmpty
                                                        ? 'Untitled note'
                                                        : note.title,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontSize: 14,
                                                        ),
                                                  ),
                                                ),
                                                if (note.isPinned)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          left: 6,
                                                        ),
                                                    child: Text(
                                                      'PINNED',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelSmall
                                                          ?.copyWith(
                                                            fontSize: 8.5,
                                                            color:
                                                                colors.secondary,
                                                            letterSpacing: 1,
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            if (source != null) ...[
                                              const SizedBox(height: 3),
                                              Text(
                                                '${source.reference.toUpperCase()} \u00b7 ${source.translationName}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          colors.secondary,
                                                      letterSpacing: 0.4,
                                                    ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Text(
                                              note.previewText.isEmpty
                                                  ? 'No text yet'
                                                  : note.previewText,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: colors
                                                        .onSurfaceVariant,
                                                    height: 1.45,
                                                  ),
                                            ),
                                            const SizedBox(height: 7),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.schedule_rounded,
                                                  size: 12,
                                                  color: colors.onSurfaceVariant
                                                      .withValues(alpha: .8),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatDate(note.updatedAt),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: colors
                                                            .onSurfaceVariant,
                                                        fontSize: 10.5,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: 'Note options',
                                        onSelected: (value) {
                                          if (value == 'edit') _editNote(note);
                                          if (value == 'pin') _togglePin(note);
                                          if (value == 'delete') {
                                            _deleteNote(note);
                                          }
                                        },
                                        itemBuilder: (_) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Edit'),
                                          ),
                                          PopupMenuItem(
                                            value: 'pin',
                                            child: Text(
                                              note.isPinned ? 'Unpin' : 'Pin',
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'delete',
                                            enabled: !note.isPinned,
                                            child: Text(
                                              note.isPinned
                                                  ? 'Unpin before deleting'
                                                  : 'Delete',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.extended(
              onPressed: _editNote,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New note'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return '${date.day} ${months[date.month - 1]} ${date.year} \u00b7 $time';
  }
}

class NoticesPage extends StatefulWidget {
  const NoticesPage({
    required this.readService,
    this.onUnreadChanged,
    super.key,
  });

  final NoticeReadService readService;
  final ValueChanged<int>? onUnreadChanged;

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> with WidgetsBindingObserver {
  bool _loading = true;
  List<Map<String, dynamic>> _notices = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.readService.mergeRemoteReceipts());
      unawaited(_load());
    }
  }

  void _notifyUnread() {
    widget.onUnreadChanged?.call(
      widget.readService.unreadCount(_notices.map((notice) => notice['id'])),
    );
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await Supabase.instance.client
          .from('church_notices')
          .select('id,title,body,category,event_date,created_at,photo_url')
          .eq('is_published', true)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _notices = List<Map<String, dynamic>>.from(rows));
      _notifyUnread();
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = 'Notices could not be loaded. Check the database setup and internet connection.',
      );
      debugPrint('Notice loading failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic raw) {
    if (raw == null) return 'Church announcement';
    final value = DateTime.tryParse(raw.toString())?.toLocal();
    if (value == null) return 'Church announcement';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }

  Color _categoryAccent(String category, ColorScheme colors) {
    switch (category.toLowerCase()) {
      case 'event':
        return colors.secondary;
      case 'funeral':
        return colors.tertiary;
      case 'marriage':
        return colors.tertiary;
      case 'service update':
        return colors.primary;
      default:
        return colors.primary;
    }
  }

  Future<void> _openNotice(Map<String, dynamic> item) async {
    final marked = await widget.readService.markRead(item['id']);
    if (!mounted) return;
    if (marked) {
      setState(() {});
      _notifyUnread();
    }
    final category = (item['category'] ?? 'Announcement').toString();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _NoticeDetailSheet(
        title: item['title']?.toString() ?? '',
        body: item['body']?.toString() ?? '',
        category: category,
        date: _date(item['event_date'] ?? item['created_at']),
        photoUrl: item['photo_url']?.toString(),
        accent: _categoryAccent(category, Theme.of(context).colorScheme),
      ),
    );
  }

  Future<void> _openPhoto(String url) async {
    await showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: InteractiveViewer(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppPage(
      title: 'Church notices',
      subtitle: 'Official announcements and updates',
      actions: [
        IconButton(
          tooltip: 'Refresh notices',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                children: [
                  _EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Notices unavailable',
                    message: _error!,
                  ),
                ],
              )
            : _notices.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
                children: const [
                  _EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No notices yet',
                    message: 'Official notices from the Secretariat will appear here.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                itemCount: _notices.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _NoticesBanner(count: _notices.length);
                  }
                  final item = _notices[index - 1];
                  final category = (item['category'] ?? 'Announcement')
                      .toString();
                  return _NoticeCard(
                    category: category,
                    date: _date(item['event_date'] ?? item['created_at']),
                    title: item['title']?.toString() ?? '',
                    body: item['body']?.toString() ?? '',
                    photoUrl: item['photo_url']?.toString(),
                    accent: _categoryAccent(category, colors),
                    unread: !widget.readService.isRead(item['id']),
                    onTap: () => _openNotice(item),
                    onPhotoTap: item['photo_url'] == null
                        ? null
                        : () => _openPhoto(item['photo_url'].toString()),
                  );
                },
              ),
      ),
    );
  }
}

class _NoticesBanner extends StatelessWidget {
  const _NoticesBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          _TintIcon(icon: Icons.verified_outlined, size: 36, radius: 10),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From the church office',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '$count published ${count == 1 ? 'notice' : 'notices'}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.shield_outlined, size: 18, color: colors.secondary),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.category,
    required this.date,
    required this.title,
    required this.body,
    required this.photoUrl,
    required this.accent,
    required this.unread,
    required this.onTap,
    this.onPhotoTap,
  });

  final String category;
  final String date;
  final String title;
  final String body;
  final String? photoUrl;
  final Color accent;
  final bool unread;
  final VoidCallback onTap;
  final VoidCallback? onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photoUrl != null)
              GestureDetector(
                onTap: onPhotoTap,
                child: Image.network(
                  photoUrl!,
                  height: 164,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(17, 15, 17, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            color: accent,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 7),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontSize: 11.5,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 16.5, height: 1.35),
                  ),
                  if (body.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        height: 1.55,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Read notice',
                        style: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(color: accent, fontSize: 12.5),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: accent,
                      ),
                    ],
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

class _NoticeDetailSheet extends StatelessWidget {
  const _NoticeDetailSheet({
    required this.title,
    required this.body,
    required this.category,
    required this.date,
    required this.photoUrl,
    required this.accent,
  });

  final String title;
  final String body;
  final String category;
  final String date;
  final String? photoUrl;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (photoUrl != null) ...[
                  GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        clipBehavior: Clip.antiAlias,
                        child: InteractiveViewer(
                          child: Image.network(photoUrl!, fit: BoxFit.contain),
                        ),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        photoUrl!,
                        width: double.infinity,
                        height: 210,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    category.toUpperCase(),
                    style: TextStyle(
                      color: accent,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(height: 1.3),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      date,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(color: colors.outlineVariant),
                const SizedBox(height: 18),
                SelectableText(
                  body,
                  style: Theme.of(context).textTheme.bodyLarge
                      ?.copyWith(color: colors.onSurface, height: 1.7),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Published by the RCZ Kanyama Secretariat',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SecretariatAccessPage extends StatefulWidget {
  const SecretariatAccessPage({super.key});

  @override
  State<SecretariatAccessPage> createState() => _SecretariatAccessPageState();
}

class _SecretariatAccessPageState extends State<SecretariatAccessPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  String _normaliseContactPhone(String value) {
    var phone = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
    if (phone.startsWith('0')) {
      phone = '+260${phone.substring(1)}';
    } else if (phone.startsWith('260')) {
      phone = '+$phone';
    }
    return phone;
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final phone = _normaliseContactPhone(_phone.text);
    final password = _password.text;
    // Role is assigned exclusively by the owner during approval. New
    // registrations are always created as pending SEC applicants.
    final role = _creating ? 'SEC' : null;

    if (_creating && name.isEmpty) {
      _message('Enter your full name.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _message('Enter a valid email address.');
      return;
    }
    if (_creating && !RegExp(r'^\+260\d{9}$').hasMatch(phone)) {
      _message('Enter a valid Zambian phone number, for example 0971234567.');
      return;
    }
    if (password.length < 8) {
      _message('Your password must be at least 8 characters long.');
      return;
    }
    if (_creating && password != _confirmPassword.text) {
      _message('The two passwords do not match.');
      return;
    }

    setState(() => _busy = true);
    try {
      final auth = Supabase.instance.client.auth;
      if (_creating) {
        final response = await auth.signUp(
          email: email,
          password: password,
          data: {
            'full_name': name,
            'contact_phone': phone,
            'requested_role': role,
          },
        );
        if (response.user == null) {
          _message('Account creation did not complete. Please try again.');
        } else if (response.session == null) {
          _message(
            'Account created. Check your email for a confirmation link, then return here and sign in. Your Secretariat role must still be approved by the church administrator.',
          );
        } else if (response.user?.emailConfirmedAt == null) {
          _message(
            'Account created. Please confirm your email address before signing in. Your application is awaiting administrator approval.',
          );
        } else {
          await _checkAccess(response.user!.id);
        }
      } else {
        final response = await auth.signInWithPassword(
          email: email,
          password: password,
        );
        final user = response.user;
        if (user == null) {
          _message('Login was unsuccessful.');
        } else if (user.emailConfirmedAt == null) {
          _message('Please confirm your email address before signing in.');
        } else {
          await _checkAccess(user.id);
        }
      }
    } on AuthException catch (error) {
      _message(error.message);
    } on PostgrestException catch (error) {
      _message(
        'Account authenticated, but Secretariat access could not be checked: ${error.message}',
      );
    } catch (error) {
      _message(
        'Could not complete the request. Check your connection and try again.',
      );
      debugPrint('Secretariat access error: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAccess(String userId) async {
    final row = await Supabase.instance.client
        .from('secretariat_accounts')
        .select('role,is_active,display_name,status')
        .eq('user_id', userId)
        .maybeSingle();
    if (!mounted) return;
    if (row == null) {
      _message(
        'No membership application was found for this account. Please contact the church administrator.',
      );
      return;
    }
    final status = row['status']?.toString();
    if (status == 'rejected') {
      _message(
        'Your application was not approved. Please contact the church administrator.',
      );
      return;
    }
    if (row['is_active'] != true) {
      if (status == 'inactive') {
        _message(
          'Your account is currently inactive. Please contact the church administrator.',
        );
      } else {
        _message('Your application is awaiting administrator approval.');
      }
      return;
    }
    final role = row['role']?.toString().toUpperCase();
    if (role != 'SEC' && role != 'VSEC') {
      _message('This account does not have a valid Secretariat role.');
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SecretariatDashboardPage(
          role: role!,
          displayName: row['display_name']?.toString() ?? _name.text.trim(),
        ),
      ),
    );
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Secretariat access')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 32),
            children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: .08),
                    ),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 29,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _creating ? 'Create Secretariat account' : 'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'This area is for church office bearers only. Register with '
                'your email address and contact phone number. Secretariat '
                'access is granted only after the church administrator '
                'approves your account.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
              ),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_creating) ...[
                        TextField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Full name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Contact phone number',
                            hintText: '0971234567',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textCapitalization: TextCapitalization.none,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_creating) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmPassword,
                          obscureText: _obscure,
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_creating ? 'Create account' : 'Sign in'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _creating = !_creating),
                        child: Text(
                          _creating
                              ? 'Already registered? Sign in'
                              : 'New Secretariat member? Create an account',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Only authorised office bearers can publish notices.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SecretariatDashboardPage extends StatefulWidget {
  const SecretariatDashboardPage({
    required this.role,
    required this.displayName,
    super.key,
  });

  final String role;
  final String displayName;

  @override
  State<SecretariatDashboardPage> createState() =>
      _SecretariatDashboardPageState();
}

class _SecretariatDashboardPageState extends State<SecretariatDashboardPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _members = [];
  String _memberSection = 'All sections';
  RealtimeChannel? _membersChannel;

  @override
  void initState() {
    super.initState();
    _load();
    _membersChannel = Supabase.instance.client
        .channel('secretariat-members-${widget.displayName}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'members',
          callback: (_) => _loadMembers(),
        )
        .subscribe();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await _cleanupExpiredPhotos();
      final rows = await Supabase.instance.client
          .from('church_notices')
          .select(
            'id,title,body,category,event_date,is_published,created_at,photo_url,photo_path,photo_expires_at',
          )
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() => _items = List<Map<String, dynamic>>.from(rows));
      }
    } catch (error) {
      _message(
        'Could not load Secretariat notices. Check database permissions.',
      );
      debugPrint('Secretariat dashboard load: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final members = await Supabase.instance.client
          .from('members')
          .select('name,phone,section,registered_at,app_version')
          .order('section')
          .order('name');
      if (mounted) {
        setState(() => _members = List<Map<String, dynamic>>.from(members));
      }
    } on PostgrestException catch (error) {
      debugPrint(
        'Secretariat members could not load: ${error.code} ${error.message}',
      );
    } catch (error) {
      debugPrint('Secretariat members could not load: $error');
    }
  }

  @override
  void dispose() {
    final channel = _membersChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }
    super.dispose();
  }

  List<Map<String, dynamic>> get _visibleMembers =>
      _memberSection == 'All sections'
      ? _members
      : _members
            .where((member) => member['section'] == _memberSection)
            .toList();

  String _largestSection() {
    if (_members.isEmpty) return '—';
    final counts = <String, int>{};
    for (final member in _members) {
      final section = member['section']?.toString() ?? 'Unknown';
      counts[section] = (counts[section] ?? 0) + 1;
    }
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<void> _exportMembers() async {
    final workbook = Excel.createExcel();
    final sheet = workbook['Members'];
    sheet.appendRow([
      TextCellValue('Name'),
      TextCellValue('Phone'),
      TextCellValue('Section'),
      TextCellValue('Registered'),
    ]);
    for (final member in _visibleMembers) {
      sheet.appendRow([
        TextCellValue(member['name']?.toString() ?? ''),
        TextCellValue(member['phone']?.toString() ?? ''),
        TextCellValue(member['section']?.toString() ?? ''),
        TextCellValue(member['registered_at']?.toString() ?? ''),
      ]);
    }
    final bytes = workbook.encode();
    if (bytes == null || !mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        title: 'RCZ Kanyama members',
        text: 'RCZ - Kanyama member register',
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: 'rcz_kanyama_members.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
      ),
    );
  }

  Future<void> _cleanupExpiredPhotos() async {
    final client = Supabase.instance.client;
    final expired = await client
        .from('church_notices')
        .select('id,photo_path')
        .not('photo_path', 'is', null)
        .lt('photo_expires_at', DateTime.now().toUtc().toIso8601String());
    for (final row in expired) {
      final path = row['photo_path']?.toString();
      if (path != null && path.isNotEmpty) {
        await client.storage.from('notice-photos').remove([path]);
      }
      await client
          .from('church_notices')
          .update({
            'photo_url': null,
            'photo_path': null,
            'photo_expires_at': null,
          })
          .eq('id', row['id']);
    }
  }

  Future<void> _compose([Map<String, dynamic>? existing]) async {
    final title = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    final body = TextEditingController(
      text: existing?['body']?.toString() ?? '',
    );
    var category = existing?['category']?.toString() ?? 'Announcement';
    XFile? photo;
    DateTime? eventDate = DateTime.tryParse(
      existing?['event_date']?.toString() ?? '',
    );
    final categories = [
      'Announcement',
      'Event',
      'Funeral',
      'Marriage',
      'Service update',
      'Other',
    ];
    final publish = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Create notice' : 'Edit notice'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.sizeOf(context).height * .62,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: categories.contains(category)
                        ? category
                        : 'Announcement',
                    decoration: const InputDecoration(labelText: 'Notice type'),
                    items: categories
                        .map(
                          (item) =>
                              DropdownMenuItem(value: item, child: Text(item)),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(
                      () => category = value ?? 'Announcement',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Event date (optional)'),
                    subtitle: Text(
                      eventDate == null
                          ? 'No date selected'
                          : '${eventDate!.day}/${eventDate!.month}/${eventDate!.year}',
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: eventDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => eventDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: title,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(labelText: 'Title'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: body,
                    minLines: 10,
                    maxLines: 16,
                    onChanged: (_) => setDialogState(() {}),
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Full notice'),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.photo_camera_outlined),
                    title: Text(
                      photo == null ? 'Add a photo' : 'Photo selected',
                    ),
                    subtitle: const Text('Photos are kept for 7 days'),
                    trailing: photo == null
                        ? const Icon(Icons.add_photo_alternate_outlined)
                        : IconButton(
                            tooltip: 'Remove photo',
                            onPressed: () => setDialogState(() => photo = null),
                            icon: const Icon(Icons.close),
                          ),
                    onTap: () async {
                      final picked = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 82,
                        maxWidth: 1800,
                      );
                      if (picked != null) {
                        setDialogState(() => photo = picked);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: title.text.trim().isEmpty || body.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );
    if (publish != true) {
      title.dispose();
      body.dispose();
      return;
    }
    try {
      final client = Supabase.instance.client;
      final Map<String, dynamic> data = {
        'title': title.text.trim(),
        'body': body.text.trim(),
        'category': category,
        'event_date': eventDate?.toIso8601String(),
        'is_published': true,
      };
      if (photo != null) {
        final extension = photo!.name.split('.').last.toLowerCase();
        final path =
            '${client.auth.currentUser!.id}/${DateTime.now().microsecondsSinceEpoch}.$extension';
        final bytes = await photo!.readAsBytes();
        await client.storage
            .from('notice-photos')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: 'image/$extension',
                upsert: false,
              ),
            );
        data['photo_path'] = path;
        data['photo_url'] = client.storage
            .from('notice-photos')
            .getPublicUrl(path);
        data['photo_expires_at'] = DateTime.now()
            .toUtc()
            .add(const Duration(days: 7))
            .toIso8601String();
      }
      if (existing == null) {
        data['created_by'] = client.auth.currentUser!.id;
        await client.from('church_notices').insert(data);
      } else {
        await client
            .from('church_notices')
            .update(data)
            .eq('id', existing['id']);
      }
      _message('Notice published.');
      await _load();
    } on PostgrestException catch (error) {
      _message('Could not publish notice: ${error.message}');
    } catch (error) {
      _message('Could not publish notice. Please try again.');
      debugPrint('Notice save: $error');
    } finally {
      title.dispose();
      body.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete notice?'),
        content: const Text(
          'This notice will be removed from the church notices page.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await Supabase.instance.client
          .from('church_notices')
          .delete()
          .eq('id', item['id']);
      await _load();
      _message('Notice deleted.');
    } catch (error) {
      _message('Could not delete this notice.');
      debugPrint('Notice delete: $error');
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Secretariat dashboard'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _compose(),
        icon: const Icon(Icons.add),
        label: const Text('New notice'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 25,
                            child: Icon(
                              widget.role == 'SEC'
                                  ? Icons.assignment_ind_outlined
                                  : Icons.verified_user_outlined,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.displayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  widget.role == 'SEC'
                                      ? 'Secretary'
                                      : 'Vice Secretary',
                                ),
                              ],
                            ),
                          ),
                          Text('${_items.length} notices'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Member overview',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Registered',
                          value: '${_members.length}',
                          icon: Icons.groups_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _DashboardMetric(
                          label: 'Largest section',
                          value: _largestSection(),
                          icon: Icons.insights_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.table_view_outlined),
                          title: const Text('Member register'),
                          subtitle: Text(
                            '${_visibleMembers.length} members shown',
                          ),
                          trailing: FilledButton.tonalIcon(
                            onPressed: _members.isEmpty ? null : _exportMembers,
                            icon: const Icon(Icons.file_download_outlined),
                            label: const Text('Excel'),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: DropdownButtonFormField<String>(
                            initialValue: _memberSection,
                            decoration: const InputDecoration(
                              labelText: 'Filter by section',
                            ),
                            items: ['All sections', ..._sections]
                                .map(
                                  (section) => DropdownMenuItem(
                                    value: section,
                                    child: Text(section),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _memberSection = value);
                              }
                            },
                          ),
                        ),
                        if (_visibleMembers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No registered members in this view.'),
                          )
                        else
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('Phone')),
                                DataColumn(label: Text('Section')),
                              ],
                              rows: _visibleMembers
                                  .map(
                                    (member) => DataRow(
                                      cells: [
                                        DataCell(
                                          Text(
                                            member['name']?.toString() ?? '',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            member['phone']?.toString() ?? '',
                                          ),
                                        ),
                                        DataCell(
                                          Text(
                                            member['section']?.toString() ?? '',
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Manage church communications',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  if (_items.isEmpty)
                    const _EmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No notices published',
                      message:
                          'Use New notice to publish the first church update.',
                    )
                  else
                    ..._items.map(
                      (item) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(item['title']?.toString() ?? ''),
                          subtitle: Text(
                            '${item['category'] ?? 'Announcement'} • ${item['event_date']?.toString().split('T').first ?? 'No event date'}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') _compose(item);
                              if (value == 'delete') _delete(item);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _EditProfileDialog extends StatefulWidget {
  const _EditProfileDialog({
    required this.name,
    required this.phone,
    required this.section,
    required this.onSaveProfile,
    required this.messenger,
  });

  final String name;
  final String phone;
  final String section;
  final Future<void> Function(String name, String phone, String section)
  onSaveProfile;
  final ScaffoldMessengerState messenger;

  @override
  State<_EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<_EditProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late String _selectedSection;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _phoneController = TextEditingController(text: widget.phone);
    _selectedSection = widget.section;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (widget.messenger.mounted) {
      widget.messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _save() async {
    final updatedName = _nameController.text.trim();
    final updatedPhone = _phoneController.text.trim();

    if (updatedName.length < 2) {
      _showMessage('Please enter your full name.');
      return;
    }

    if (!RegExp(r'^0\d{9}$').hasMatch(updatedPhone)) {
      _showMessage('Enter a valid 10-digit Zambian number starting with 0.');
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.onSaveProfile(updatedName, updatedPhone, _selectedSection);

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      debugPrint('Member profile update failed: $error');
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
        'Your profile could not be updated. Check your connection and try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit your profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '0971234567',
                prefixIcon: Icon(Icons.phone_outlined),
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedSection,
              decoration: const InputDecoration(
                labelText: 'Congregation section',
                prefixIcon: Icon(Icons.groups_outlined),
              ),
              items: _sections
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _selectedSection = value);
                      }
                    },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save changes'),
        ),
      ],
    );
  }
}

class MorePage extends StatelessWidget {
  const MorePage({
    required this.name,
    required this.section,
    required this.phone,
    required this.onSaveProfile,
    required this.isDark,
    required this.preferences,
    required this.onToggleTheme,
    required this.onTextScaleChanged,
    super.key,
  });

  final String name;
  final String section;
  final String phone;
  final Future<void> Function(String name, String phone, String section)
  onSaveProfile;
  final bool isDark;
  final SharedPreferences preferences;
  final VoidCallback onToggleTheme;
  final ValueChanged<double> onTextScaleChanged;

  Future<void> _changeTextSize(BuildContext context) async {
    var scale = preferences.getDouble('reader_font_scale') ?? 1.0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reading size'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose a comfortable reading size for the whole app.',
              ),
              const SizedBox(height: 18),
              Text(
                'Aa  Sample reading text',
                style: TextStyle(fontSize: 18.0 * scale),
              ),
              Slider(
                value: scale,
                min: .8,
                max: 1.6,
                divisions: 8,
                label: scale < .95
                    ? 'Small'
                    : scale < 1.2
                    ? 'Medium'
                    : scale < 1.45
                    ? 'Large'
                    : 'Extra large',
                onChanged: (value) => setDialogState(() => scale = value),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [Text('Small'), Text('Medium'), Text('Large')],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await preferences.setDouble('reader_font_scale', scale);
                onTextScaleChanged(scale);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save size'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareApp(BuildContext context) async {
    await SharePlus.instance.share(
      ShareParams(
        text: 'Join RCZ - Kanyama, the congregation app for worship, hymns, sermons and more.',
      ),
    );
  }

  Future<void> _openMap(BuildContext context) async {
    final opened = await launchUrl(
      Uri.parse('https://maps.app.goo.gl/SsUcLNk91b63Y4Px6'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the church location.')),
      );
    }
  }

  Future<void> _editProfile(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _EditProfileDialog(
        name: name,
        phone: phone,
        section: section,
        onSaveProfile: onSaveProfile,
        messenger: messenger,
      ),
    );

    if (result == true && context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Your profile has been updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppPage(
      title: 'More',
      subtitle: 'Your church, close at hand',
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _editProfile(context),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: AppDecor.heroGradient(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: colors.primary.withValues(alpha: .18),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _nameInitials(name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                          letterSpacing: .5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MEMBER PROFILE',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: colors.secondary,
                                  letterSpacing: 1.5,
                                  fontSize: 9,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Section $section  •  $phone',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const _SettingsLabel('FAITH & COMMUNITY'),
          const SizedBox(height: 9),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.auto_stories_rounded,
                  title: 'The Bible',
                  subtitle: 'Read and download translations',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BibleHomePage(),
                    ),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.event_outlined,
                  title: 'Church events',
                  subtitle: 'Upcoming gatherings and activities',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const EventsPage()),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.history_edu_outlined,
                  title: 'Church history',
                  subtitle: 'The Reformed Church in Zambia',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChurchHistoryPage(),
                    ),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.account_balance_outlined,
                  title: 'Kanyama Congregation History',
                  subtitle: 'Our own story, pastors and milestones',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CongregationHistoryPage(),
                    ),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.forum_outlined,
                  title: 'Church WhatsApp group',
                  subtitle: 'Stay connected with the congregation',
                  external: true,
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://chat.whatsapp.com/KcKMEjhMR4P8bmyRwBr8lz',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.location_on_outlined,
                  title: 'Find RCZ Kanyama',
                  subtitle: 'Open the church location in Maps',
                  external: true,
                  onTap: () => _openMap(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SettingsLabel('PREFERENCES'),
          const SizedBox(height: 9),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  value: isDark,
                  onChanged: (_) => onToggleTheme(),
                  contentPadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  secondary: const _TintIcon(
                    icon: Icons.dark_mode_outlined,
                    size: 38,
                    radius: 11,
                  ),
                  title: Text(
                    'Dark theme',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    'Comfortable viewing at any time',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.text_fields_rounded,
                  title: 'Reading size',
                  subtitle: 'Adjust text size throughout the app',
                  onTap: () => _changeTextSize(context),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Secretariat access',
                  subtitle: 'Sign in to the authorised church office',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SecretariatAccessPage(),
                    ),
                  ),
                ),
                const _SettingsDivider(),
                _SettingsTile(
                  icon: Icons.perm_media_outlined,
                  title: 'Media Team access',
                  subtitle: 'Manage the congregation history archive',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MediaTeamAccessPage(),
                    ),
                  ),
                ),
                _OwnerAdminTile(),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const _SettingsLabel('ABOUT'),
          const SizedBox(height: 9),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _SettingsTile(
                  icon: Icons.share_outlined,
                  title: 'Share the app',
                  subtitle: 'Invite someone to RCZ Kanyama',
                  onTap: () => _shareApp(context),
                ),
                const _SettingsDivider(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.navy,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Image.asset(
                          'assets/logo_white.png',
                          errorBuilder: (_, _, _) =>
                              Icon(Icons.church, color: colors.primary),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RCZ - Kanyama',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "Kuunika M'mdima - Version 1.0.0",
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'Made by Phineas Chisale Mwale',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.onSurfaceVariant, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

String _nameInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'RCZ';
  if (parts.length == 1) {
    final single = parts.first;
    return (single.length > 1 ? single.substring(0, 2) : single).toUpperCase();
  }
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

class _SettingsLabel extends StatelessWidget {
  const _SettingsLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 1.7,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) =>
      const Divider(indent: 66, endIndent: 16);
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.external = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool external;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            _TintIcon(icon: icon, size: 38, radius: 11),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              external
                  ? Icons.open_in_new_rounded
                  : Icons.chevron_right_rounded,
              size: external ? 16 : 20,
              color: colors.onSurfaceVariant.withValues(alpha: .7),
            ),
          ],
        ),
      ),
    );
  }
}

class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Church events')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
                decoration: BoxDecoration(
                  gradient: AppDecor.heroGradient(context),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -16,
                      bottom: -28,
                      child: Icon(
                        Icons.church_rounded,
                        size: 118,
                        color: Colors.white.withValues(alpha: .07),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TIYENI LIMODZI',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.goldLight,
                                letterSpacing: 1.8,
                              ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Gather. Worship.\nBelong.',
                          style: TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 27,
                            height: 1.14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Worship and fellowship together as one congregation.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const _SectionHeading(
                eyebrow: 'WEEKLY RHYTHM',
                title: 'Services',
                subtitle: 'Come as you are — there is a place for you',
              ),
              const SizedBox(height: 12),
              const _EventServiceCard(
                icon: Icons.wb_sunny_outlined,
                title: 'Sunday Service',
                note: 'Every Sunday',
                sessions: [
                  ('First Service', '06:30'),
                  ('Second Service', '09:30'),
                ],
              ),
              const SizedBox(height: 10),
              const _EventServiceCard(
                icon: Icons.nightlight_outlined,
                title: 'Wednesday Service',
                note: 'Midweek gathering',
                sessions: [('Midweek Service', '15:00')],
              ),
              const SizedBox(height: 22),
              _SectionHeading(
                eyebrow: 'VIGWIRIZANO',
                title: 'Fellowships',
                subtitle: 'Grow together in faith and friendship',
              ),
              const SizedBox(height: 12),
              const _FellowshipCard(),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Times may change on public holidays and special church occasions.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventServiceCard extends StatelessWidget {
  const _EventServiceCard({
    required this.icon,
    required this.title,
    required this.note,
    required this.sessions,
  });

  final IconData icon;
  final String title;
  final String note;
  final List<(String, String)> sessions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TintIcon(icon: icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        note,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(color: colors.outlineVariant),
            const SizedBox(height: 6),
            ...sessions.map(
              (session) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.$1,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        session.$2,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: colors.onPrimaryContainer,
                              fontWeight: FontWeight.w800,
                              letterSpacing: .4,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FellowshipCard extends StatelessWidget {
  const _FellowshipCard();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const fellowships = [
      ("Men's Fellowship", 'Brothers growing in the Word'),
      ("Women's Fellowship", 'Sisters serving together'),
      ('Youth Fellowship', 'Young people walking in faith'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const _TintIcon(icon: Icons.groups_2_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fellowships',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Vigwirizano',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...fellowships.map(
              (fellowship) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.people_outline_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fellowship.$1,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            fellowship.$2,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryMilestone extends StatelessWidget {
  const _HistoryMilestone({
    required this.year,
    required this.title,
    required this.description,
    this.isLast = false,
  });

  final String year;
  final String title;
  final String description;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                const SizedBox(height: 22),
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: colors.secondary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.secondary.withValues(alpha: .25),
                      width: 3,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      margin: const EdgeInsets.only(top: 6),
                      color: colors.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        year.toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.secondary,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall
                            ?.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChurchHistoryPage extends StatelessWidget {
  const ChurchHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Church history')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Container(
                clipBehavior: Clip.antiAlias,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: AppDecor.heroGradient(context),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      top: -26,
                      child: Icon(
                        Icons.auto_stories_rounded,
                        size: 130,
                        color: Colors.white.withValues(alpha: .06),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.navy,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Image.asset(
                            'assets/logo_white.png',
                            errorBuilder: (_, _, _) => Icon(
                              Icons.church_rounded,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'A story of faith,\nservice and grace.',
                          style: TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 26,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            letterSpacing: -.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The Reformed Church in Zambia',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: .72),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'The Reformed Church in Zambia (RCZ) grew from a mission movement '
                'into an independent Zambian church. Its story is connected with '
                'the witness of missionaries, African evangelists and generations '
                'of local Christians who established congregations and ministries '
                'across the country.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.65),
              ),
              const SizedBox(height: 24),
              Text('Milestones', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Moments that shaped the church',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              const _HistoryMilestone(
                year: '1899',
                title: 'The beginning at Magwero',
                description:
                    'On 5 July 1899, mission work associated with the Dutch '
                    'Reformed Church of the Orange Free State was established '
                    'at Magwero in present-day Eastern Province.',
              ),
              const _HistoryMilestone(
                year: '1943',
                title: 'A developing church structure',
                description:
                    'The growing work was organised into a synod within the '
                    'mission church structure, helping congregations develop a '
                    'more coordinated church life.',
              ),
              const _HistoryMilestone(
                year: '1957',
                title: 'African Reformed Church',
                description:
                    'The name African Reformed Church was adopted as the church '
                    'continued to develop its identity and leadership.',
              ),
              const _HistoryMilestone(
                year: '1966',
                title: 'Autonomy',
                description:
                    'On 23 April 1966, the church attained autonomy and '
                    'continued its ministry as a self-governing church in Zambia.',
              ),
              const _HistoryMilestone(
                year: 'Today',
                title: 'A church serving communities',
                description:
                    'The RCZ continues through worship, discipleship, '
                    'evangelism, education, pastoral care and community service '
                    'in different parts of Zambia.',
                isLast: true,
              ),
              const SizedBox(height: 12),
              Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://www.oikoumene.org/member-churches/reformed-church-in-zambia',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const _TintIcon(
                          icon: Icons.public_outlined,
                          size: 38,
                          radius: 11,
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Read the reference',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'World Council of Churches / public history summary',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11.5,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.open_in_new_rounded,
                          size: 17,
                          color: colors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppPage extends StatelessWidget {
  const AppPage({
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ...actions,
                    if (actions.isNotEmpty) const SizedBox(width: 4),
                    Container(
                      width: 42,
                      height: 42,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppColors.navy,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset(
                          'assets/logo_white.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.church_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _TintIcon(icon: icon, size: 36, radius: 10),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
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

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.initials,
    required this.onOpenNotices,
    required this.onOpenProfile,
    this.noticeCount = 0,
  });

  final String initials;
  final VoidCallback onOpenNotices;
  final VoidCallback onOpenProfile;
  final int noticeCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: AppColors.navy,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant),
            boxShadow: AppDecor.softShadow(context),
          ),
          child: Image.asset(
            'assets/logo_white.png',
            errorBuilder: (_, _, _) =>
                Icon(Icons.church_rounded, color: colors.primary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RCZ KANYAMA',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.primary, letterSpacing: 2.2),
              ),
              const SizedBox(height: 3),
              Text(
                'Reformed Church in Zambia',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Badge(
          isLabelVisible: noticeCount > 0,
          label: Text(
            noticeCount > 99 ? '99+' : '$noticeCount',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
          child: _HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Church notices',
            onTap: onOpenNotices,
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'Your profile',
          child: GestureDetector(
            onTap: onOpenProfile,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: AppDecor.heroGradient(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.primary.withValues(alpha: .2)),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: .4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: colors.outlineVariant),
            ),
            child: Icon(icon, size: 21, color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: colors.primary.withValues(alpha: .08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onPrimaryContainer),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.secondary, letterSpacing: 1.7),
        ),
        const SizedBox(height: 5),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _TintIcon extends StatelessWidget {
  const _TintIcon({
    required this.icon,
    this.size = 40,
    this.radius = 12,
    this.background,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final double radius;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background ?? colors.primaryContainer,
        borderRadius: BorderRadius.circular(radius),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: size * .5, color: foreground ?? colors.primary),
    );
  }
}

class _VerseShowcase extends StatelessWidget {
  const _VerseShowcase({
    required this.verse,
    required this.index,
    required this.total,
    required this.onNext,
  });

  final (String, String, String) verse;
  final int index;
  final int total;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: AppDecor.heroGradient(context),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.navyDeep.withValues(alpha: .22),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            top: -26,
            child: Icon(
              Icons.format_quote_rounded,
              size: 150,
              color: Colors.white.withValues(alpha: .06),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 3, color: AppColors.gold),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 18, height: 2, color: AppColors.gold),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'VERSE FOR TODAY',
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.goldLight,
                                letterSpacing: 1.8,
                              ),
                        ),
                      ),
                    ),
                    Text(
                      '${(index + 1).toString().padLeft(2, '0')} / '
                      '${total.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white.withValues(alpha: .45),
                        letterSpacing: .8,
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'Next verse',
                      onPressed: onNext,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.white70,
                        minimumSize: const Size(34, 34),
                        padding: const EdgeInsets.all(6),
                      ),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AnimatedSize(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 450),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: AlignmentDirectional.topStart,
                      children: [?currentChild],
                    ),
                    transitionBuilder: (child, animation) =>
                        FadeTransition(opacity: animation, child: child),
                    child: Column(
                      key: ValueKey(verse.$2),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          verse.$1,
                          style: const TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 22,
                            fontStyle: FontStyle.italic,
                            height: 1.42,
                            letterSpacing: .1,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          verse.$3,
                          style: TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            height: 1.5,
                            color: Colors.white.withValues(alpha: .7),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Text(
                              verse.$2.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AppColors.goldLight,
                                    letterSpacing: 1.6,
                                  ),
                            ),
                            const Spacer(),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(total, (dot) {
                                final active = dot == index;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  width: active ? 14 : 5,
                                  height: 5,
                                  margin: const EdgeInsets.only(left: 5),
                                  decoration: BoxDecoration(
                                    color: active
                                        ? AppColors.goldLight
                                        : Colors.white.withValues(alpha: .22),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceTimesCard extends StatelessWidget {
  const _ServiceTimesCard({required this.onOpenEvents});

  final VoidCallback onOpenEvents;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenEvents,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            children: [
              Row(
                children: [
                  _TintIcon(icon: Icons.church_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sunday worship',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Come and worship with us',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: colors.outlineVariant),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _ServiceTime(
                      label: 'FIRST SERVICE',
                      time: '06:30',
                      suffix: 'AM',
                    ),
                  ),
                  Container(width: 1, height: 44, color: colors.outlineVariant),
                  Expanded(
                    child: _ServiceTime(
                      label: 'SECOND SERVICE',
                      time: '09:30',
                      suffix: 'AM',
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTime extends StatelessWidget {
  const _ServiceTime({
    required this.label,
    required this.time,
    required this.suffix,
    this.alignEnd = false,
  });

  final String label;
  final String time;
  final String suffix;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 1.2,
            fontSize: 9.5,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              time,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              suffix,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: colors.onSurfaceVariant, letterSpacing: .6),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickActionGrid extends StatelessWidget {
  const _QuickActionGrid({required this.onOpenPage});

  final ValueChanged<int> onOpenPage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actions = [
      (Icons.play_circle_outline_rounded, 'Sermons', 'Watch and listen', 1),
      (Icons.menu_book_outlined, 'Nyimbo', 'Hymnbook', 2),
      (Icons.edit_note_outlined, 'Notes', 'Your reflections', 3),
      (Icons.campaign_outlined, 'Notices', 'From the office', 4),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.95,
      ),
      itemBuilder: (_, index) {
        final action = actions[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onOpenPage(action.$4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _TintIcon(icon: action.$1, size: 36, radius: 11),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          action.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          action.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: colors.onSurfaceVariant,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 17,
                    color: colors.onSurfaceVariant.withValues(alpha: .6),
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

class _BiblePromoCard extends StatelessWidget {
  const _BiblePromoCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: AppDecor.heroGradient(context),
          borderRadius: BorderRadius.circular(22),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              Positioned(
                right: -12,
                bottom: -18,
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 124,
                  color: Colors.white.withValues(alpha: .07),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SCRIPTURE LIBRARY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.goldLight,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'The Word,\nalways with you.',
                      style: TextStyle(
                        fontFamily: 'SourceSerif4',
                        fontSize: 26,
                        height: 1.14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Read the Bible in Chichewa and English — available '
                      'offline once downloaded.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: Colors.white.withValues(alpha: .72),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .14),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.menu_book_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          SizedBox(width: 7),
                          Text(
                            'Open Bible',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          SizedBox(width: 6),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                        ],
                      ),
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

class _ExploreChurchCard extends StatelessWidget {
  const _ExploreChurchCard({
    required this.onOpenNotices,
    required this.onOpenEvents,
    required this.onOpenHistory,
  });

  final VoidCallback onOpenNotices;
  final VoidCallback onOpenEvents;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ExploreTile(
            icon: Icons.campaign_outlined,
            title: 'Church announcements',
            subtitle: 'Official updates from the Secretariat',
            onTap: onOpenNotices,
          ),
          const Divider(indent: 68, endIndent: 16),
          _ExploreTile(
            icon: Icons.event_available_outlined,
            title: 'Church events',
            subtitle: 'Services, prayer and fellowship',
            onTap: onOpenEvents,
          ),
          const Divider(indent: 68, endIndent: 16),
          _ExploreTile(
            icon: Icons.history_edu_outlined,
            title: 'Our story',
            subtitle: 'Discover the Reformed Church in Zambia',
            onTap: onOpenHistory,
          ),
        ],
      ),
    );
  }
}

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Row(
          children: [
            _TintIcon(icon: icon, size: 38, radius: 11),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: colors.onSurfaceVariant.withValues(alpha: .7),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutChurchCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const _TintIcon(icon: Icons.church_outlined, size: 38),
        title: Text(
          'About our church',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: Text(
          'Worship, fellowship and service',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'RCZ Kanyama is a Reformed Christian congregation in Lusaka. '
              'We gather to worship God, learn from Scripture, encourage one '
              'another and serve our community. You are always welcome.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.onSurfaceVariant, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: .08),
                  ),
                ),
                child: Icon(icon, size: 29, color: colors.primary),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant, height: 1.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _OwnerAdminTile extends StatefulWidget {
  const _OwnerAdminTile();

  @override
  State<_OwnerAdminTile> createState() => _OwnerAdminTileState();
}

class _OwnerAdminTileState extends State<_OwnerAdminTile> {
  bool? _isOwner;
  bool _checking = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (_) => unawaited(_check()),
    );
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    if (mounted) setState(() => _isOwner = null);
    try {
      final result = await Supabase.instance.client.rpc('is_owner_admin');
      if (!mounted) return;
      setState(() => _isOwner = result == true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isOwner = false);
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isOwner != true) return const SizedBox.shrink();
    return Column(
      children: [
        const _SettingsDivider(),
        _SettingsTile(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Admin Dashboard',
          subtitle: 'Owner-only administration',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const AdminDashboardPage(),
            ),
          ),
        ),
      ],
    );
  }
}


class _AndroidEmbedPlayer extends StatefulWidget {
  const _AndroidEmbedPlayer({required this.videoId});
  final String? videoId;

  @override
  State<_AndroidEmbedPlayer> createState() => _AndroidEmbedPlayerState();
}

class _AndroidEmbedPlayerState extends State<_AndroidEmbedPlayer> {
  WebViewController? _webController;
  Route<void>? _fullscreenRoute;

  @override
  void initState() {
    super.initState();
    _load(widget.videoId);
  }

  @override
  void didUpdateWidget(covariant _AndroidEmbedPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) _load(widget.videoId);
  }

  Future<void> _load(String? videoId) async {
    if (videoId == null || videoId.isEmpty) return;

    final controller = WebViewController();
    _webController = controller;
    final platformController = controller.platform;

    if (platformController is AndroidWebViewController) {
      platformController.setCustomWidgetCallbacks(
        onShowCustomWidget: (Widget widget, OnHideCustomWidgetCallback _) {
          if (!mounted || _fullscreenRoute?.isActive == true) return;

          final route = MaterialPageRoute<void>(
            builder: (BuildContext context) => widget,
            fullscreenDialog: true,
          );

          _fullscreenRoute = route;

          unawaited(
            Navigator.of(context).push<void>(route).whenComplete(() {
              if (identical(_fullscreenRoute, route)) {
                _fullscreenRoute = null;
              }
            }),
          );
        },
        onHideCustomWidget: () {
          final route = _fullscreenRoute;

          if (!mounted ||
              route == null ||
              !route.isActive ||
              !route.isCurrent) {
            return;
          }

          Navigator.of(context).pop();
        },
      );
    }

    if (mounted) setState(() {});

    await controller.setJavaScriptMode(
      JavaScriptMode.unrestricted,
    );

    await controller.loadRequest(
      Uri.parse(
        'https://www.youtube.com/embed/$videoId?playsinline=1&rel=0',
      ),
      headers: {
        'Referer': 'https://rcz-kanyama-web.vercel.app/',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _webController;
    if (c == null) {
      return const Center(child: CircularProgressIndicator(color: Colors.white70));
    }
    return WebViewWidget(controller: c);
  }
}


