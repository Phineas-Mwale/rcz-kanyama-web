import 'dart:async';
import 'dart:convert';

import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'supabase_config.dart';
import 'features/bible/presentation/bible_home_page.dart';

const _brandBlue = Color(0xFF34358F);
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
  }

  Future<void> _saveProfile(String name, String phone, String section) async {
    // Save to the device only after Supabase confirms the profile update.
    await _syncMember(
      name,
      phone,
      section,
      throwOnFailure: true,
    );

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
    final lightScheme = ColorScheme.fromSeed(
      seedColor: _brandBlue,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: _brandBlue,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'RCZ - Kanyama',
      debugShowCheckedModeBanner: false,
      themeMode: _isDark ? ThemeMode.dark : ThemeMode.light,
      theme: _theme(lightScheme),
      darkTheme: _theme(darkScheme),
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

  ThemeData _theme(ColorScheme colors) {
    return ThemeData(
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: colors.surfaceContainerLow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        elevation: 0,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: .45),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final isNameStep = _step == 0;
    final isPhoneStep = _step == 1;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.94, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, scale, child) => Opacity(
                opacity: ((scale - 0.94) / 0.06).clamp(0, 1),
                child: Transform.scale(scale: scale, child: child),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Image.asset(
                      'assets/logo1.png',
                      height: 150,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.church,
                        size: 120,
                        color: _brandBlue,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'RCZ - Kanyama',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: _brandBlue,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kuunika M’mdima',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 50),
                    Text(
                      isNameStep
                          ? 'Welcome home'
                          : isPhoneStep
                          ? 'Stay connected'
                          : 'Find your section',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isNameStep
                          ? 'What should we call you?'
                          : isPhoneStep
                          ? 'Add your Zambian mobile number'
                          : 'Which section do you worship with?',
                    ),
                    const SizedBox(height: 24),
                    if (isNameStep)
                      TextField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _next(),
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      )
                    else if (isPhoneStep)
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
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 1.65,
                            ),
                        itemCount: _sections.length,
                        itemBuilder: (_, index) {
                          final section = _sections[index];
                          final selected = _section == section;
                          final colors = Theme.of(context).colorScheme;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            decoration: BoxDecoration(
                              color: selected
                                  ? colors.primary
                                  : colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: selected
                                    ? colors.primary
                                    : colors.outlineVariant,
                                width: selected ? 1.6 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: colors.primary.withValues(
                                          alpha: .16,
                                        ),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : const [],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () => setState(() => _section = section),
                                child: Center(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (selected) ...[
                                        const Icon(
                                          Icons.check_circle,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(
                                        section,
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : colors.onSurface,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _saving ? null : _next,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isNameStep ? 'Continue' : 'Enter the app'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This helps us welcome you personally. You can change these details later.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _noticeCount = 0;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _refreshNoticeCount();
    _noticeTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshNoticeCount(),
    );
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshNoticeCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('church_notices')
          .select('id')
          .eq('is_published', true);
      if (mounted) setState(() => _noticeCount = rows.length);
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
      ),
      SermonsPage(preferences: widget.preferences),
      HymnsPage(preferences: widget.preferences),
      NotesPage(preferences: widget.preferences),
      const NoticesPage(),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outline),
            label: 'Sermons',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            label: 'Nyimbo',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: _noticeCount == 0
                ? Icon(Icons.campaign_outlined)
                : Badge(
                    label: Text(_noticeCount > 99 ? '99+' : '$_noticeCount'),
                    child: const Icon(Icons.campaign_outlined),
                  ),
            label: 'Notices',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    required this.name,
    required this.section,
    required this.onOpenPage,
    super.key,
  });

  final String name;
  final String section;
  final ValueChanged<int> onOpenPage;

  static const _verses = [
    (
      '“The Lord is my shepherd; I shall not want.”',
      'Psalm 23:1',
      '“Ambuye ndiye m’busa wanga; sindidzasowa kanthu.”',
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
      DateTime.now().difference(DateTime(2024)).inDays %
      HomePage._verses.length;
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
    return AppPage(
      title: 'Hello, ${widget.name}',
      subtitle: 'RCZ - Kanyama • Section ${widget.section}',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Text(
            'A moment for the Word',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          _VerseCard(verse: verse),
          const SizedBox(height: 18),
          Text(
            'Our worship times',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Expanded(
                child: _InfoCard(
                  icon: Icons.wb_sunny_outlined,
                  title: 'First service',
                  value: '06:30',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _InfoCard(
                  icon: Icons.wb_twilight_outlined,
                  title: 'Second service',
                  value: '09:30',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Tiyeni limodzi', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 18),
          _ActionGrid(onOpenPage: widget.onOpenPage),
          const SizedBox(height: 14),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
              title: const Text(
                'Read the Bible',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('Explore Scripture in Chichewa and more'),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const BibleHomePage()),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: const Text('Church announcements'),
                  subtitle: const Text(
                    'Keep up with notices from the Secretariat',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => widget.onOpenPage(4),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_available_outlined),
                  title: const Text('Church events'),
                  subtitle: const Text('Services, prayer and fellowship'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const EventsPage()),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history_edu_outlined),
                  title: const Text('Our story'),
                  subtitle: const Text(
                    'Discover the Reformed Church in Zambia',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChurchHistoryPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.church_outlined),
              title: const Text('About our church'),
              subtitle: const Text('Worship, fellowship and service'),
              childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              children: const [
                Text(
                  'RCZ Kanyama is a Reformed Christian congregation in Lusaka. We gather to worship God, learn from Scripture, encourage one another and serve our community. You are always welcome.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SermonVideo {
  const SermonVideo({
    required this.id,
    required this.title,
    this.publishedAt,
    this.thumbnail,
  });

  final String id;
  final String title;
  final DateTime? publishedAt;
  final String? thumbnail;

  factory SermonVideo.fromJson(Map<String, dynamic> json) {
    final idValue = json['videoId'] ?? json['video_id'] ?? json['id'];
    final id = idValue is Map
        ? (idValue['videoId'] ?? idValue['video_id'] ?? '').toString()
        : (idValue ?? '').toString();
    final published =
        json['publishedAt'] ?? json['published_at'] ?? json['publishedTime'];
    return SermonVideo(
      id: id,
      title: (json['title'] ?? 'RCZ - Kanyama service').toString(),
      publishedAt: published == null
          ? null
          : DateTime.tryParse(published.toString()),
      thumbnail:
          json['thumbnail']?.toString() ?? json['thumbnailUrl']?.toString(),
    );
  }
}

class SermonsPage extends StatefulWidget {
  const SermonsPage({required this.preferences, super.key});
  final SharedPreferences preferences;

  @override
  State<SermonsPage> createState() => _SermonsPageState();
}

class _SermonsPageState extends State<SermonsPage> {
  static const _fallback = [
    SermonVideo(id: 'GYd4KOvEutA', title: 'Recent worship service'),
    SermonVideo(id: 'K73245kzX1I', title: 'Recent worship service'),
    SermonVideo(id: '2cEjuD0NOOo', title: 'Recent worship service'),
    SermonVideo(id: 'yzUp9XYzojQ', title: 'Recent worship service'),
  ];

  late final YoutubePlayerController _controller;
  final Set<String> _favourites = {};
  List<SermonVideo> _videos = _fallback;
  int _selectedVideo = 0;
  bool _loading = false;
  bool _showSavedOnly = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _favourites.addAll(
      widget.preferences.getStringList('sermon_favourites') ?? const [],
    );
    _controller = YoutubePlayerController.fromVideoId(
      videoId: _fallback.first.id,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableJavaScript: true,
        playsInline: false,
        origin: 'https://www.youtube-nocookie.com',
      ),
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
    _controller.close();
    super.dispose();
  }

  Future<void> _refreshSermons({bool showMessage = true}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      try {
        await Supabase.instance.client.functions.invoke('sync-youtube-sermons');
      } catch (error) {
        debugPrint('YouTube sermon sync unavailable: $error');
      }
      final response = await Supabase.instance.client
          .from('sermons')
          .select()
          .order('published_at', ascending: false)
          .limit(10);
      final loaded = <SermonVideo>[];
      for (final item in response) {
        final video = SermonVideo.fromJson(item);
        if (video.id.isNotEmpty) {
          loaded.add(video);
        }
      }
      if (!mounted) return;
      setState(() {
        if (loaded.isNotEmpty) {
          _videos = loaded;
          _selectedVideo = 0;
        } else {}
      });
      if (loaded.isNotEmpty) {
        await _controller.loadVideoById(videoId: loaded.first.id);
      }
    } catch (error) {
      if (!mounted) return;
      debugPrint('Sermon refresh failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (showMessage && mounted && _videos.length > 1) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sermons refreshed.')));
    }
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

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Sermons',
      subtitle: 'Mauthenga a moyo • Watch and grow in the Word',
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
                  YoutubePlayer(controller: _controller, aspectRatio: 16 / 9),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _videos.isEmpty
                              ? 'Sermons from RCZ Kanyama'
                              : _videos[_selectedVideo < _videos.length
                                        ? _selectedVideo
                                        : 0]
                                    .title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Latest messages',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: _showSavedOnly
                          ? 'Show all sermons'
                          : 'Show saved sermons',
                      onPressed: () =>
                          setState(() => _showSavedOnly = !_showSavedOnly),
                      icon: Icon(
                        _showSavedOnly ? Icons.bookmark : Icons.bookmark_border,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_videos.isNotEmpty)
                  ..._videos
                      .asMap()
                      .entries
                      .where(
                        (entry) =>
                            !_showSavedOnly ||
                            _favourites.contains(entry.value.id),
                      )
                      .take(10)
                      .map((entry) {
                        final index = entry.key;
                        final video = entry.value;
                        final saved = _favourites.contains(video.id);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          clipBehavior: Clip.antiAlias,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                video.thumbnail ??
                                    'https://img.youtube.com/vi/${video.id}/mqdefault.jpg',
                                width: 104,
                                height: 66,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 104,
                                  height: 66,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  child: const Icon(Icons.play_circle_outline),
                                ),
                              ),
                            ),
                            title: Text(
                              video.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              index == _selectedVideo
                                  ? 'Now playing'
                                  : 'Watch sermon',
                              style: TextStyle(
                                color: index == _selectedVideo
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                fontWeight: index == _selectedVideo
                                    ? FontWeight.w700
                                    : null,
                              ),
                            ),
                            tileColor: index == _selectedVideo
                                ? Theme.of(context).colorScheme.primaryContainer
                                      .withValues(alpha: .45)
                                : null,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: index == _selectedVideo
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                              ),
                            ),
                            onTap: () async {
                              setState(() => _selectedVideo = index);
                              await _controller.loadVideoById(
                                videoId: video.id,
                              );
                            },
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: saved
                                      ? 'Remove from saved'
                                      : 'Save sermon',
                                  onPressed: () => _toggleFavourite(video.id),
                                  icon: Icon(
                                    saved
                                        ? Icons.bookmark
                                        : Icons.bookmark_border,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Share sermon',
                                  onPressed: () => _shareVideo(video),
                                  icon: const Icon(Icons.share_outlined),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
              ],
            ),
          ),
        ],
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
        (line) =>
            line.replaceFirst(RegExp(r'^(?:\d+|[IVX]+)[.)]?\s*'), '').trim(),
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
    return AppPage(
      title: 'Nyimbo',
      subtitle: 'Offline hymnbook • Chichewa and English',
      actions: [
        IconButton(
          tooltip: 'Search hymns',
          onPressed: () async {
            final query = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Search hymns'),
                content: TextField(
                  autofocus: true,
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Number, title or words',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (value) => Navigator.pop(context, value),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, _searchController.text),
                    child: const Text('Search'),
                  ),
                ],
              ),
            );
            if (query != null && mounted) setState(() {});
          },
          icon: const Icon(Icons.search),
        ),
        PopupMenuButton<bool>(
          tooltip: 'Language',
          initialValue: _english,
          onSelected: (value) => setState(() => _english = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: false, child: Text('Chichewa')),
            PopupMenuItem(value: true, child: Text('English')),
          ],
          icon: const Icon(Icons.translate),
        ),
        IconButton(
          tooltip: _showFavouritesOnly ? 'Show all hymns' : 'Favourite hymns',
          onPressed: () =>
              setState(() => _showFavouritesOnly = !_showFavouritesOnly),
          icon: Icon(
            _showFavouritesOnly ? Icons.favorite : Icons.favorite_border,
          ),
        ),
      ],
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
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(children: [const SizedBox(height: 4)]),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: visible.length,
                  itemBuilder: (_, index) {
                    final hymn = visible[index];
                    final title = _english
                        ? hymn.englishTitle
                        : hymn.chichewaTitle;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          child: Text('${hymn.number}'),
                        ),
                        title: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          (_english ? hymn.englishText : hymn.chichewaText)
                                  .trim()
                                  .isEmpty
                              ? 'Lyrics not yet in this language file'
                              : (_english
                                    ? 'English edition'
                                    : 'Chichewa edition'),
                        ),
                        onTap: () => _openHymn(hymn),
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
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'HYMN ${widget.hymn.number}  •  ${widget.languageLabel.toUpperCase()}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.lyrics.trim().isEmpty
                          ? 'Hymn ${widget.hymn.number}'
                          : _hymnTitle(widget.lyrics, widget.hymn.number),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                                  fontFamily: 'serif',
                                  fontSize: 20.0 * _readerScale,
                                  height: 1.48,
                                  letterSpacing: .15,
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
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
  List<Note> _notes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadNotes() {
    try {
      final saved = widget.preferences.getString('notes');
      if (saved != null && saved.isNotEmpty) {
        _notes = (jsonDecode(saved) as List)
            .map((item) => Note.fromJson(item as Map<String, dynamic>))
            .toList();
        _notes.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
      }
    } catch (error) {
      debugPrint('Saved notes could not be decoded: $error');
      _notes = [];
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveNotes() async {
    await widget.preferences.setString(
      'notes',
      jsonEncode(_notes.map((note) => note.toJson()).toList()),
    );
  }

  Future<void> _editNote([Note? note]) async {
    final result = await showModalBottomSheet<Note>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => NoteEditor(note: note),
    );
    if (result == null) return;
    setState(() {
      if (note == null) {
        _notes.insert(0, result);
      } else {
        final index = _notes.indexOf(note);
        _notes[index] = result;
      }
    });
    await _saveNotes();
  }

  Future<void> _viewNote(Note note) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NoteViewPage(
          note: note,
          fontScale: 1.0,
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
    setState(() => _notes.remove(note));
    await _saveNotes();
  }

  Future<void> _togglePin(Note note) async {
    final index = _notes.indexOf(note);
    if (index < 0) return;
    setState(() {
      _notes[index] = Note(
        id: note.id,
        title: note.title,
        body: note.body,
        updatedAt: DateTime.now(),
        isPinned: !note.isPinned,
      );
      _notes.sort(
        (a, b) => b.isPinned.toString().compareTo(a.isPinned.toString()),
      );
    });
    await _saveNotes();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final query = _searchController.text.trim().toLowerCase();
    final notes = _notes
        .where(
          (note) =>
              query.isEmpty ||
              note.title.toLowerCase().contains(query) ||
              note.body.toLowerCase().contains(query),
        )
        .toList();
    return AppPage(
      title: 'Notes',
      subtitle: 'Keep what speaks to your heart',
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Search your notes',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: notes.isEmpty
                    ? const _EmptyState(
                        icon: Icons.edit_note,
                        title: 'Start a new note',
                        message: 'Write sermon highlights, prayer points, reminders and ideas. Your notes are only visible to you.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                        itemCount: notes.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final note = notes[index];
                          return Dismissible(
                            key: ValueKey(note.id),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 20),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                note.isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin,
                                color: Colors.white,
                              ),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.error,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.delete_outline,
                                color: Colors.white,
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
                              setState(() => _notes.remove(note));
                              await _saveNotes();
                            },
                            child: Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.fromLTRB(
                                  18,
                                  10,
                                  10,
                                  10,
                                ),
                                leading: CircleAvatar(
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                                  child: Icon(
                                    note.isPinned
                                        ? Icons.push_pin
                                        : Icons.notes_outlined,
                                  ),
                                ),
                                title: Text(
                                  note.title.isEmpty
                                      ? 'Untitled note'
                                      : note.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${note.body}\n${_formatDate(note.updatedAt)}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onTap: () => _viewNote(note),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') _editNote(note);
                                    if (value == 'pin') _togglePin(note);
                                    if (value == 'delete') _deleteNote(note);
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
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
              icon: const Icon(Icons.add),
              label: const Text('New note'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day}/${date.month}/${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedAt,
    required this.isPinned,
  });

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'] as String,
    title: json['title'] as String,
    body: json['body'] as String,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    isPinned: json['isPinned'] as bool? ?? false,
  );

  final String id;
  final String title;
  final String body;
  final DateTime updatedAt;
  final bool isPinned;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'updatedAt': updatedAt.toIso8601String(),
    'isPinned': isPinned,
  };
}

List<InlineSpan> _noteSpans(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final pattern = RegExp(r'(\*\*.+?\*\*|\*.+?\*|__.+?__)');
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final token = match.group(0)!;
    if (token.startsWith('**')) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(fontWeight: FontWeight.bold),
        ),
      );
    } else if (token.startsWith('__')) {
      spans.add(
        TextSpan(
          text: token.substring(2, token.length - 2),
          style: base.copyWith(decoration: TextDecoration.underline),
        ),
      );
    } else {
      spans.add(
        TextSpan(
          text: token.substring(1, token.length - 1),
          style: base.copyWith(fontStyle: FontStyle.italic),
        ),
      );
    }
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}

class NoteViewPage extends StatelessWidget {
  const NoteViewPage({
    required this.note,
    required this.fontScale,
    required this.onEdit,
    super.key,
  });

  final Note note;
  final double fontScale;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodyLarge!
        .copyWith(fontSize: 17.0 * fontScale, height: 1.75);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My note'),
        actions: [
          IconButton(
            tooltip: 'Edit note',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 36),
        children: [
          Row(
            children: [
              if (note.isPinned)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.push_pin, size: 18, color: colors.primary),
                ),
              Text(
                note.isPinned ? 'PINNED NOTE' : 'PERSONAL NOTE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            note.title.isEmpty ? 'Untitled note' : note.title,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 8),
          Text(
            'Updated ${note.updatedAt.day}/${note.updatedAt.month}/${note.updatedAt.year}',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          Divider(color: colors.outlineVariant),
          const SizedBox(height: 18),
          SelectableText.rich(
            TextSpan(style: base, children: _noteSpans(note.body, base)),
          ),
        ],
      ),
    );
  }
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({this.note, super.key});

  final Note? note;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late final _titleController = TextEditingController(
    text: widget.note?.title ?? '',
  );
  late final _bodyController = TextEditingController(
    text: widget.note?.body ?? '',
  );
  late bool _isPinned = widget.note?.isPinned ?? false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _wrapSelection(String marker) {
    final value = _bodyController.value;
    final selection = value.selection;
    if (!selection.isValid || selection.isCollapsed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select some text first, then choose formatting.'),
        ),
      );
      return;
    }
    final selected = value.text.substring(selection.start, selection.end);
    final replacement = '$marker$selected$marker';
    final updated = value.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    _bodyController.value = value.copyWith(
      text: updated,
      selection: TextSelection.collapsed(
        offset: selection.start + replacement.length,
      ),
      composing: TextRange.empty,
    );
  }

  void _save() {
    if (_bodyController.text.trim().isEmpty &&
        _titleController.text.trim().isEmpty) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(
      context,
      Note(
        id: widget.note?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        updatedAt: DateTime.now(),
        isPinned: _isPinned,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.note == null ? 'New note' : 'Edit note',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Title',
                prefixIcon: Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Bold selected text',
                  onPressed: () => _wrapSelection('**'),
                  icon: const Icon(Icons.format_bold),
                ),
                IconButton(
                  tooltip: 'Italic selected text',
                  onPressed: () => _wrapSelection('*'),
                  icon: const Icon(Icons.format_italic),
                ),
                IconButton(
                  tooltip: 'Underline selected text',
                  onPressed: () => _wrapSelection('__'),
                  icon: const Icon(Icons.format_underlined),
                ),
              ],
            ),
            TextField(
              controller: _bodyController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 6,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Write your note',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPinned,
              onChanged: (value) => setState(() => _isPinned = value),
              title: const Text('Pin this note'),
              secondary: const Icon(Icons.push_pin_outlined),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('Save note'),
            ),
          ],
        ),
      ),
    );
  }
}

class NoticesPage extends StatefulWidget {
  const NoticesPage({super.key});

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notices = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await Supabase.instance.client
          .from('church_notices')
          .select('id,title,body,category,event_date,created_at,photo_url')
          .eq('is_published', true)
          .order('created_at', ascending: false);
      if (!mounted) return;
      setState(() => _notices = List<Map<String, dynamic>>.from(rows));
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

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Church notices',
      subtitle: 'Official announcements and updates',
      child: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
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
                children: const [
                  SizedBox(height: 100),
                  _EmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No notices yet',
                    message: 'Official notices from the Secretariat will appear here.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: _notices.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = _notices[index];
                  final category = (item['category'] ?? 'Announcement')
                      .toString();
                  return Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        showDragHandle: true,
                        builder: (context) => SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (item['photo_url'] != null) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: GestureDetector(
                                        onTap: () => showDialog<void>(
                                          context: context,
                                          builder: (_) => Dialog(
                                            child: InteractiveViewer(
                                              child: Image.network(
                                                item['photo_url'].toString(),
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ),
                                        child: Image.network(
                                          item['photo_url'].toString(),
                                          width: double.infinity,
                                          height: 190,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  Text(
                                    category.toUpperCase(),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    item['title']?.toString() ?? '',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _date(
                                      item['event_date'] ?? item['created_at'],
                                    ),
                                  ),
                                  const Divider(height: 28),
                                  SelectableText(
                                    item['body']?.toString() ?? '',
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(17),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item['photo_url'] != null) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: GestureDetector(
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => Dialog(
                                      child: InteractiveViewer(
                                        child: Image.network(
                                          item['photo_url'].toString(),
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                  ),
                                  child: Image.network(
                                    item['photo_url'].toString(),
                                    width: double.infinity,
                                    height: 150,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    category,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _date(
                                    item['event_date'] ?? item['created_at'],
                                  ),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              item['title']?.toString() ?? '',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item['body']?.toString() ?? '',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'Read notice  →',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
  bool _creating = false;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _requestedRole(String name) {
    final value = name.trim().toUpperCase();
    if (value.endsWith('VSEC')) return 'VSEC';
    if (value.endsWith('SEC')) return 'SEC';
    return null;
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
    final role = _creating ? _requestedRole(name) : null;

    if (_creating && (name.isEmpty || role == null)) {
      _message('Enter your full name ending in SEC or VSEC.');
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
        } else {
          await _checkAccess(response.user!.id, role);
        }
      } else {
        final response = await auth.signInWithPassword(
          email: email,
          password: password,
        );
        final user = response.user;
        if (user == null) {
          _message('Login was unsuccessful.');
        } else {
          await _checkAccess(user.id, null);
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

  Future<void> _checkAccess(String userId, String? requestedRole) async {
    final row = await Supabase.instance.client
        .from('secretariat_accounts')
        .select('role,is_active,display_name')
        .eq('user_id', userId)
        .maybeSingle();
    if (!mounted) return;
    if (row == null || row['is_active'] != true) {
      _message(
        'Your account exists, but Secretariat access has not yet been authorised by the church administrator.',
      );
      return;
    }
    final role = row['role']?.toString().toUpperCase();
    if (role != 'SEC' && role != 'VSEC') {
      _message('This account does not have a valid Secretariat role.');
      return;
    }
    if (requestedRole != null && role != requestedRole) {
      _message(
        'The SEC/VSEC suffix does not match the role assigned to this account.',
      );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Secretariat access')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 58,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 14),
          Text(
            _creating ? 'Create Secretariat account' : 'Welcome back',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'This area is for church office bearers only. Register with your email address and contact phone number. Secretariat access is granted only after the church administrator approves your account.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_creating) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Full name (end with SEC or VSEC)',
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
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
      _showMessage(
        'Enter a valid 10-digit Zambian number starting with 0.',
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await widget.onSaveProfile(
        updatedName,
        updatedPhone,
        _selectedSection,
      );

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
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    ),
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
        const SnackBar(
          content: Text('Your profile has been updated.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'More',
      subtitle: 'Your church, close at hand',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(name),
              subtitle: Text('Section $section • $phone'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editProfile(context),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.auto_stories_rounded),
                  title: const Text('The Bible'),
                  subtitle: const Text('Read and download Bible translations'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const BibleHomePage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  value: isDark,
                  onChanged: (_) => onToggleTheme(),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Dark mode'),
                  subtitle: const Text('Comfortable viewing at any time'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.text_fields_rounded),
                  title: const Text('Reading size'),
                  subtitle: const Text('Adjust text size throughout the app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _changeTextSize(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Secretariat access'),
                  subtitle: const Text(
                    'Sign in to the authorised church office',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SecretariatAccessPage(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_outlined),
                  title: const Text('Church events'),
                  subtitle: const Text('Upcoming gatherings and activities'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const EventsPage()),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.history_edu_outlined),
                  title: const Text('Church history'),
                  subtitle: const Text('The Reformed Church in Zambia'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ChurchHistoryPage(),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.forum_outlined),
                  title: const Text('Church WhatsApp group'),
                  subtitle: const Text('Stay connected with the congregation'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => launchUrl(
                    Uri.parse(
                      'https://chat.whatsapp.com/KcKMEjhMR4P8bmyRwBr8lz',
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Find RCZ Kanyama'),
                  subtitle: const Text('Open church location in Maps'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openMap(context),
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: const Text('Share the app'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _shareApp(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.church_outlined),
              title: const Text('RCZ - Kanyama'),
              subtitle: const Text('Kuunika M’mdima • Version 1.0.0'),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'Made by Phineas Chisale Mwale',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}



class EventsPage extends StatelessWidget {
  const EventsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget serviceCard({
      required IconData icon,
      required String title,
      required List<(String, String)> sessions,
    }) {
      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(icon, color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ...sessions.map(
                (session) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        session.$2,
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w800,
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

    Widget fellowshipCard() {
      const fellowships = [
        "Men's Fellowship",
        "Women's Fellowship",
        'Youth Fellowship',
      ];

      return Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      Icons.groups_outlined,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Fellowships (Vigwirizano)',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...fellowships.map(
                (name) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 20,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Church events'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Tiyeni limodzi',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Worship and fellowship together as one congregation.',
          ),
          const SizedBox(height: 20),
          serviceCard(
            icon: Icons.church_outlined,
            title: 'Sunday Service',
            sessions: [
              ('First Service', '06:30'),
              ('Second Service', '09:30'),
            ],
          ),
          serviceCard(
            icon: Icons.menu_book_outlined,
            title: 'Wednesday Service',
            sessions: [
              ('Midweek Service', '15:00'),
            ],
          ),
          fellowshipCard(),
        ],
      ),
    );
  }
}

class _HistoryMilestone extends StatelessWidget {
  const _HistoryMilestone({
    required this.year,
    required this.title,
    required this.description,
  });

  final String year;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(
              year,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 5),
                    Text(description),
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

class ChurchHistoryPage extends StatelessWidget {
  const ChurchHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Church history')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Image.asset(
            'assets/logo1.png',
            height: 150,
            errorBuilder: (_, _, _) => const Icon(Icons.church, size: 120),
          ),
          const SizedBox(height: 12),
          Text(
            'The Reformed Church in Zambia',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'The Reformed Church in Zambia (RCZ) grew from a mission movement into an independent Zambian church. Its story is connected with the witness of missionaries, African evangelists and generations of local Christians who established congregations and ministries across the country.',
          ),
          const SizedBox(height: 18),
          _HistoryMilestone(
            year: '1899',
            title: 'The beginning at Magwero',
            description: 'On 5 July 1899, mission work associated with the Dutch Reformed Church of the Orange Free State was established at Magwero in present-day Eastern Province.',
          ),
          _HistoryMilestone(
            year: '1943',
            title: 'A developing church structure',
            description: 'The growing work was organised into a synod within the mission church structure, helping congregations develop a more coordinated church life.',
          ),
          _HistoryMilestone(
            year: '1957',
            title: 'African Reformed Church',
            description: 'The name African Reformed Church was adopted as the church continued to develop its identity and leadership.',
          ),
          _HistoryMilestone(
            year: '1966',
            title: 'Autonomy',
            description: 'On 23 April 1966, the church attained autonomy and continued its ministry as a self-governing church in Zambia.',
          ),
          _HistoryMilestone(
            year: 'Today',
            title: 'A church serving communities',
            description: 'The RCZ continues through worship, discipleship, evangelism, education, pastoral care and community service in different parts of Zambia.',
          ),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.public_outlined),
              title: const Text('Read the reference'),
              subtitle: const Text(
                'World Council of Churches / public history summary',
              ),
              onTap: () => launchUrl(
                Uri.parse(
                  'https://www.oikoumene.org/member-churches/reformed-church-in-zambia',
                ),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        ],
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
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
                ...actions,
                const SizedBox(width: 14),
                ClipOval(
                  child: Image.asset(
                    'assets/logo_color.png',
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.church),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: child),
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
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
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

class _VerseCard extends StatelessWidget {
  const _VerseCard({required this.verse});

  final (String, String, String) verse;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          transitionBuilder: (child, animation) =>
              FadeTransition(opacity: animation, child: child),
          child: Column(
            key: ValueKey(verse.$2),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_stories_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Verse for today',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                verse.$1,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontStyle: FontStyle.italic, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                verse.$2,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.onOpenPage});

  final ValueChanged<int> onOpenPage;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.play_circle_outline, 'Watch sermons', 1),
      (Icons.edit_note_outlined, 'Write a note', 3),
      (Icons.menu_book_outlined, 'Open Nyimbo', 2),
      (Icons.campaign_outlined, 'Church notices', 4),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: actions.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.75,
      ),
      itemBuilder: (_, index) {
        final action = actions[index];
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: .96, end: 1),
          duration: Duration(milliseconds: 220 + index * 45),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onOpenPage(action.$3),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        action.$1,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        action.$2,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(height: 14),
            Text(title),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 58, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
