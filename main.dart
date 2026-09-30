import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _ch = MethodChannel('game_launcher/native');
const _peach = Color(0xFFFFC58F);
const _ink = Color(0xFF2B1A10);
const _accent = Color(0xFFFF7A2F);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(
      [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LauncherApp());
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        builder: (c, w) => Directionality(textDirection: TextDirection.ltr, child: w!),
        home: const HomeScreen(),
      );
}

class Game {
  final String name, package;
  final Uint8List icon;
  Game(this.name, this.package, this.icon);
}

class Meta {
  String? name;
  String? cover;
  bool fav;
  int last;
  Meta({this.name, this.cover, this.fav = false, this.last = 0});
  Map<String, dynamic> toJson() => {'n': name, 'c': cover, 'f': fav, 'l': last};
  factory Meta.fromJson(Map<String, dynamic> j) => Meta(
      name: j['n'] as String?,
      cover: j['c'] as String?,
      fav: (j['f'] ?? false) as bool,
      last: (j['l'] ?? 0) as int);
}

Future<String> _saveCover(Uint8List bytes, String pkg) async {
  final dir = await getApplicationDocumentsDirectory();
  final d = Directory('${dir.path}/covers');
  await d.create(recursive: true);
  final f = File('${d.path}/${pkg}_${DateTime.now().millisecondsSinceEpoch}.jpg');
  await f.writeAsBytes(bytes);
  return f.path;
}

enum Shelf { recent, fav, all }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Game> games = [], apps = [];
  Map<String, Meta> meta = {};
  bool gamesTab = true;
  Shelf shelf = Shelf.all;
  int selected = 0;
  bool loading = true, busy = false;
  double _tileW = 160;
  final _scroll = ScrollController();
  final _focus = FocusNode();
  late final Timer _clock;
  DateTime now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
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
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('meta_v1');
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      meta = m.map((k, v) => MapEntry(k, Meta.fromJson(Map<String, dynamic>.from(v as Map))));
    }
    final g = await _ch.invokeListMethod<Map>('getGames') ?? [];
    final a = await _ch.invokeListMethod<Map>('getUserApps') ?? [];
    Game conv(Map m) => Game(m['name'] as String, m['package'] as String, m['icon'] as Uint8List);
    if (!mounted) return;
    setState(() {
      games = g.map(conv).toList();
      apps = a.map(conv).toList();
      loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('meta_v1', jsonEncode(meta.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Meta _m(String pkg) => meta.putIfAbsent(pkg, () => Meta());

  String _title(Game g) {
    final n = meta[g.package]?.name;
    return (n != null && n.trim().isNotEmpty) ? n : g.name;
  }

  List<Game> get visible {
    final src = gamesTab ? games : apps;
    if (shelf == Shelf.recent) {
      final l = src.where((g) => (meta[g.package]?.last ?? 0) > 0).toList();
      l.sort((a, b) => meta[b.package]!.last.compareTo(meta[a.package]!.last));
      return l;
    }
    if (shelf == Shelf.fav) {
      return src.where((g) => meta[g.package]?.fav == true).toList();
    }
    return src;
  }

  void _select(int i) {
    setState(() => selected = i);
    if (_scroll.hasClients) {
      final target = (i * (_tileW + 16)) - 20;
      _scroll.animateTo(target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _move(int d) {
    final n = visible.length;
    if (n == 0) return;
    _select((selected + d).clamp(0, n - 1));
  }

  void _cycleShelf(int d) {
    final v = Shelf.values;
    setState(() {
      shelf = v[(shelf.index + d + v.length) % v.length];
      selected = 0;
    });
  }

  void _setTab(bool g) => setState(() {
        gamesTab = g;
        selected = 0;
      });

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent || busy) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight) { _move(1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowLeft) { _move(-1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowDown) { _cycleShelf(1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowUp) { _cycleShelf(-1); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.gameButtonRight1) { _setTab(false); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.gameButtonLeft1) { _setTab(true); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter ||
        k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.gameButtonA) {
      _play(); return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.gameButtonY) { _edit(); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.gameButtonStart || k == LogicalKeyboardKey.gameButtonSelect) {
      _openSettings(); return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _focus.requestFocus();
  }

  Future<void> _play() async {
    final list = visible;
    if (list.isEmpty || busy) return;
    final g = list[selected.clamp(0, list.length - 1)];
    setState(() => busy = true);
    Map<String, dynamic>? res;
    try {
      res = await _ch.invokeMapMethod<String, dynamic>('boost', {'keep': g.package});
    } catch (_) {}
    final freed = ((res?['freedMb'] ?? 0) as num).round();
    final killed = res?['closed'] ?? 0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('تم إغلاق $killed تطبيق · تحرير ~$freed MB')));
    }
    _m(g.package).last = DateTime.now().millisecondsSinceEpoch;
    await _save();
    await Future.delayed(const Duration(milliseconds: 600));
    await _ch.invokeMethod('launch', {'package': g.package});
    if (mounted) setState(() => busy = false);
  }

  Future<void> _edit() async {
    final list = visible;
    if (list.isEmpty) return;
    final g = list[selected.clamp(0, list.length - 1)];
    final m = _m(g.package);
    final res = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => EditDialog(game: g, meta: m, isGame: gamesTab));
    _focus.requestFocus();
    if (res == null) return;
    setState(() {
      m.name = res['name'] as String?;
      m.cover = res['cover'] as String?;
      m.fav = res['fav'] as bool;
    });
    await _save();
  }

  String _lastText(int ms) {
    if (ms == 0) return 'لم تُشغَّل بعد';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'آخر تشغيل: اليوم';
    if (diff == 1) return 'آخر تشغيل: أمس';
    return 'آخر تشغيل: ${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final list = visible;
    final sel = list.isEmpty ? 0 : selected.clamp(0, list.length - 1);
    final cur = list.isEmpty ? null : list[sel];
    final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: const Color(0xFF120A06),
        body: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _WavePainter())),
          SafeArea(
            child: Row(children: [
              _rail(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 12, 24, 10),
                  child: Column(children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(30)),
                        child: Row(children: [
                          _tab('الألعاب', Icons.rocket_launch, true),
                          _tab('التطبيقات', Icons.apps, false),
                        ]),
                      ),
                      const Spacer(),
                      Text(t, style: const TextStyle(fontSize: 16, color: Colors.white70, fontWeight: FontWeight.w600)),
                    ]),
                    Expanded(
                      child: LayoutBuilder(builder: (ctx, c) {
                        final tileH = (c.maxHeight * 0.5).clamp(110.0, 260.0).toDouble();
                        _tileW = tileH * 0.9;
                        if (loading) {
                          return const Center(child: CircularProgressIndicator(color: _peach));
                        }
                        if (cur == null) {
                          final msg = shelf == Shelf.recent
                              ? 'لا يوجد شيء شُغّل مؤخرًا'
                              : shelf == Shelf.fav
                                  ? 'لا توجد مفضلة. اضغط مطولًا على أي عنصر لتعديله وإضافته'
                                  : (gamesTab ? 'لم أجد ألعابًا. جرّب تبويب التطبيقات' : 'لا توجد تطبيقات');
                          return Center(child: Text(msg, style: const TextStyle(fontSize: 16, color: Colors.white70)));
                        }
                        final info = _lastText(meta[cur.package]?.last ?? 0) +
                            (meta[cur.package]?.fav == true ? '  •  ★ مفضلة' : '');
                        return SingleChildScrollView(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(
                              height: tileH + 34,
                              child: ListView.separated(
                                controller: _scroll,
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
                                itemCount: list.length,
                                separatorBuilder: (_, __) => const SizedBox(width: 16),
                                itemBuilder: (_, i) => SizedBox(
                                  width: _tileW,
                                  height: tileH,
                                  child: _Tile(
                                    game: list[i],
                                    cover: meta[list[i].package]?.cover,
                                    active: i == sel,
                                    onTap: () => i == sel ? _play() : _select(i),
                                    onLong: () {
                                      _select(i);
                                      _edit();
                                    },
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Row(children: [
                                Flexible(
                                  child: Text(_title(cur),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white)),
                                ),
                                IconButton(
                                    onPressed: _edit,
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.edit, size: 18, color: Colors.white54)),
                              ]),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 10),
                              child: Text(info, style: const TextStyle(fontSize: 13, color: Colors.white60)),
                            ),
                          ]),
                        );
                      }),
                    ),
                    Row(children: [
                      Expanded(
                        child: Wrap(spacing: 14, runSpacing: 2, children: [
                          _hint('START', 'الإعدادات'),
                          _hint('L1 R1', 'تبويب'),
                          _hint('▲▼', 'القسم'),
                          _hint('◄►', 'تنقل'),
                          _hint('Y', 'تعديل'),
                          _hint('A', 'تشغيل'),
                        ]),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 44,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: _accent, shape: const StadiumBorder()),
                          onPressed: busy ? null : _play,
                          icon: busy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.rocket_launch, size: 18),
                          label: Text(busy ? 'جارٍ التنظيف…' : 'نظّف وابدأ'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _tab(String t, IconData i, bool isGames) {
    final on = gamesTab == isGames;
    return GestureDetector(
      onTap: () => _setTab(isGames),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: on ? _peach : Colors.transparent, borderRadius: BorderRadius.circular(24)),
        child: Row(children: [
          Icon(i, size: 18, color: on ? _ink : Colors.white70),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(color: on ? _ink : Colors.white70, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _rail() => Container(
        width: 60,
        margin: const EdgeInsets.fromLTRB(10, 12, 6, 12),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(30)),
        child: Column(children: [
          _railBtn(Icons.history, Shelf.recent),
          _railBtn(Icons.star, Shelf.fav),
          _railBtn(Icons.grid_view_rounded, Shelf.all),
          const Spacer(),
          IconButton(onPressed: _openSettings, icon: const Icon(Icons.settings, color: Colors.white70)),
        ]),
      );

  Widget _railBtn(IconData i, Shelf f) {
    final on = shelf == f;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GestureDetector(
        onTap: () => setState(() {
          shelf = f;
          selected = 0;
        }),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? _peach : Colors.white12),
          child: Icon(i, size: 22, color: on ? _ink : Colors.white70),
        ),
      ),
    );
  }

  Widget _hint(String k, String v) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(k, style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(v, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      ]);
}

class _Tile extends StatelessWidget {
  final Game game;
  final String? cover;
  final bool active;
  final VoidCallback onTap, onLong;
  const _Tile({required this.game, required this.cover, required this.active, required this.onTap, required this.onLong});

  @override
  Widget build(BuildContext context) {
    final hue = (game.package.hashCode.abs() % 360).toDouble();
    final base = HSLColor.fromAHSL(1, hue, .45, .30).toColor();
    final dark = HSLColor.fromAHSL(1, hue, .45, .16).toColor();
    Widget fallback() => Container(
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [base, dark])),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Image.memory(game.icon, fit: BoxFit.contain, gaplessPlayback: true),
            ),
          ),
        );
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLong,
      child: AnimatedScale(
        scale: active ? 1.06 : 0.96,
        duration: const Duration(milliseconds: 160),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? _peach : Colors.transparent, width: 3),
            boxShadow: active ? [BoxShadow(color: _peach.withOpacity(.35), blurRadius: 18)] : null,
          ),
          child: cover != null
              ? Image.file(File(cover!), fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback())
              : fallback(),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final bg = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF1B0F09), Color(0xFF2E160A), Color(0xFF0E0704)],
      ).createShader(Offset.zero & s);
    canvas.drawRect(Offset.zero & s, bg);
    for (int i = 0; i < 14; i++) {
      final p = Path();
      final y0 = s.height * (0.62 + i * 0.02);
      p.moveTo(0, y0);
      for (double x = 0; x <= s.width; x += 8) {
        p.lineTo(x, y0 + math.sin(x / s.width * 2 * math.pi + i * 0.25) * 26 * (1 + i * 0.03));
      }
      canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = Color.lerp(const Color(0xFFFF7A2F), const Color(0xFFFFC04D), i / 14)!.withOpacity(.28));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Cand {
  final String title, url;
  final int index;
  _Cand(this.title, this.url, this.index);
}

class EditDialog extends StatefulWidget {
  final Game game;
  final Meta meta;
  final bool isGame;
  const EditDialog({super.key, required this.game, required this.meta, required this.isGame});
  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  late final TextEditingController nameC;
  late final TextEditingController searchC;
  String? cover;
  bool fav = false, searching = false, downloading = false;
  String? msg;
  List<_Cand> results = [];

  @override
  void initState() {
    super.initState();
    final n = widget.meta.name ?? widget.game.name;
    nameC = TextEditingController(text: n);
    searchC = TextEditingController(text: n);
    cover = widget.meta.cover;
    fav = widget.meta.fav;
  }

  @override
  void dispose() {
    nameC.dispose();
    searchC.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = searchC.text.trim();
    if (q.isEmpty) return;
    setState(() {
      searching = true;
      msg = null;
      results = [];
    });
    try {
      final uri = Uri.https('en.wikipedia.org', '/w/api.php', {
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrsearch': widget.isGame ? '$q video game' : q,
        'gsrlimit': '15',
        'prop': 'pageimages',
        'piprop': 'thumbnail',
        'pithumbsize': '500',
      });
      final r = await http.get(uri, headers: {'User-Agent': 'GameLauncher/1.0'}).timeout(const Duration(seconds: 15));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final pages = ((j['query'] as Map?)?['pages'] as Map?) ?? {};
      final list = <_Cand>[];
      pages.forEach((k, v) {
        final t = v['thumbnail'];
        if (t != null) {
          list.add(_Cand(v['title'] as String, t['source'] as String, (v['index'] ?? 99) as int));
        }
      });
      list.sort((a, b) => a.index.compareTo(b.index));
      setState(() {
        results = list;
        if (list.isEmpty) msg = 'لم أجد صورًا. جرّب كتابة اسم اللعبة بالإنجليزية.';
      });
    } catch (_) {
      setState(() => msg = 'تعذّر الاتصال بالإنترنت.');
    }
    if (mounted) setState(() => searching = false);
  }

  Future<void> _useUrl(String url) async {
    setState(() {
      downloading = true;
      msg = null;
    });
    try {
      final r = await http.get(Uri.parse(url), headers: {'User-Agent': 'GameLauncher/1.0'}).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception('bad');
      final p = await _saveCover(r.bodyBytes, widget.game.package);
      setState(() => cover = p);
    } catch (_) {
      setState(() => msg = 'فشل تنزيل الصورة.');
    }
    if (mounted) setState(() => downloading = false);
  }

  Future<void> _gallery() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 900, imageQuality: 88);
    if (x == null) return;
    final p = await _saveCover(await x.readAsBytes(), widget.game.package);
    setState(() => cover = p);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF241610),
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('تعديل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 90,
                height: 100,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
                child: cover != null
                    ? Image.file(File(cover!), fit: BoxFit.cover)
                    : Padding(padding: const EdgeInsets.all(12), child: Image.memory(widget.game.icon)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(children: [
                  TextField(controller: nameC, decoration: const InputDecoration(labelText: 'الاسم', isDense: true, border: OutlineInputBorder())),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    activeColor: _peach,
                    title: const Text('مفضلة'),
                    value: fav,
                    onChanged: (v) => setState(() => fav = v),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(onPressed: _gallery, icon: const Icon(Icons.photo_library, size: 18), label: const Text('من المعرض')),
              if (cover != null)
                OutlinedButton.icon(onPressed: () => setState(() => cover = null), icon: const Icon(Icons.delete_outline, size: 18), label: const Text('حذف الغلاف')),
            ]),
            const SizedBox(height: 14),
            const Text('بحث عن غلاف في الإنترنت', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: searchC,
                  onSubmitted: (_) => _search(),
                  decoration: const InputDecoration(hintText: 'اسم اللعبة بالإنجليزية', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _accent),
                  onPressed: searching ? null : _search,
                  child: const Text('بحث')),
            ]),
            if (msg != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!, style: const TextStyle(color: Colors.orangeAccent))),
            if (searching || downloading)
              const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator(color: _peach)),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) {
                    final c = results[i];
                    return GestureDetector(
                      onTap: downloading ? null : () => _useUrl(c.url),
                      child: SizedBox(
                        width: 100,
                        child: Column(children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(c.url, width: 100, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white60)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _accent),
                onPressed: () {
                  final n = nameC.text.trim();
                  Navigator.pop(context, {
                    'name': (n.isEmpty || n == widget.game.name) ? null : n,
                    'cover': cover,
                    'fav': fav,
                  });
                },
                child: const Text('حفظ'),
              ),
            ]),
          ]),
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
    if (!mounted) return;
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
      onKeyEvent: (n, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.gameButtonB || e.logicalKey == LogicalKeyboardKey.escape)) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF1B0F09),
        appBar: AppBar(backgroundColor: const Color(0xFF1B0F09), title: const Text('التطبيقات المستثناة من الإغلاق')),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: _peach))
            : ListView.builder(
                itemCount: apps.length,
                itemBuilder: (_, i) {
                  final a = apps[i];
                  final keep = excluded.contains(a.package);
                  return SwitchListTile(
                    activeColor: _peach,
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
