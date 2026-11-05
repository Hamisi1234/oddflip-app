// =============================================================================
//  RED CARD ALERT - main.dart
//  Faili hili lina kurasa hizi (tafuta kwa kutafuta maneno "UKURASA"):
//    1. APP SETUP        - rangi, main(), MaterialApp
//    2. APP SHELL        - navigation ya chini + kitufe cha kati (FAB) + alert dialog
//    3. HOME             - DashboardScreen, _Hero (kichwa chenye kitufe cha Log in), MatchCard
//    4. MATCH DETAILS    - MatchDetailsScreen na EventTile
//    5. FAVORITES        - FavoritesScreen
//    6. SETTINGS         - SettingsScreen
//    7. LOGIN            - LoginPage (ina animation)
//    7b. SIGN UP         - SignUpPage (mpya, ina animation)
//    8. SHARED WIDGETS   - CardLogo, EmptyPanel, TeamBadge n.k.
//    9. CARD ALERT       - CardAlert na CardAlertDialog
// =============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'api_service.dart';
import 'card_notification_service.dart';
import 'app_loading_indicator.dart';
import 'match_insights_panel.dart';
import 'mkaria_chat_screen.dart';
import 'red_card_overview_screen.dart';
import 'settings_screen.dart' as account_settings;

// ========================== 1. APP SETUP: RANGI ==============================
const red = Color(0xFFCF3948);
const ink = Color(0xFFFFFFFF);
const slate = Color(0xFF121E36);
const muted = Color(0xFFA0AEC0);
const canvas = Color(0xFF060C1B);
const cyan = Color(0xFF00C9FF);
const cyanBright = Color(0xFF00F2FE);
const highlightGradient = LinearGradient(
  colors: [Color(0xFF00F2FE), Color(0xFF4FACFE)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);
const backgroundGradient = LinearGradient(
  colors: [Color(0xFF060C1B), Color(0xFF121E36)],
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
);

// ========================== 1. APP SETUP: main() =============================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CardNotificationService.initialize();
  runApp(const RedCardAlertApp());
}

// ========================== 1. APP SETUP: MaterialApp ========================
class RedCardAlertApp extends StatefulWidget {
  const RedCardAlertApp({super.key});

  @override
  State<RedCardAlertApp> createState() => _RedCardAlertAppState();
}

class _RedCardAlertAppState extends State<RedCardAlertApp> {
  bool _darkMode = true;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _darkMode = prefs.getBool('dark_mode') ?? true);
    }
  }

  Future<void> _setDarkMode(bool value) async {
    setState(() => _darkMode = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OddFlip',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _darkMode ? ThemeMode.dark : ThemeMode.light,
      home: AppShell(onThemeChanged: _setDarkMode),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = isDark
        ? const ColorScheme.dark(
            primary: cyan,
            onPrimary: canvas,
            secondary: cyanBright,
            onSecondary: canvas,
            surface: canvas,
            onSurface: Colors.white,
            surfaceContainerHighest: slate,
            onSurfaceVariant: muted,
            outline: Color(0xFF34445D),
            error: Color(0xFFE45B68),
            onError: Colors.white,
          )
        : const ColorScheme.light(
            primary: Color(0xFF202833),
            onPrimary: Colors.white,
            secondary: Color(0xFF526171),
            onSecondary: Colors.white,
            surface: Colors.white,
            onSurface: Color(0xFF171B22),
            surfaceContainerHighest: Color(0xFFF2F4F7),
            onSurfaceVariant: Color(0xFF596575),
            outline: Color(0xFFD8DDE5),
            error: Color(0xFFB83B46),
            onError: Colors.white,
          );
    final pageBackground = isDark ? canvas : const Color(0xFFF7F8FA);
    final cardSurface = isDark ? slate : Colors.white;
    final accent = scheme.primary;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: pageBackground,
      canvasColor: cardSurface,
      fontFamily: 'Roboto',
      textTheme:
          (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
                bodyColor: scheme.onSurface,
                displayColor: scheme.onSurface,
              ),
      appBarTheme: AppBarTheme(
        backgroundColor: pageBackground,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: isDark ? 0 : 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardSurface,
        modalBackgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? slate : const Color(0xFFF2F4F7),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: accent,
        suffixIconColor: accent,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        foregroundColor: scheme.onSurface,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: cardSurface,
        indicatorColor:
            isDark ? cyan.withValues(alpha: .18) : const Color(0xFFE8ECF1),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent.withValues(alpha: .28)
              : scheme.surfaceContainerHighest,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? accent : cardSurface,
        ),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(color: scheme.outline),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? accent
              : scheme.onSurfaceVariant,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        selectedColor: isDark ? slate : const Color(0xFFE8ECF1),
        secondarySelectedColor: isDark ? slate : const Color(0xFFE8ECF1),
        labelStyle: TextStyle(color: scheme.onSurface),
        secondaryLabelStyle: TextStyle(color: scheme.onSurface),
        side: BorderSide(color: scheme.outline),
      ),
      dividerColor: scheme.outline.withValues(alpha: .65),
      popupMenuTheme: PopupMenuThemeData(
        color: cardSurface,
        surfaceTintColor: Colors.transparent,
        textStyle: TextStyle(color: scheme.onSurface),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: accent.withValues(alpha: .25),
        selectionHandleColor: accent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? slate : const Color(0xFF202833),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
    );
  }
}

// ========================== 2. APP SHELL (navigation kuu) ====================
class AppShell extends StatefulWidget {
  const AppShell({required this.onThemeChanged, super.key});

  final ValueChanged<bool> onThemeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // ukurasa uliochaguliwa kwenye bottom navigation
  LiveFixture? _selectedFixture;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _restoreProfile();
  }

  Future<void> _restoreProfile() async {
    final profile = await ApiService.fetchProfile();
    if (mounted && profile != null) setState(() => _profile = profile);
  }

  Future<void> _onAuthenticated() async {
    final profile = await ApiService.fetchProfile();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _index = 3;
    });
  }

  Future<void> _openLogin() async {
    final loggedIn = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const LoginPage(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .08),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (loggedIn == true && mounted) await _onAuthenticated();
  }

  void _onProfileUpdated(Map<String, dynamic> profile) {
    setState(() => _profile = profile);
  }

  Future<void> _logout() async {
    await ApiService.logout();
    if (!mounted) return;
    setState(() {
      _profile = null;
      _index = 0;
    });
    await _openLogin();
  }

  // Fungua ukurasa wa Matches na mechi iliyochaguliwa
  void _openFixture(LiveFixture fixture) {
    setState(() {
      _selectedFixture = fixture;
      _index = 1;
    });
  }

  // Onyesha dialog ya red/yellow card
  void _showAlert(CardAlert alert) {
    setState(() {
      _selectedFixture = alert.fixture;
    });
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: (alert.event.isRedCard ? red : const Color(0xFFF4C433))
          .withValues(alpha: .16),
      builder: (dialogContext) => CardAlertDialog(
        alert: alert,
        onView: () {
          Navigator.pop(dialogContext);
          _openFixture(alert.fixture);
        },
      ),
    );
  }

  void _openRedCardOverview() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RedCardOverviewScreen(
          onOpenFixture: (fixture) {
            Navigator.of(context).pop();
            _openFixture(fixture);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Kurasa kuu za app: Home, Matches, Favorites, Settings, Mkamaria AI.
    final chatUser = _profile?['user'];
    final chatUserId = chatUser is Map ? chatUser['id']?.toString() : null;
    final chatScreen = MkariaChatScreen(
      key: ValueKey(chatUserId ?? 'guest'),
      fixtureId: _selectedFixture?.id,
      userId: chatUserId,
    );
    final pages = [
      DashboardScreen(
        onOpen: _openFixture,
        onRedCards: _openRedCardOverview,
        onAlert: _showAlert,
        onAuthenticated: _onAuthenticated,
        onProfile: () => setState(() => _index = 3),
        profile: _profile,
      ),
      MatchDetailsScreen(
        fixture: _selectedFixture,
        onAlert: _showAlert,
      ),
      const FavoritesScreen(),
      account_settings.SettingsScreen(
        profile: _profile,
        onLogin: _openLogin,
        onLogout: _logout,
        onProfileUpdated: _onProfileUpdated,
        onDarkModeChanged: widget.onThemeChanged,
      ),
      chatScreen,
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      // Kitufe cha red-card overview hakizibi composer kwenye Mkamaria AI.
      floatingActionButton: _index == 4
          ? null
          : FloatingActionButton.small(
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              tooltip: 'Red card overview',
              onPressed: _openRedCardOverview,
              child: Container(
                width: 14,
                height: 20,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      // Bar ya chini
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor:
              Theme.of(context).colorScheme.surfaceContainerHighest,
          indicatorColor: Colors.transparent,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant)),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                color: states.contains(WidgetState.selected)
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w700
                    : FontWeight.w500,
              )),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: _SelectedNavigationIcon(icon: Icons.home),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.timeline_outlined),
                selectedIcon: _SelectedNavigationIcon(icon: Icons.timeline),
                label: 'Matches'),
            NavigationDestination(
                icon: Icon(Icons.star_outline),
                selectedIcon: _SelectedNavigationIcon(icon: Icons.star),
                label: 'Favorites'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: _SelectedNavigationIcon(icon: Icons.settings),
                label: 'Settings'),
            NavigationDestination(
                icon: Icon(Icons.auto_awesome_outlined),
                selectedIcon: _SelectedNavigationIcon(icon: Icons.auto_awesome),
                label: 'Mkamaria AI'),
          ],
        ),
      ),
    );
  }
}

class _SelectedNavigationIcon extends StatelessWidget {
  const _SelectedNavigationIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 2),
          Container(
            width: 18,
            height: 2,
            decoration: BoxDecoration(
              gradient: highlightGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      );
}

// ========================== 3. UKURASA: HOME (Dashboard) =====================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.onOpen,
    required this.onRedCards,
    required this.onAlert,
    required this.onAuthenticated,
    required this.onProfile,
    required this.profile,
    this.apiClient,
    super.key,
  });

  final ValueChanged<LiveFixture> onOpen;
  final VoidCallback onRedCards;
  final ValueChanged<CardAlert> onAlert;
  final VoidCallback onAuthenticated;
  final VoidCallback onProfile;
  final Map<String, dynamic>? profile;
  final ApiClient? apiClient;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const _collapsedMatchCount = 10;

  late final ApiClient _api = widget.apiClient ?? ApiClient();
  final _search = TextEditingController();
  List<LiveFixture> _fixtures = const [];
  List<LiveFixture> _upcomingFixtures = const [];
  final Map<String, String> _leagueOptions = {};
  final Set<String> _countryOptions = {};
  Set<String> _favorites = {};
  String _selectedDate = 'all';
  String _selectedTime = 'all';
  String _selectedLeague = 'all';
  String _selectedCountry = 'all';
  int _upcomingRequestId = 0;
  bool _loading = true;
  bool _upcomingLoading = true;
  bool _showAllLiveMatches = false;
  bool _showAllUpcomingMatches = false;
  bool _requestInFlight = false;
  bool _redCardScanInFlight = false;
  final Map<String, Set<String>> _knownRedCards = {};
  String? _error;
  String? _upcomingError;
  Timer? _timer;
  Timer? _upcomingTimer;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _load();
    _loadUpcoming();
    // Refresh mechi kila sekunde 20
    _timer =
        Timer.periodic(const Duration(seconds: 20), (_) => _load(silent: true));
    _upcomingTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadUpcoming(silent: true),
    );
    _search.addListener(() => setState(() {}));
  }

  // Soma favorites zilizohifadhiwa
  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _favorites =
          (prefs.getStringList('favorite_fixtures') ?? []).toSet());
    }
  }

  // Pakua mechi za live
  Future<void> _load({bool silent = false}) async {
    if (_requestInFlight) return;
    _requestInFlight = true;
    if (!silent && _fixtures.isEmpty) setState(() => _loading = true);
    try {
      final fixtures = await _api.fetchLiveFixtures();
      if (mounted) {
        setState(() {
          _fixtures = fixtures;
          _error = fixtures.isEmpty ? 'No live matches currently.' : null;
        });
      }
      unawaited(_scanRedCards(fixtures));
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
    } finally {
      _requestInFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadUpcoming({bool silent = false}) async {
    final requestId = ++_upcomingRequestId;
    if (!silent && mounted) {
      setState(() => _upcomingLoading = true);
    }
    try {
      final timeRange = _timeRanges[_selectedTime];
      final fixtures = await _api.fetchUpcomingFixtures(
        date: _selectedDate == 'all' ? null : _selectedDate,
        timeFrom: timeRange?['from'],
        timeTo: timeRange?['to'],
        league: _selectedLeague == 'all' ? null : _selectedLeague,
        country: _selectedCountry == 'all' ? null : _selectedCountry,
      );
      if (mounted && requestId == _upcomingRequestId) {
        setState(() {
          _upcomingFixtures = fixtures;
          _upcomingError = null;
          for (final fixture in fixtures) {
            _leagueOptions[fixture.league.id] = fixture.league.name;
            if (fixture.league.country.isNotEmpty) {
              _countryOptions.add(fixture.league.country);
            }
          }
        });
      }
    } on ApiException catch (error) {
      if (mounted && requestId == _upcomingRequestId) {
        setState(() => _upcomingError = error.message);
      }
    } finally {
      if (mounted && requestId == _upcomingRequestId) {
        setState(() => _upcomingLoading = false);
      }
    }
  }

  static const _timeRanges = <String, Map<String, String>>{
    'night': {'from': '00:00', 'to': '05:59'},
    'morning': {'from': '06:00', 'to': '11:59'},
    'afternoon': {'from': '12:00', 'to': '17:59'},
    'evening': {'from': '18:00', 'to': '23:59'},
  };

  List<MapEntry<String, String>> get _dateOptions {
    final today = DateTime.now();
    return List.generate(4, (index) {
      final date = today.add(Duration(days: index));
      final value = '${date.year.toString().padLeft(4, '0')}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      return MapEntry(value, index == 0 ? 'Leo · $value' : value);
    });
  }

  void _updateUpcomingFilter(void Function() update) {
    setState(update);
    _loadUpcoming();
  }

  Widget _matchListButton({
    required Key key,
    required bool expanded,
    required int total,
    required ValueChanged<bool> onChanged,
  }) {
    return TextButton.icon(
      key: key,
      onPressed: () => onChanged(!expanded),
      icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
      label: Text(
        expanded ? 'See less' : 'See more (${total - _collapsedMatchCount})',
      ),
    );
  }

  Future<void> _refreshFixtures() async {
    await Future.wait([_load(), _loadUpcoming()]);
  }

  Future<void> _scanRedCards(List<LiveFixture> fixtures) async {
    if (_redCardScanInFlight) return;
    _redCardScanInFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsEnabled = prefs.getBool('alert_red_cards') ?? true;
      final alarmEnabled = prefs.getBool('alarm_red_cards') ?? true;
      final fixtureIds = fixtures.map((fixture) => fixture.id).toSet();
      _knownRedCards
          .removeWhere((fixtureId, _) => !fixtureIds.contains(fixtureId));

      final fixturesWithTimelines =
          fixtures.where((fixture) => fixture.hasTimeline).toList();
      for (var start = 0; start < fixturesWithTimelines.length; start += 5) {
        final batch = fixturesWithTimelines.skip(start).take(5).toList();
        final results = await Future.wait(
          batch.map(_fetchRedCardEvents),
        );
        for (var index = 0; index < batch.length; index++) {
          final events = results[index];
          if (events == null) continue;

          final fixture = batch[index];
          final previousFingerprints = _knownRedCards[fixture.id];
          final redCards = events.where((event) => event.isRedCard).toList();
          for (final event in redCards) {
            if (previousFingerprints != null &&
                !previousFingerprints.contains(event.fingerprint)) {
              if (alarmEnabled) {
                try {
                  await SystemSound.play(SystemSoundType.alert);
                } on PlatformException catch (error) {
                  debugPrint('Could not play red-card alarm: $error');
                }
              }
              if (notificationsEnabled) {
                try {
                  await CardNotificationService.showRedCard(
                    homeTeam: fixture.home.name,
                    awayTeam: fixture.away.name,
                    player: event.playerName,
                    team: event.teamName,
                    minute: event.minute,
                  );
                } on PlatformException catch (error) {
                  debugPrint('Could not show red-card notification: $error');
                }
              }
            }
          }
          _knownRedCards[fixture.id] =
              redCards.map((event) => event.fingerprint).toSet();
        }
      }
    } finally {
      _redCardScanInFlight = false;
    }
  }

  Future<List<MatchEvent>?> _fetchRedCardEvents(LiveFixture fixture) async {
    try {
      return await _api.fetchEvents(fixture.id);
    } on ApiException catch (error) {
      debugPrint(
        'Could not check red cards for ${fixture.home.name} vs '
        '${fixture.away.name}: ${error.message}',
      );
      return null;
    }
  }

  // Weka / ondoa mechi kwenye favorites
  Future<void> _toggleFavorite(String id) async {
    setState(() =>
        _favorites.contains(id) ? _favorites.remove(id) : _favorites.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_fixtures', _favorites.toList());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _upcomingTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Chuja mechi kulingana na search
    final query = _search.text.trim().toLowerCase();
    bool matchesSearch(LiveFixture fixture) =>
        fixture.home.name.toLowerCase().contains(query) ||
        fixture.away.name.toLowerCase().contains(query) ||
        fixture.league.name.toLowerCase().contains(query);
    final visible = _fixtures.where(matchesSearch).toList();
    final visibleUpcoming = _upcomingFixtures.where(matchesSearch).toList();
    final displayedLive = _showAllLiveMatches
        ? visible
        : visible.take(_collapsedMatchCount).toList();
    final displayedUpcoming = _showAllUpcomingMatches
        ? visibleUpcoming
        : visibleUpcoming.take(_collapsedMatchCount).toList();
    Widget filterDropdown({
      required String label,
      required String value,
      required List<MapEntry<String, String>> options,
      required ValueChanged<String?> onChanged,
    }) {
      return DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        items: options
            .map((option) => DropdownMenuItem<String>(
                  value: option.key,
                  child: Text(option.value, overflow: TextOverflow.ellipsis),
                ))
            .toList(),
        onChanged: onChanged,
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshFixtures,
      child: CustomScrollView(
        slivers: [
          // Kichwa chekundu (kina kitufe cha Log in juu kulia)
          SliverToBoxAdapter(
            child: _Hero(
              search: _search,
              profile: widget.profile,
              onAuthenticated: widget.onAuthenticated,
              onProfile: widget.onProfile,
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 110),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Kichwa cha orodha: "Live now" + refresh
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.light
                                    ? Theme.of(context).colorScheme.error
                                    : slate,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('API-FOOTBALL · LIVE',
                              style: TextStyle(
                                  color: Theme.of(context).brightness ==
                                          Brightness.light
                                      ? Theme.of(context).colorScheme.onError
                                      : cyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2)),
                        ),
                        SizedBox(height: 4),
                        Text('Live now',
                            style: TextStyle(
                                fontSize: 23, fontWeight: FontWeight.w800)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _refreshFixtures,
                          icon: const Icon(Icons.refresh, color: cyan),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: widget.onRedCards,
                        icon: const Icon(Icons.credit_card, size: 18),
                        label: const Text('Red cards'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Loading / tupu / orodha ya mechi
                if (_loading && _fixtures.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 22),
                    child: AppLoadingIndicator(label: 'Loading live matches'),
                  )
                else if (visible.isEmpty)
                  EmptyPanel(
                    message: query.isNotEmpty
                        ? 'No live matches found for "$query".'
                        : _error ?? 'No live matches currently.',
                  )
                else ...[
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Live refresh failed. Showing the last available data. $_error',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: AppLoadingIndicator(
                        compact: true,
                        label: 'Refreshing live matches',
                      ),
                    ),
                  ...displayedLive.map((fixture) => Padding(
                        padding: const EdgeInsets.only(bottom: 13),
                        child: MatchCard(
                          fixture: fixture,
                          favorite: _favorites.contains(fixture.id),
                          onFavorite: () => _toggleFavorite(fixture.id),
                          onOpen: () => widget.onOpen(fixture),
                        ),
                      )),
                  if (visible.length > _collapsedMatchCount)
                    Align(
                      alignment: Alignment.center,
                      child: _matchListButton(
                        key: const ValueKey('live-match-expansion'),
                        expanded: _showAllLiveMatches,
                        total: visible.length,
                        onChanged: (value) => setState(
                          () => _showAllLiveMatches = value,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    const Icon(Icons.event_outlined, color: cyan, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Upcoming matches',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${visibleUpcoming.length}',
                      style: const TextStyle(
                        color: muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: filterDropdown(
                        label: 'Tarehe',
                        value: _selectedDate,
                        options: [
                          const MapEntry('all', 'Tarehe zote'),
                          ..._dateOptions,
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _updateUpcomingFilter(() => _selectedDate = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: filterDropdown(
                        label: 'Muda',
                        value: _selectedTime,
                        options: const [
                          MapEntry('all', 'Muda wote'),
                          MapEntry('night', 'Usiku'),
                          MapEntry('morning', 'Asubuhi'),
                          MapEntry('afternoon', 'Mchana'),
                          MapEntry('evening', 'Jioni'),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _updateUpcomingFilter(() => _selectedTime = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: filterDropdown(
                        label: 'Ligi',
                        value: _selectedLeague,
                        options: [
                          const MapEntry('all', 'Ligi zote'),
                          ..._leagueOptions.entries
                              .map((entry) => MapEntry(entry.key, entry.value))
                              .toList()
                            ..sort((left, right) =>
                                left.value.compareTo(right.value)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _updateUpcomingFilter(
                                () => _selectedLeague = value);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: filterDropdown(
                        label: 'Nchi',
                        value: _selectedCountry,
                        options: [
                          const MapEntry('all', 'Nchi zote'),
                          ...(_countryOptions.toList()..sort())
                              .map((country) => MapEntry(country, country)),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _updateUpcomingFilter(
                                () => _selectedCountry = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_upcomingLoading && _upcomingFixtures.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child:
                        AppLoadingIndicator(label: 'Loading upcoming matches'),
                  )
                else if (visibleUpcoming.isEmpty)
                  EmptyPanel(
                    message: query.isNotEmpty
                        ? 'No upcoming matches found for "$query".'
                        : _upcomingError ?? 'No upcoming matches available.',
                  )
                else ...[
                  if (_upcomingError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Upcoming matches could not be refreshed. '
                        'Showing saved matches. $_upcomingError',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ),
                  if (_upcomingLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: AppLoadingIndicator(
                        compact: true,
                        label: 'Refreshing upcoming matches',
                      ),
                    ),
                  ...displayedUpcoming.map((fixture) => Padding(
                        padding: const EdgeInsets.only(bottom: 13),
                        child: MatchCard(
                          fixture: fixture,
                          favorite: _favorites.contains(fixture.id),
                          onFavorite: () => _toggleFavorite(fixture.id),
                          onOpen: () => widget.onOpen(fixture),
                          isUpcoming: true,
                        ),
                      )),
                  if (visibleUpcoming.length > _collapsedMatchCount)
                    Align(
                      alignment: Alignment.center,
                      child: _matchListButton(
                        key: const ValueKey('upcoming-match-expansion'),
                        expanded: _showAllUpcomingMatches,
                        total: visibleUpcoming.length,
                        onChanged: (value) => setState(
                          () => _showAllUpcomingMatches = value,
                        ),
                      ),
                    ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ========================== 3. HOME: _Hero (kichwa chekundu) =================
class _Hero extends StatelessWidget {
  const _Hero({
    required this.search,
    required this.profile,
    required this.onAuthenticated,
    required this.onProfile,
  });

  final TextEditingController search;
  final Map<String, dynamic>? profile;
  final VoidCallback onAuthenticated;
  final VoidCallback onProfile;

  // Fungua LoginPage kwa animation (fade + slide kutoka chini)
  Future<void> _openLogin(BuildContext context) async {
    final loggedIn = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const LoginPage(),
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero)
                      .animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    // Ikiwa login imefanikiwa, onyesha ujumbe
    if (loggedIn == true && context.mounted) {
      onAuthenticated();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome back! You are logged in.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final liveBadgeColor = isLightMode ? red : cyan;
    final now = DateTime.now();
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.paddingOf(context).top + 16, 20, 30),
      decoration: const BoxDecoration(
        gradient: backgroundGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Safu ya juu: logo kushoto, Log in + kengele kulia
          Row(
            children: [
              const CardLogo(),
              const SizedBox(width: 10),
              const Text('RED CARD\nALERT',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                      height: 1.05)),
              const Spacer(),
              // ---- KITUFE CHA LOG IN (juu upande wa kulia) ----
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: profile == null ? () => _openLogin(context) : onProfile,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_outline,
                          color: Colors.white, size: 16),
                      const SizedBox(width: 5),
                      Text(profile == null ? 'Log in' : 'Profile',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.notifications_outlined, color: Colors.white),
            ],
          ),
          const SizedBox(height: 28),
          // Tarehe + "Live matches" + chip ya LIVE
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${weekdays[now.weekday - 1]}, ${now.day}',
                        style: const TextStyle(color: muted, fontSize: 12)),
                    const Text('Live matches',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              Chip(
                backgroundColor: isLightMode ? red : Colors.transparent,
                side: BorderSide(color: liveBadgeColor),
                avatar: CircleAvatar(
                  radius: 4,
                  backgroundColor: isLightMode ? Colors.white : cyan,
                ),
                label: Text('LIVE',
                    style: TextStyle(
                        color: isLightMode ? Colors.white : cyan,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Sehemu ya kutafuta
          TextField(
            controller: search,
            decoration: InputDecoration(
              hintText: 'Search team, league or match',
              hintStyle: const TextStyle(color: muted),
              prefixIcon: const Icon(Icons.search, color: cyan),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: search.clear,
                      icon: const Icon(Icons.close, color: cyan)),
              filled: true,
              fillColor: slate,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: cyanBright)),
            ),
            style: const TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ========================== 3. HOME: MatchCard (kadi ya mechi) ===============
class MatchCard extends StatelessWidget {
  const MatchCard({
    required this.fixture,
    required this.favorite,
    required this.onFavorite,
    required this.onOpen,
    this.isUpcoming = false,
    super.key,
  });

  final LiveFixture fixture;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onOpen;
  final bool isUpcoming;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: cyan.withValues(alpha: .14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cyan.withValues(alpha: .45))),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 10, 15, 14),
          child: Column(
            children: [
              // Jina la ligi + nyota ya favorite
              Row(
                children: [
                  Expanded(
                      child: Text(fixture.league.name,
                          style: const TextStyle(color: muted, fontSize: 11))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: onFavorite,
                    icon: Icon(favorite ? Icons.star : Icons.star_outline,
                        color: favorite ? red : muted),
                  ),
                ],
              ),
              // Timu mbili + matokeo
              Row(
                children: [
                  Expanded(child: TeamBadge(team: fixture.home)),
                  Column(
                    children: [
                      Text(
                          isUpcoming
                              ? fixture.startsAt == null
                                  ? 'UPCOMING'
                                  : MaterialLocalizations.of(context)
                                      .formatTimeOfDay(
                                      TimeOfDay.fromDateTime(
                                        fixture.startsAt!.toLocal(),
                                      ),
                                    )
                              : '●  ${fixture.minute ?? '—'}′',
                          style: const TextStyle(
                              color: cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                          isUpcoming
                              ? 'VS'
                              : '${fixture.home.goals} — ${fixture.away.goals}',
                          style: const TextStyle(
                              fontSize: 25, fontWeight: FontWeight.w900)),
                      if (isUpcoming && fixture.startsAt != null)
                        Text(
                          MaterialLocalizations.of(context)
                              .formatShortDate(fixture.startsAt!.toLocal()),
                          style: const TextStyle(color: muted, fontSize: 9),
                        ),
                      Text(fixture.venue ?? 'Venue unavailable',
                          style: const TextStyle(color: muted, fontSize: 9)),
                    ],
                  ),
                  Expanded(child: TeamBadge(team: fixture.away, dark: true)),
                ],
              ),
              const Divider(height: 22),
              // Fungua insights na timeline ya fixture hii.
              Row(
                children: [
                  Container(
                      width: 8,
                      height: 12,
                      decoration: BoxDecoration(
                          color: red, borderRadius: BorderRadius.circular(1))),
                  const SizedBox(width: 7),
                  Text(
                      isUpcoming
                          ? 'Scheduled match'
                          : fixture.hasTimeline
                              ? 'Live incidents'
                              : 'Score coverage only',
                      style: const TextStyle(color: muted, fontSize: 10)),
                  const Spacer(),
                  const Text('Match insights',
                      style: TextStyle(
                          color: cyan,
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  const Icon(Icons.chevron_right, color: cyan, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ========================== 8. SHARED: TeamBadge (nembo ya timu) =============
class TeamBadge extends StatelessWidget {
  const TeamBadge({required this.team, this.dark = false, super.key});
  final TeamScore team;
  final bool dark;

  // Herufi za mwanzo za jina la timu
  String get initials {
    final words =
        team.name.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    return words.take(3).map((word) => word[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final logoUri = Uri.tryParse(team.logo.trim());
    final hasLogo = logoUri != null &&
        (logoUri.scheme == 'http' || logoUri.scheme == 'https') &&
        logoUri.host.isNotEmpty;

    Widget initialsBadge() => Text(
          initials,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
        );

    return Column(
      children: [
        CircleAvatar(
          radius: 23,
          backgroundColor: slate,
          foregroundColor: Colors.white,
          child: hasLogo
              ? Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.network(
                      logoUri.toString(),
                      width: 46,
                      height: 46,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) =>
                          loadingProgress == null ? child : initialsBadge(),
                      errorBuilder: (context, error, stackTrace) =>
                          initialsBadge(),
                    ),
                  ),
                )
              : initialsBadge(),
        ),
        const SizedBox(height: 7),
        Text(team.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

// ========================== 4. UKURASA: MATCH DETAILS ========================
class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({
    required this.fixture,
    required this.onAlert,
    super.key,
  });
  final LiveFixture? fixture;
  final ValueChanged<CardAlert> onAlert;

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  final _api = ApiClient();
  List<MatchEvent> _events = const [];
  MatchInsights? _insights;
  Set<String>? _knownEvents;
  bool _cardsOnly = false;
  bool _loading = false;
  String? _loadingFixtureId;
  int _loadGeneration = 0;
  String? _error;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant MatchDetailsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fixture?.id != oldWidget.fixture?.id) _startPolling();
  }

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  // Anza kuangalia matukio ya mechi kila sekunde 15
  void _startPolling() {
    _timer?.cancel();
    _loadGeneration++;
    _loadingFixtureId = null;
    _knownEvents = null;
    _events = const [];
    _insights = null;
    if (widget.fixture == null) return;
    _load();
    if (_isLiveFixture(widget.fixture!)) {
      _timer = Timer.periodic(
          const Duration(seconds: 15), (_) => _load(silent: true));
    }
  }

  bool _isLiveFixture(LiveFixture fixture) => const {
        '1H',
        '2H',
        'HT',
        'ET',
        'BT',
        'P',
        'LIVE',
        'INT'
      }.contains(fixture.status.toUpperCase());

  // Pakua matukio na gundua kadi mpya
  Future<void> _load({bool silent = false}) async {
    final fixture = widget.fixture;
    if (fixture == null) return;
    if (_loadingFixtureId == fixture.id) return;
    _loadingFixtureId = fixture.id;
    final generation = _loadGeneration;
    if (!silent) setState(() => _loading = true);
    try {
      String? insightError;
      final eventsRequest = _api.fetchEvents(fixture.id);
      final insightsRequest = _loadInsights(
        fixture.id,
        (message) => insightError = message,
      );
      final insights = await insightsRequest;
      if (!mounted || generation != _loadGeneration) return;
      if (mounted) {
        setState(() {
          _insights = insights;
          _error = insightError;
        });
      }

      final events = await eventsRequest;
      if (!mounted || generation != _loadGeneration) return;
      final fingerprints = events.map((event) => event.fingerprint).toSet();
      if (_knownEvents != null) {
        for (final event in events.where((item) => item.isCard)) {
          if (!_knownEvents!.contains(event.fingerprint)) {
            widget.onAlert(CardAlert(fixture, event));
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          _events = events;
          _insights = insights;
          _knownEvents = fingerprints;
          _error = insightError;
        });
      }
    } on ApiException catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() {
          _error = error.message;
        });
      }
    } finally {
      if (generation == _loadGeneration) {
        _loadingFixtureId = null;
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<MatchInsights?> _loadInsights(
    String fixtureId,
    ValueChanged<String> onError,
  ) async {
    try {
      return await _api.fetchMatchInsights(fixtureId);
    } on ApiException catch (error) {
      onError(error.message);
    } on FormatException catch (error) {
      debugPrint('Could not parse insights for fixture $fixtureId: $error');
      onError('Match insights data could not be read.');
    } on TypeError catch (error) {
      debugPrint('Invalid insights data for fixture $fixtureId: $error');
      onError('The provider returned invalid match insights.');
    }
    return null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fixture = widget.fixture;
    if (fixture == null) {
      return const SafeArea(
          child: EmptyPanel(
              message: 'Select a live match from Home to view its timeline.'));
    }
    final events =
        _cardsOnly ? _events.where((event) => event.isCard).toList() : _events;
    final redCount = _events.where((event) => event.isRedCard).length;
    final yellowCount =
        _events.where((event) => event.isCard && !event.isRedCard).length;
    return CustomScrollView(
      slivers: [
        // Kichwa cha mechi
        SliverToBoxAdapter(
          child: Container(
            decoration: const BoxDecoration(gradient: backgroundGradient),
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.paddingOf(context).top + 18, 20, 28),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.sports_soccer, color: Colors.white),
                    Expanded(
                        child: Text(fixture.league.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                    const Icon(Icons.star_outline, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(child: TeamBadge(team: fixture.home)),
                    Column(
                      children: [
                        Chip(
                            label: Text(
                                _isLiveFixture(fixture)
                                    ? 'LIVE · ${fixture.minute ?? '—'}′'
                                    : fixture.startsAt == null
                                        ? fixture.status
                                        : MaterialLocalizations.of(context)
                                            .formatShortDate(
                                            fixture.startsAt!.toLocal(),
                                          ),
                                style: const TextStyle(
                                    color: cyan, fontWeight: FontWeight.w800)),
                            backgroundColor: slate,
                            side: const BorderSide(color: cyan)),
                        Text('${fixture.home.goals} — ${fixture.away.goals}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 29,
                                fontWeight: FontWeight.w900)),
                      ],
                    ),
                    Expanded(child: TeamBadge(team: fixture.away, dark: true)),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Mwili: hali ya mechi, filter, orodha ya matukio
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 18),
                      const SizedBox(width: 6),
                      Text(fixture.status),
                      const Spacer(),
                      Text('$redCount red · $yellowCount yellow',
                          style: const TextStyle(
                              color: red, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              MatchInsightsPanel(
                fixture: fixture,
                events: _events,
                insights: _insights,
                error: _error,
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('All events')),
                  ButtonSegment(value: true, label: Text('Cards only')),
                ],
                selected: {_cardsOnly},
                onSelectionChanged: (value) =>
                    setState(() => _cardsOnly = value.first),
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: AppLoadingIndicator(
                    compact: true,
                    label: 'Refreshing match events and insights',
                  ),
                ),
              if (!_loading && events.isEmpty)
                EmptyPanel(message: _error ?? 'No incidents reported yet.'),
              ...events.map(EventTile.new),
            ]),
          ),
        ),
      ],
    );
  }
}

// ========================== 4. MATCH DETAILS: EventTile ======================
class EventTile extends StatelessWidget {
  const EventTile(this.event, {super.key});
  final MatchEvent event;

  @override
  Widget build(BuildContext context) {
    final color = event.isRedCard
        ? red
        : event.isCard
            ? const Color(0xFFF4C433)
            : ink;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 7),
      leading: Text('${event.minute}′',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      title: Row(
        children: [
          Container(
              width: event.isCard ? 12 : 20,
              height: event.isCard ? 18 : 20,
              decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(event.isCard ? 2 : 10))),
          const SizedBox(width: 12),
          Expanded(
              child: Text(event.isRedCard ? 'Red card' : event.detail,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 24, top: 4),
        child: Text('${event.playerName} · ${event.teamName}'),
      ),
    );
  }
}

// ========================== 5. UKURASA: FAVORITES ============================
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) => const SafeArea(
        child: EmptyPanel(
            message: 'Favorite live matches are marked with a star on Home.'),
      );
}

// ========================== 6. UKURASA: SETTINGS =============================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _push = true;
  bool _vibration = true;
  bool _allMatches = false;
  String _sound = 'Siren';

  @override
  void initState() {
    super.initState();
    _restore();
  }

  // Soma settings zilizohifadhiwa
  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _push = prefs.getBool('push') ?? true;
      _vibration = prefs.getBool('vibration') ?? true;
      _allMatches = prefs.getBool('all_matches') ?? false;
      _sound = prefs.getString('sound') ?? 'Siren';
    });
  }

  // Hifadhi setting moja
  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          18, MediaQuery.paddingOf(context).top + 24, 18, 110),
      children: [
        const Text('YOUR PREFERENCES',
            style: TextStyle(
                color: cyan,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.4)),
        const Text('Alert settings',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
        const Text('Choose how and when you want to be notified.',
            style: TextStyle(color: muted)),
        const SizedBox(height: 26),
        // Sehemu: Notifications
        const SettingsHeading('Notifications'),
        SettingsCard(children: [
          SwitchListTile(
            secondary: const SettingsIcon(Icons.notifications_outlined),
            title: const Text('Push notifications'),
            subtitle: const Text('Instant red and yellow card alerts'),
            value: _push,
            onChanged: (value) {
              setState(() => _push = value);
              _save('push', value);
            },
          ),
          SwitchListTile(
            secondary: const SettingsIcon(Icons.vibration),
            title: const Text('Vibration'),
            subtitle: const Text('Haptic alert feedback'),
            value: _vibration,
            onChanged: (value) {
              setState(() => _vibration = value);
              _save('vibration', value);
            },
          ),
        ]),
        // Sehemu: Alert sound
        const SettingsHeading('Alert sound'),
        Wrap(
          spacing: 8,
          children: ['Siren', 'Harsh beep', 'Pop']
              .map((sound) => ChoiceChip(
                    label: Text(sound),
                    selected: _sound == sound,
                    onSelected: (_) {
                      setState(() => _sound = sound);
                      _save('sound', sound);
                    },
                  ))
              .toList(),
        ),
        const SizedBox(height: 24),
        // Sehemu: Match coverage (RadioGroup - njia mpya ya Flutter)
        const SettingsHeading('Match coverage'),
        SettingsCard(children: [
          RadioGroup<bool>(
            groupValue: _allMatches,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _allMatches = value);
              _save('all_matches', value);
            },
            child: const Column(
              children: [
                RadioListTile<bool>(
                  secondary: SettingsIcon(Icons.star_outline),
                  title: Text('Favorites only'),
                  subtitle: Text('Your saved teams and leagues'),
                  value: false,
                ),
                RadioListTile<bool>(
                  secondary: SettingsIcon(Icons.timeline),
                  title: Text('All live matches'),
                  subtitle: Text('Every live card event'),
                  value: true,
                ),
              ],
            ),
          ),
        ]),
        const ListTile(
          leading: SettingsIcon(Icons.schedule),
          title: Text('Silent hours'),
          subtitle: Text('23:00 — 07:00'),
          trailing: Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

// ========================== 6. SETTINGS: widgets saidizi =====================
class SettingsHeading extends StatelessWidget {
  const SettingsHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Text(text,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      );
}

class SettingsCard extends StatelessWidget {
  const SettingsCard({required this.children, super.key});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 14),
        elevation: 0,
        shape: RoundedRectangleBorder(
            side: const BorderSide(color: cyan),
            borderRadius: BorderRadius.circular(16)),
        child: Column(children: children),
      );
}

class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.icon, {super.key});
  final IconData icon;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: slate,
        foregroundColor: cyan,
        child: Icon(icon, size: 20),
      );
}

// ========================== 7. UKURASA: LOGIN (mpya) =========================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final AnimationController _intro; // controller ya animation ya kuingia
  bool _hidePassword = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // Animation ya kuingia kwa mfuatano: fade + slide kwa muda uliopangwa (begin..end)
  Widget _reveal(double begin, double end, Widget child) {
    final animation = CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .25), end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }

  // Bonyeza Log in: thibitisha fomu na tuma taarifa kwenye Laravel API
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    // Kuunganisha na Laravel API kupitia ApiService
    final result =
        await ApiService.login(_email.text.trim(), _password.text.trim());

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success']) {
      // Kila kitu kiko sawa, rudi Home au fungua ukurasa mkuu
      Navigator.of(context).pop(true);
    } else {
      // Onyesha ujumbe wa kosa uliotoka kwenye Laravel API
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: red),
      );
    }
  }

  // Fungua SignUpPage (fade + slide). Ikifanikiwa, funga na Login pia
  Future<void> _openSignUp() async {
    final created = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        transitionDuration: const Duration(milliseconds: 450),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => const SignUpPage(),
        transitionsBuilder: (_, animation, __, child) {
          final curved =
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(.08, 0), end: Offset.zero)
                      .animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (created == true && mounted) Navigator.of(context).pop(true);
  }

  // Muonekano wa input field
  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.5,
            )),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ---- Kichwa chekundu: kitufe cha kufunga, logo, kichwa cha habari ----
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.paddingOf(context).top + 8, 20, 36),
              decoration: const BoxDecoration(
                gradient: backgroundGradient,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  // Logo inajitokeza kwa "pop" (elastic scale)
                  ScaleTransition(
                    scale: CurvedAnimation(
                        parent: _intro,
                        curve: const Interval(0, .5, curve: Curves.elasticOut)),
                    child: Transform.scale(scale: 1.7, child: CardLogo()),
                  ),
                  const SizedBox(height: 26),
                  _reveal(
                      .15,
                      .55,
                      const Text('Welcome back',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900))),
                  const SizedBox(height: 4),
                  _reveal(
                      .2,
                      .6,
                      const Text('Log in to get instant card alerts',
                          style: TextStyle(color: muted))),
                ],
              ),
            ),
            // ---- Fomu ya login ----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Email
                    _reveal(
                        .3,
                        .7,
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration('Email', Icons.mail_outline),
                          validator: (value) =>
                              (value == null || !value.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                        )),
                    const SizedBox(height: 14),
                    // Password (na kitufe cha kuonyesha/kuficha)
                    _reveal(
                        .4,
                        .8,
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: _decoration(
                            'Password',
                            Icons.lock_outline,
                            suffix: IconButton(
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: muted),
                            ),
                          ),
                          validator: (value) =>
                              (value == null || value.length < 6)
                                  ? 'At least 6 characters'
                                  : null,
                        )),
                    // Forgot password
                    _reveal(
                        .45,
                        .85,
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {},
                            child: const Text('Forgot password?',
                                style: TextStyle(
                                    color: cyan, fontWeight: FontWeight.w700)),
                          ),
                        )),
                    const SizedBox(height: 8),
                    // Kitufe cha Log in (kinabadilika kuwa spinner wakati wa loading)
                    _reveal(
                        .55,
                        .95,
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: red,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _loading ? null : _submit,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _loading
                                  ? const SizedBox(
                                      key: ValueKey('loading'),
                                      width: 22,
                                      height: 22,
                                      child: AppLoadingIndicator(
                                        compact: true,
                                        color: Colors.white,
                                        label: 'Signing in',
                                      ),
                                    )
                                  : const Text('Log in',
                                      key: ValueKey('label'),
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                            ),
                          ),
                        )),
                    const SizedBox(height: 18),
                    // Sign up
                    _reveal(
                        .65,
                        1,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("Don't have an account?",
                                style: TextStyle(color: muted)),
                            TextButton(
                              onPressed: _openSignUp,
                              child: const Text('Sign up',
                                  style: TextStyle(
                                      color: cyan,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        )),
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

// ========================== 7b. UKURASA: SIGN UP (mpya) ======================
class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late final AnimationController _intro; // controller ya animation ya kuingia
  bool _hidePassword = true;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..forward();
  }

  @override
  void dispose() {
    _intro.dispose();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // Animation ya kuingia kwa mfuatano: fade + slide
  Widget _reveal(double begin, double end, Widget child) {
    final animation = CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, .25), end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }

  // Bonyeza Create account: thibitisha fomu na tuma taarifa za usajili kupitia ApiService
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    // Kuunganisha na Laravel API halisi ya register
    final result = await ApiService.register(
      _name.text.trim(),
      _email.text.trim(),
      _password.text.trim(),
    );

    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success']) {
      // Usajili umefanikiwa, rudi nyuma
      Navigator.of(context).pop(true);
    } else {
      // Onyesha ujumbe wa kosa uliotoka Laravel
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: red),
      );
    }
  }

  // Muonekano wa input field
  InputDecoration _decoration(String label, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
        suffixIcon: suffix,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide:
                BorderSide(color: Theme.of(context).colorScheme.primary)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ---- Kichwa chekundu: kitufe cha kurudi, logo, kichwa cha habari ----
            Container(
              width: double.infinity,
              padding: EdgeInsets.fromLTRB(
                  20, MediaQuery.paddingOf(context).top + 8, 20, 32),
              decoration: const BoxDecoration(
                gradient: backgroundGradient,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                  ),
                  ScaleTransition(
                    scale: CurvedAnimation(
                        parent: _intro,
                        curve: const Interval(0, .5, curve: Curves.elasticOut)),
                    child: Transform.scale(scale: 1.5, child: CardLogo()),
                  ),
                  const SizedBox(height: 22),
                  _reveal(
                      .1,
                      .5,
                      const Text('Create account',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900))),
                  const SizedBox(height: 4),
                  _reveal(
                      .15,
                      .55,
                      const Text('Sign up to never miss a card',
                          style: TextStyle(color: muted))),
                ],
              ),
            ),
            // ---- Fomu ya sign up ----
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Full name
                    _reveal(
                        .25,
                        .6,
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          decoration:
                              _decoration('Full name', Icons.person_outline),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'Enter your name'
                                  : null,
                        )),
                    const SizedBox(height: 14),
                    // Email
                    _reveal(
                        .3,
                        .68,
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration('Email', Icons.mail_outline),
                          validator: (value) =>
                              (value == null || !value.contains('@'))
                                  ? 'Enter a valid email'
                                  : null,
                        )),
                    const SizedBox(height: 14),
                    // Password
                    _reveal(
                        .38,
                        .76,
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            'Password',
                            Icons.lock_outline,
                            suffix: IconButton(
                              onPressed: () => setState(
                                  () => _hidePassword = !_hidePassword),
                              icon: Icon(
                                  _hidePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: muted),
                            ),
                          ),
                          validator: (value) =>
                              (value == null || value.length < 6)
                                  ? 'At least 6 characters'
                                  : null,
                        )),
                    const SizedBox(height: 14),
                    // Confirm password
                    _reveal(
                        .46,
                        .84,
                        TextFormField(
                          controller: _confirm,
                          obscureText: _hidePassword,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: _decoration(
                              'Confirm password', Icons.lock_reset_outlined),
                          validator: (value) => value != _password.text
                              ? 'Passwords do not match'
                              : null,
                        )),
                    const SizedBox(height: 22),
                    // Kitufe cha Create account (kinabadilika kuwa spinner wakati wa loading)
                    _reveal(
                        .55,
                        .94,
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: red,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _loading ? null : _submit,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: _loading
                                  ? const SizedBox(
                                      key: ValueKey('loading'),
                                      width: 22,
                                      height: 22,
                                      child: AppLoadingIndicator(
                                        compact: true,
                                        color: Colors.white,
                                        label: 'Creating account',
                                      ),
                                    )
                                  : const Text('Create account',
                                      key: ValueKey('label'),
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800)),
                            ),
                          ),
                        )),
                    const SizedBox(height: 14),
                    // Rudi kwenye Login
                    _reveal(
                        .65,
                        1,
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('Already have an account?',
                                style: TextStyle(color: muted)),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Log in',
                                  style: TextStyle(
                                      color: cyan,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        )),
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

// ========================== 8. SHARED: CardLogo (nembo ya app) ===============
class CardLogo extends StatelessWidget {
  const CardLogo({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 30,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Transform.scale(
            scale: 1.2,
            child: Image.asset(
              'assets/odd_flip_logo.png',
              width: 30,
              height: 30,
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
}

// ========================== 8. SHARED: EmptyPanel (hakuna data) ==============
class EmptyPanel extends StatelessWidget {
  const EmptyPanel({required this.message, super.key});
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircleAvatar(
                  backgroundColor: slate,
                  foregroundColor: cyan,
                  child: Icon(Icons.sports_soccer)),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
}

// ========================== 9. CARD ALERT: modeli ============================
class CardAlert {
  const CardAlert(this.fixture, this.event);
  final LiveFixture fixture;
  final MatchEvent event;
}

// ========================== 9. CARD ALERT: dialog ya tahadhari ===============
class CardAlertDialog extends StatelessWidget {
  const CardAlertDialog({required this.alert, required this.onView, super.key});
  final CardAlert alert;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final event = alert.event;
    final fixture = alert.fixture;
    final color = event.isRedCard ? red : const Color(0xFFD5A30E);
    return AlertDialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: color)),
      // Kichwa: "URGENT · RED CARD" + kitufe cha kufunga
      title: Row(
        children: [
          Chip(
            label: Text('URGENT · ${event.isRedCard ? 'RED' : 'YELLOW'} CARD',
                style: TextStyle(
                    color: color, fontSize: 10, fontWeight: FontWeight.w900)),
            backgroundColor: color.withValues(alpha: .08),
            side: BorderSide.none,
          ),
          const Spacer(),
          IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close)),
        ],
      ),
      // Maudhui: mchezaji, timu, matokeo, maelezo
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 30,
              height: 44,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 15),
          Text('${event.minute}′ MINUTE',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 11)),
          Text(event.playerName,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          Text(event.teamName, style: const TextStyle(color: muted)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: canvas, borderRadius: BorderRadius.circular(13)),
            child: Row(
              children: [
                Expanded(
                    child:
                        Text(fixture.home.name, textAlign: TextAlign.center)),
                Text('${fixture.home.goals} — ${fixture.away.goals}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w900)),
                Expanded(
                    child:
                        Text(fixture.away.name, textAlign: TextAlign.center)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(event.detail, textAlign: TextAlign.center),
        ],
      ),
      // Kitufe cha kwenda kwenye timeline ya mechi
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: color, padding: const EdgeInsets.all(14)),
            onPressed: onView,
            child: const Text('View match timeline'),
          ),
        ),
      ],
    );
  }
}
