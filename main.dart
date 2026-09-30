import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LauncherApp());
}

const _bg = Color(0xFFEBEBEB);
const _red = Color(0xFFE60012);
const _cyan = Color(0xFF00C3E3);
const _ink = Color(0xFF2D2D2D);

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ar'),
        builder: (c, w) => Directionality(textDirection: TextDirection.rtl, child: w!),
        theme: ThemeData(scaffoldBackgroundColor: _bg, fontFamily: 'Roboto'),
        home: const HomeScreen(),
      );
}

class Game {
  final String name, package;
  final Uint8List icon;
  Game(this.name, this.package, this.icon);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _ch = MethodChannel('game_launcher/native');
  List<Game> games = [];
  int selected = 0;
  bool loading = true, busy = false;
  late final Timer _clock;
  DateTime now = DateTime.now();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent || busy) return KeyEventResult.ignored;
    final k = e.logicalKey;
    // الواجهة من اليمين لليسار: اليسار = التالي، اليمين = السابق
    if (k == LogicalKeyboardKey.arrowLeft) { _move(1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowRight) { _move(-1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.gameButtonA) {
      _boostAndPlay(); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.gameButtonStart || k == LogicalKeyboardKey.gameButtonY ||
        k == LogicalKeyboardKey.gameButtonSelect) {
      _openSettings(); return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _move(int d) {
    if (games.isEmpty) return;
    _select((selected + d).clamp(0, games.length - 1));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _focus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() => now = DateTime.now()));
    _load();
  }

  @override
  void dispose() {
    _clock.cancel();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _ch.invokeListMethod<Map>('getGames') ?? [];
    setState(() {
      games = list
          .map((m) => Game(m['name'] as String, m['package'] as String, m['icon'] as Uint8List))
          .toList();
      loading = false;
    });
  }

  void _select(int i) {
    setState(() => selected = i);
    _scroll.animateTo((i * 176.0 - 120).clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  Future<void> _boostAndPlay() async {
    if (games.isEmpty || busy) return;
    setState(() => busy = true);
    final g = games[selected];
    final res = await _ch.invokeMapMethod<String, dynamic>('boost', {'keep': g.package});
    final freed = ((res?['freedMb'] ?? 0) as num).round();
    final killed = res?['closed'] ?? 0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('تم إغلاق $killed تطبيق · تحرير ~$freed MB')));
    }
    await Future.delayed(const Duration(milliseconds: 600));
    await _ch.invokeMethod('launch', {'package': g.package});
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
          child: Column(children: [
            Row(children: [
              const CircleAvatar(radius: 18, backgroundColor: _cyan, child: Icon(Icons.person, color: Colors.white)),
              const Spacer(),
              IconButton(
                  tooltip: 'الإعدادات',
                  onPressed: _openSettings,
                  icon: const Icon(Icons.settings, color: _ink)),
              const SizedBox(width: 12),
              Text(t, style: const TextStyle(fontSize: 18, color: _ink, fontWeight: FontWeight.w600)),
            ]),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator(color: _red))
                  : games.isEmpty
                      ? const Center(child: Text('لا توجد ألعاب مثبتة', style: TextStyle(fontSize: 20, color: _ink)))
                      : ListView.separated(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
                          itemCount: games.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 16),
                          itemBuilder: (_, i) => _Tile(game: games[i], active: i == selected, onTap: () => _select(i)),
                        ),
            ),
            if (games.isNotEmpty)
              Text(games[selected].name,
                  style: const TextStyle(fontSize: 20, color: _ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              width: 260,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: _red, shape: const StadiumBorder(), textStyle: const TextStyle(fontSize: 18)),
                onPressed: busy ? null : _boostAndPlay,
                icon: busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.rocket_launch),
                label: Text(busy ? 'جارٍ التنظيف…' : 'نظّف وابدأ اللعب'),
              ),
            ),
          ]),
        ),
      ),
    ));
  }
}

class _Tile extends StatelessWidget {
  final Game game;
  final bool active;
  final VoidCallback onTap;
  const _Tile({required this.game, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: active ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: 160,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: active ? _cyan : Colors.transparent, width: 4),
            boxShadow: active
                ? [BoxShadow(color: _cyan.withOpacity(.45), blurRadius: 16)]
                : const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Image.memory(game.icon, fit: BoxFit.contain, gaplessPlayback: true),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _ch = MethodChannel('game_launcher/native');
  List<Game> apps = [];
  Set<String> excluded = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _ch.invokeListMethod<Map>('getUserApps') ?? [];
    final ex = await _ch.invokeListMethod<String>('getExcluded') ?? [];
    setState(() {
      apps = list.map((m) => Game(m['name'] as String, m['package'] as String, m['icon'] as Uint8List)).toList();
      excluded = ex.toSet();
      loading = false;
    });
  }

  Future<void> _toggle(String pkg, bool keep) async {
    setState(() => keep ? excluded.add(pkg) : excluded.remove(pkg));
    await _ch.invokeMethod('setExcluded', {'packages': excluded.toList()});
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: false,
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.gameButtonB || e.logicalKey == LogicalKeyboardKey.escape)) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          foregroundColor: _ink,
          title: const Text('التطبيقات المستثناة من الإغلاق'),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: _red))
            : ListView.builder(
                itemCount: apps.length,
                itemBuilder: (_, i) {
                  final a = apps[i];
                  final keep = excluded.contains(a.package);
                  return SwitchListTile(
                    activeColor: _cyan,
                    secondary: Image.memory(a.icon, width: 40, height: 40, gaplessPlayback: true),
                    title: Text(a.name),
                    subtitle: Text(keep ? 'لن يُغلق' : 'سيُغلق عند التنظيف'),
                    value: keep,
                    onChanged: (v) => _toggle(a.package, v),
                  );
                },
              ),
      ),
    );
  }
}
