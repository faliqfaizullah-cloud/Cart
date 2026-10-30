import 'dart:io';
import 'dart:math' as m;
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

const green = Color(0xFF16A068), ink = Color(0xFF111111), bg = Color(0xFFEAEAEA), mono = 'monospace';
void tap() => HapticFeedback.lightImpact();

// ---------- background isolate work ----------
const exts = {'mp3', 'm4a', 'flac', 'ogg', 'opus', 'wav', 'aac'};
List<List<Object>> scanFn(String root) {
  final out = <List<Object>>[];
  void walk(Directory d) {
    try {
      for (final e in d.listSync()) {
        final n = e.path.split('/').last;
        if (n.startsWith('.') || e.path == '$root/Android') continue;
        if (e is Directory) { walk(e); }
        else if (exts.contains(n.split('.').last.toLowerCase())) {
          var t = n.replaceAll(RegExp(r'\.\w+$'), ''), a = 'Unknown artist', al = 'Unknown album', g = '';
          try {
            final md = readMetadata(File(e.path));
            if ((md.title ?? '').isNotEmpty) t = md.title!;
            if ((md.artist ?? '').isNotEmpty) a = md.artist!;
            if ((md.album ?? '').isNotEmpty) al = md.album!;
            g = (md.genre ?? '').trim();
          } catch (_) {}
          out.add([e.path, t, a, al, g, File(e.path).lastModifiedSync().millisecondsSinceEpoch]);
        }
      }
    } catch (_) {}
  }
  walk(Directory(root));
  return out;
}

// Turns the real embedded album art into black-ink line drawing
Uint8List? doodleFn(String path) {
  try {
    final md = readMetadata(File(path), getImage: true);
    if (md.pictures.isEmpty) return null;
    var im = img.decodeImage(md.pictures.first.bytes);
    if (im == null) return null;
    im = img.copyResize(im, width: 240, interpolation: img.Interpolation.linear);
    final g = img.gaussianBlur(img.grayscale(im), radius: 1);
    final o = img.Image(width: g.width, height: g.height);
    num L(int x, int y) => g.getPixel(x.clamp(0, g.width - 1), y.clamp(0, g.height - 1)).r;
    for (var y = 0; y < g.height; y++) {
      for (var x = 0; x < g.width; x++) {
        final gx = L(x + 1, y - 1) + 2 * L(x + 1, y) + L(x + 1, y + 1) - L(x - 1, y - 1) - 2 * L(x - 1, y) - L(x - 1, y + 1);
        final gy = L(x - 1, y + 1) + 2 * L(x, y + 1) + L(x + 1, y + 1) - L(x - 1, y - 1) - 2 * L(x, y - 1) - L(x + 1, y - 1);
        final edge = m.sqrt(gx * gx + gy * gy) > 70;
        final hatch = L(x, y) < 70 && (x + y) % 5 == 0;
        final v = (edge || hatch) ? 15 : 250;
        o.setPixelRgb(x, y, v, v, v);
      }
    }
    return Uint8List.fromList(img.encodePng(o));
  } catch (_) { return null; }
}

Map<String, Object> lyricsFn(String path) {
  String? raw;
  try { final f = File('${path.replaceAll(RegExp(r'\.\w+$'), '')}.lrc'); if (f.existsSync()) raw = f.readAsStringSync(); } catch (_) {}
  if (raw == null) { try { raw = readMetadata(File(path)).lyrics; } catch (_) {} }
  final t = <int>[], l = <String>[];
  final re = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
  for (final ln in (raw ?? '').split(RegExp(r'\r?\n'))) {
    final ms = re.allMatches(ln).toList(), txt = ln.replaceAll(re, '').trim();
    if (ms.isNotEmpty) { for (final x in ms) { t.add(((int.parse(x[1]!) * 60 + double.parse(x[2]!)) * 1000).round()); l.add(txt); } }
    else if (ln.trim().isNotEmpty) { l.add(ln.trim()); }
  }
  return {'t': t, 'l': l};
}

// ---------- state ----------
class Song {
  final String path, title, artist, album, genre; final int added;
  Song(this.path, this.title, this.artist, this.album, this.genre, this.added);
  String get key => '$album|$artist';
}

class Lib extends ChangeNotifier {
  static final i = Lib._(); Lib._();
  List<Song> songs = []; List<String> favs = [], recent = []; bool busy = false; List<Uint8List> intro = [];
  late SharedPreferences sp; final _art = <String, Future<Uint8List?>>{};
  Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    favs = sp.getStringList('f') ?? []; recent = sp.getStringList('r') ?? [];
    if (await has()) await scan();
  }
  Future<bool> has() async => await Permission.audio.isGranted || await Permission.storage.isGranted || await Permission.manageExternalStorage.isGranted;
  Future<bool> ask() async {
    await Permission.audio.request(); await Permission.storage.request();
    if (!await Permission.manageExternalStorage.isGranted) await Permission.manageExternalStorage.request();
    return has();
  }
  Future<void> scan() async {
    busy = true; notifyListeners();
    final r = await compute(scanFn, '/storage/emulated/0');
    songs = [for (final x in r) Song(x[0] as String, x[1] as String, x[2] as String, x[3] as String, x[4] as String, x[5] as int)];
    busy = false; notifyListeners();
    final seen = <String>{}, out = <Uint8List>[]; var tries = 0;
    for (final s in songs) {
      if (out.length >= 5 || tries >= 30) break;
      if (!seen.add(s.key)) continue;
      tries++; final a = await art(s); if (a != null) out.add(a);
    }
    intro = out; notifyListeners();
  }
  Future<Uint8List?> art(Song s) => _art.putIfAbsent(s.key, () => compute(doodleFn, s.path));
  Song? byPath(String p) { for (final s in songs) { if (s.path == p) return s; } return null; }
  List<Song> get recents => recent.map(byPath).whereType<Song>().toList();
  List<Song> get favSongs => favs.map(byPath).whereType<Song>().toList();
  void addRecent(Song s) { recent..remove(s.path)..insert(0, s.path); if (recent.length > 20) recent.removeLast(); sp.setStringList('r', recent); notifyListeners(); }
  void toggleFav(Song s) { favs.contains(s.path) ? favs.remove(s.path) : favs.add(s.path); sp.setStringList('f', favs); HapticFeedback.selectionClick(); notifyListeners(); }
}

final player = AudioPlayer();
class Q {
  static List<Song> list = []; static int i = 0; static bool shuf = false;
  static final now = ValueNotifier<Song?>(null);
  static Future<void> play(List<Song> l, int k) async { list = l; i = k; await _go(); }
  static Future<void> _go() async {
    final s = list[i]; now.value = s; Lib.i.addRecent(s);
    try { await player.setFilePath(s.path); player.play(); } catch (_) {}
  }
  static Future<void> next() async { if (list.isEmpty) return; i = shuf ? m.Random().nextInt(list.length) : (i + 1) % list.length; await _go(); }
  static Future<void> prev() async {
    if (list.isEmpty) return;
    if (player.position.inSeconds > 3) { player.seek(Duration.zero); return; }
    i = (i - 1 + list.length) % list.length; await _go();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  player.processingStateStream.listen((s) { if (s == ProcessingState.completed) Q.next(); });
  Lib.i.init();
  runApp(MaterialApp(
    title: 'Cart', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: green, scaffoldBackgroundColor: bg),
    home: const Intro(),
  ));
}

// ---------- doodle art widget ----------
class Doodle extends StatelessWidget {
  final Song s; final double r;
  const Doodle(this.s, {this.r = 8, super.key});
  @override
  Widget build(BuildContext c) => FutureBuilder<Uint8List?>(
        future: Lib.i.art(s),
        builder: (_, sn) => ClipRRect(
          borderRadius: BorderRadius.circular(r),
          child: sn.data != null
              ? Image.memory(sn.data!, fit: BoxFit.cover, width: double.infinity, height: double.infinity, gaplessPlayback: true)
              : Container(color: Colors.white, child: const Center(child: Icon(Icons.music_note, color: Colors.black26, size: 32))),
        ),
      );
}

// ---------- opening animation ----------
class Intro extends StatefulWidget { const Intro({super.key}); @override State<Intro> createState() => _I(); }
class _I extends State<Intro> with SingleTickerProviderStateMixin {
  late final AnimationController a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  @override void dispose() { a.dispose(); super.dispose(); }
  static const pos = [[-.32, -.05, .08], [.0, .0, .0], [-.22, .22, .12], [.12, .3, .2], [-.15, .5, .3]];
  @override
  Widget build(BuildContext c) {
    final s = MediaQuery.of(c).size;
    return Scaffold(
      backgroundColor: ink,
      body: AnimatedBuilder(
        animation: Listenable.merge([a, Lib.i]),
        builder: (_, __) {
          double t(double d) => Curves.easeOutCubic.transform(((a.value - d) / .6).clamp(0, 1));
          final arts = Lib.i.intro;
          return Stack(children: [
            for (var k = 0; k < pos.length; k++)
              Positioned(
                left: s.width * (.15 + pos[k][0] * 1.2 + pos[k][2]) + (1 - t(pos[k][2])) * 300,
                top: s.height * (.02 + pos[k][1] * .8) - (1 - t(pos[k][2])) * 200,
                child: Opacity(
                  opacity: t(pos[k][2]),
                  child: Transform.rotate(
                    angle: .35,
                    child: Container(
                      width: s.width * .6, height: s.width * .75, padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.black, width: 4)),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 700),
                        child: arts.isEmpty
                            ? Container(key: const ValueKey(0), decoration: BoxDecoration(color: const Color(0xFFF3F3F3), borderRadius: BorderRadius.circular(16)), child: const Center(child: Icon(Icons.music_note, size: 60, color: Colors.black12)))
                            : ClipRRect(key: ValueKey(k), borderRadius: BorderRadius.circular(16), child: Image.memory(arts[k % arts.length], fit: BoxFit.cover, width: double.infinity, height: double.infinity)),
                      ),
                    ),
                  ),
                ),
              ),
            const Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, ink, ink])))),
            Positioned(
              left: 24, right: 24, bottom: 40,
              child: Opacity(
                opacity: t(.5),
                child: Transform.translate(
                  offset: Offset(0, 30 * (1 - t(.5))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    const Text('Music without\nborders', style: TextStyle(fontFamily: mono, fontWeight: FontWeight.w800, fontSize: 38, color: Colors.white, height: 1.15)),
                    const SizedBox(height: 14),
                    const Text('Create playlists, find new tracks and\nlisten to your favorite music anytime!', style: TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity, height: 56,
                      child: FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () async {
                          HapticFeedback.mediumImpact();
                          final L = Lib.i;
                          if (!await L.has() && !await L.ask()) {
                            if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Allow storage access so Cart can find your music')));
                            return;
                          }
                          if (L.songs.isEmpty) await L.scan();
                          if (c.mounted) Navigator.pushReplacement(c, PageRouteBuilder(transitionDuration: const Duration(milliseconds: 600), pageBuilder: (_, an, __) => FadeTransition(opacity: an, child: const Shell())));
                        },
                        child: const Text('Get started', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

// ---------- shell ----------
class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState() => _S(); }
class _S extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(child: IndexedStack(index: i, children: const [Home(), Favs(), Profile()])),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black12))),
          child: NavigationBar(
            backgroundColor: bg, indicatorColor: Colors.transparent, selectedIndex: i,
            onDestinationSelected: (v) { tap(); setState(() => i = v); },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: ink), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.favorite_border), selectedIcon: Icon(Icons.favorite, color: ink), label: 'Favorites'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: ink), label: 'Profile'),
            ],
          ),
        ),
      );
}

void openPlayer(BuildContext c, List<Song> l, int k) {
  tap(); Q.play(l, k);
  Navigator.push(c, PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (_, a, __) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: const Lyrics()),
  ));
}

Widget songRows(BuildContext c, List<Song> l) => Column(children: [
      for (var k = 0; k < l.length; k++)
        InkWell(
          onTap: () => openPlayer(c, l, k),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Container(width: 80, height: 80, decoration: BoxDecoration(border: Border.all(color: Colors.black87), borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.all(2), child: Doodle(l[k], r: 6)),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l[k].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Lib.i.favs.contains(l[k].path) ? Icons.favorite : Icons.check_circle, color: green, size: 19), const SizedBox(width: 6),
                  Expanded(child: Text(l[k].artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15))),
                ]),
              ])),
              PopupMenuButton<int>(
                icon: const Icon(Icons.more_vert), onOpened: tap,
                onSelected: (_) => Lib.i.toggleFav(l[k]),
                itemBuilder: (_) => [PopupMenuItem(value: 1, child: Text(Lib.i.favs.contains(l[k].path) ? 'Remove from favorites' : 'Add to favorites'))],
              ),
            ]),
          ),
        ),
    ]);

const hdr = TextStyle(fontFamily: mono, fontSize: 21, fontWeight: FontWeight.w600);

// ---------- home ----------
class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState() => _H(); }
class _H extends State<Home> {
  int tab = 0, spin = 0; String q = ''; bool searching = false;
  Widget sq(IconData i, VoidCallback f) => Container(
        width: 52, height: 52, margin: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.black87), borderRadius: BorderRadius.circular(14)),
        child: IconButton(onPressed: f, icon: Icon(i)),
      );
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: Lib.i,
        builder: (_, __) {
          final L = Lib.i, cnt = <String, int>{};
          for (final s in L.songs) { if (s.genre.isNotEmpty) cnt[s.genre] = (cnt[s.genre] ?? 0) + 1; }
          final g = (cnt.keys.toList()..sort((a, b) => cnt[b]!.compareTo(cnt[a]!))).take(4).toList();
          final tabs = ['All', ...g]; if (tab >= tabs.length) tab = 0;
          final list = L.songs.where((s) => (tab == 0 || s.genre == tabs[tab]) && (q.isEmpty || '${s.title} ${s.artist}'.toLowerCase().contains(q.toLowerCase()))).toList();
          final feat = (List<Song>.of(list)..shuffle(m.Random(spin))).take(8).toList();
          final rec = L.recents;
          final now = DateTime.now().millisecondsSinceEpoch;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 20), children: [
            Row(children: [
              const CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.black54)),
              const Spacer(),
              if (searching) Expanded(flex: 4, child: TextField(autofocus: true, onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search songs', isDense: true))),
              sq(searching ? Icons.close : Icons.search, () { tap(); setState(() { searching = !searching; q = ''; }); }),
              sq(Icons.notifications_none, tap),
            ]),
            const SizedBox(height: 22),
            SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
              for (var k = 0; k < tabs.length; k++)
                GestureDetector(
                  onTap: () { tap(); setState(() => tab = k); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250), margin: const EdgeInsets.only(right: 22), padding: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 3, color: k == tab ? ink : Colors.transparent))),
                    child: Text(tabs[k], style: TextStyle(fontFamily: mono, fontSize: 17, fontWeight: k == tab ? FontWeight.w800 : FontWeight.w400, color: k == tab ? ink : Colors.black45)),
                  ),
                )
            ])),
            const SizedBox(height: 28),
            Row(children: [
              Expanded(child: Text('${tabs[tab]} Essentials', style: hdr)),
              GestureDetector(
                onTap: () { HapticFeedback.selectionClick(); setState(() => spin++); L.scan(); },
                child: AnimatedRotation(
                  turns: spin * .5, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut,
                  child: Container(width: 52, height: 52, decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.sync, color: Colors.white)),
                ),
              ),
            ]),
            const SizedBox(height: 18),
            if (L.busy) const LinearProgressIndicator(color: green),
            if (list.isEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text(L.busy ? 'Scanning your music...' : 'No songs found. Add music files and tap the green refresh button.', textAlign: TextAlign.center))
            else ...[
              SizedBox(height: 270, child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final s in feat)
                  GestureDetector(
                    onTap: () => openPlayer(c, feat, feat.indexOf(s)),
                    child: Container(
                      width: 210, margin: const EdgeInsets.only(right: 14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.black87, width: 1.5)),
                      child: Column(children: [
                        Expanded(child: Stack(children: [
                          Padding(padding: const EdgeInsets.all(4), child: Doodle(s, r: 14)),
                          if (now - s.added < 14 * 86400000)
                            Positioned(left: 10, top: 10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black26)), child: const Text('NEW', style: TextStyle(fontFamily: mono, fontSize: 12)))),
                        ])),
                        Container(
                          height: 64, padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: const BoxDecoration(color: ink, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                          child: Row(children: [
                            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                              Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                            ])),
                            const Icon(Icons.south_east, color: Colors.white, size: 20),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ])),
              if (rec.isNotEmpty) ...[const SizedBox(height: 28), const Text('Recently listened', style: hdr), const SizedBox(height: 14), songRows(c, rec.take(5).toList())],
              const SizedBox(height: 28), Text('Library (${list.length})', style: hdr), const SizedBox(height: 14), songRows(c, list),
            ],
          ]);
        },
      );
}

class Favs extends StatelessWidget {
  const Favs({super.key});
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: Lib.i,
        builder: (_, __) {
          final f = Lib.i.favSongs;
          return ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Favorites', style: hdr), const SizedBox(height: 14),
            if (f.isEmpty) const Text('Tap ⋮ on any song to add it here.') else songRows(c, f),
          ]);
        },
      );
}

class Profile extends StatelessWidget {
  const Profile({super.key});
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
        animation: Lib.i,
        builder: (_, __) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircleAvatar(radius: 44, backgroundColor: Colors.white, child: Icon(Icons.person, size: 44, color: Colors.black54)),
          const SizedBox(height: 16),
          Text('${Lib.i.songs.length} songs · ${Lib.i.songs.map((s) => s.album).toSet().length} albums', style: hdr),
          const SizedBox(height: 16),
          FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: green), onPressed: () { HapticFeedback.mediumImpact(); Lib.i.scan(); }, icon: const Icon(Icons.sync), label: Text(Lib.i.busy ? 'Scanning...' : 'Rescan library')),
        ])),
      );
}

// ---------- player + lyrics ----------
class Lyrics extends StatefulWidget { const Lyrics({super.key}); @override State<Lyrics> createState() => _L(); }
class _L extends State<Lyrics> {
  Song? s; List<String> lines = []; List<int> times = []; int cur = 0; final sc = ScrollController();
  bool get synced => times.isNotEmpty && times.length == lines.length;
  @override
  void initState() {
    super.initState();
    Q.now.addListener(load); load();
    player.positionStream.listen((p) {
      if (lines.isEmpty || !mounted) return;
      var n = 0;
      if (synced) { for (var k = 0; k < times.length; k++) { if (times[k] <= p.inMilliseconds) n = k; } }
      else { final d = player.duration?.inMilliseconds ?? 0; if (d > 0) n = (p.inMilliseconds / d * lines.length).floor().clamp(0, lines.length - 1); }
      if (n != cur) { setState(() => cur = n); if (sc.hasClients) sc.animateTo(m.max(0, n * 46.0 - 92), duration: const Duration(milliseconds: 400), curve: Curves.easeOut); }
    });
  }
  @override void dispose() { Q.now.removeListener(load); sc.dispose(); super.dispose(); }
  Future<void> load() async {
    final n = Q.now.value; if (n == null) return;
    setState(() { s = n; lines = []; times = []; cur = 0; });
    final r = await compute(lyricsFn, n.path);
    if (!mounted || Q.now.value != n) return;
    setState(() { lines = (r['l'] as List).cast<String>(); times = (r['t'] as List).cast<int>(); });
  }
  Widget ctl(IconData i, VoidCallback f, [bool on = false]) => IconButton(onPressed: () { tap(); f(); }, icon: Icon(i, color: on ? green : Colors.white, size: 28));
  @override
  Widget build(BuildContext c) {
    final song = s;
    return Scaffold(
      body: SafeArea(child: Column(children: [
        Row(children: [
          IconButton(onPressed: () { tap(); Navigator.pop(c); }, icon: const Icon(Icons.chevron_left, size: 32)),
          const Expanded(child: Center(child: Text('Lyrics', style: TextStyle(fontFamily: mono, fontSize: 18, fontWeight: FontWeight.w600)))),
          IconButton(onPressed: song == null ? null : () => Lib.i.toggleFav(song), icon: AnimatedBuilder(animation: Lib.i, builder: (_, __) => Icon(song != null && Lib.i.favs.contains(song.path) ? Icons.favorite : Icons.favorite_border, color: green))),
        ]),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Container(
            height: 280, padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.black87, width: 2)),
            child: song == null ? null : Doodle(song, r: 12),
          ),
        ),
        Text(song?.artist ?? '', maxLines: 1, style: const TextStyle(fontFamily: mono, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(constraints: const BoxConstraints(maxWidth: 260), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(16)), child: Text((song?.title ?? '').toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontFamily: mono, fontSize: 12))),
        StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (_, sn) {
            final d = (player.duration ?? Duration.zero).inMilliseconds.toDouble(), p = (sn.data ?? Duration.zero).inMilliseconds.toDouble();
            return SliderTheme(data: SliderTheme.of(c).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)), child: Slider(activeColor: green, inactiveColor: Colors.black12, value: d <= 0 ? 0 : p.clamp(0, d), max: d <= 0 ? 1 : d, onChanged: (v) => player.seek(Duration(milliseconds: v.round()))));
          },
        ),
        Expanded(
          child: lines.isEmpty
              ? const Center(child: Text('No lyrics found.\nEmbed lyrics in the file or put a .lrc\nwith the same name next to it.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)))
              : ListView.builder(
                  controller: sc, itemExtent: 46, itemCount: lines.length,
                  itemBuilder: (_, k) => Center(child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(fontSize: 19, fontWeight: k <= cur ? FontWeight.w600 : FontWeight.w400, color: k <= cur ? ink : Colors.black38),
                    child: Text(lines[k], maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  )),
                ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(14, 6, 14, 14), padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(18)),
          child: StreamBuilder<bool>(
            stream: player.playingStream,
            builder: (_, sn) {
              final pl = sn.data ?? false;
              return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                ctl(Icons.repeat, () { setState(() {}); player.setLoopMode(player.loopMode == LoopMode.one ? LoopMode.off : LoopMode.one); }, player.loopMode == LoopMode.one),
                ctl(Icons.skip_previous, Q.prev),
                GestureDetector(
                  onTap: () { HapticFeedback.mediumImpact(); pl ? player.pause() : player.play(); },
                  child: Container(width: 72, height: 56, decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(14)), child: Icon(pl ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32)),
                ),
                ctl(Icons.skip_next, Q.next),
                ctl(Icons.shuffle, () => setState(() => Q.shuf = !Q.shuf), Q.shuf),
              ]);
            },
          ),
        ),
      ])),
    );
  }
}
