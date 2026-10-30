import 'dart:async';
import 'dart:math' as m;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const green = Color(0xFF16A068), ink = Color(0xFF111111), bg = Color(0xFFEAEAEA);
const mono = 'monospace';
void tap() => HapticFeedback.lightImpact();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(MaterialApp(
    title: 'Cart',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: green, scaffoldBackgroundColor: bg),
    home: const Intro(),
  ));
}

class Art extends StatelessWidget {
  final Color c; final IconData i; final double r;
  const Art(this.c, this.i, {this.r = 14, super.key});
  @override
  Widget build(BuildContext x) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r),
          gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, .6)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(child: Icon(i, color: Colors.white70, size: 36)),
      );
}

// ---------- Opening animation + welcome ----------
class Intro extends StatefulWidget { const Intro({super.key}); @override State<Intro> createState() => _I(); }
class _I extends State<Intro> with SingleTickerProviderStateMixin {
  late final AnimationController a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..forward();
  @override void dispose() { a.dispose(); super.dispose(); }
  static const tiles = [
    [Color(0xFF0F9D58), Icons.music_note, -.32, -.05, .08],
    [Color(0xFFE8531F), Icons.album, .0, .0, .0],
    [Color(0xFFB0B0B0), Icons.people, -.22, .22, .12],
    [Color(0xFF1E88E5), Icons.headphones, .12, .3, .2],
    [Color(0xFFE6C619), Icons.graphic_eq, -.15, .5, .3],
  ];
  @override
  Widget build(BuildContext c) {
    final s = MediaQuery.of(c).size;
    return Scaffold(
      backgroundColor: ink,
      body: AnimatedBuilder(
        animation: a,
        builder: (_, __) {
          double t(double d) => Curves.easeOutCubic.transform(((a.value - d) / .6).clamp(0, 1));
          return Stack(children: [
            for (final k in tiles)
              Positioned(
                left: s.width * (.15 + (k[2] as double) * 1.2 + (k[4] as double)) + (1 - t(k[4] as double)) * 300,
                top: s.height * (.02 + (k[3] as double) * .8) - (1 - t(k[4] as double)) * 200,
                child: Opacity(
                  opacity: t(k[4] as double),
                  child: Transform.rotate(
                    angle: .35,
                    child: Container(
                      width: s.width * .6, height: s.width * .75,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: Colors.black, width: 4)),
                      child: Art(k[0] as Color, k[1] as IconData, r: 16),
                    ),
                  ),
                ),
              ),
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, ink, ink]))) ),
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
                        onPressed: () { HapticFeedback.mediumImpact(); Navigator.pushReplacement(c, PageRouteBuilder(transitionDuration: const Duration(milliseconds: 600), pageBuilder: (_, a, __) => FadeTransition(opacity: a, child: const Shell()))); },
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

// ---------- Shell ----------
class Shell extends StatefulWidget { const Shell({super.key}); @override State<Shell> createState() => _S(); }
class _S extends State<Shell> {
  int i = 0;
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(child: IndexedStack(index: i, children: const [Home(), Center(child: Text('Favorites')), Center(child: Text('Profile'))])),
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

// ---------- Home ----------
class Home extends StatefulWidget { const Home({super.key}); @override State<Home> createState() => _H(); }
class _H extends State<Home> with SingleTickerProviderStateMixin {
  int tab = 1; int spin = 0;
  static const tabs = ['All', 'IDM', 'Rock', 'Pop', 'Alternative'];
  static const recent = [
    ['Bone', 'Sonic Youth', Color(0xFF444444), Icons.person],
    ['Review', 'Depeche Mode', Color(0xFFD33F49), Icons.blur_on],
    ['Drowning', 'Woodz', Color(0xFF1E88E5), Icons.face],
  ];
  Widget sq(IconData i) => Container(
        width: 52, height: 52,
        decoration: BoxDecoration(border: Border.all(color: Colors.black87), borderRadius: BorderRadius.circular(14)),
        child: IconButton(onPressed: tap, icon: Icon(i)),
      );
  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 20), children: [
        Row(children: [
          const CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Icon(Icons.person, color: Colors.black54)),
          const Spacer(), sq(Icons.search), const SizedBox(width: 12), sq(Icons.notifications_none),
        ]),
        const SizedBox(height: 22),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (var k = 0; k < tabs.length; k++)
              GestureDetector(
                onTap: () { tap(); setState(() => tab = k); },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.only(right: 22), padding: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 3, color: k == tab ? ink : Colors.transparent))),
                  child: Text(tabs[k], style: TextStyle(fontFamily: mono, fontSize: 17, fontWeight: k == tab ? FontWeight.w800 : FontWeight.w400, color: k == tab ? ink : Colors.black45)),
                ),
              )
          ]),
        ),
        const SizedBox(height: 28),
        Row(children: [
          Text('${tabs[tab]} Essentials', style: const TextStyle(fontFamily: mono, fontSize: 21, fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); setState(() => spin++); },
            child: AnimatedRotation(
              turns: spin * .5, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut,
              child: Container(width: 52, height: 52, decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.sync, color: Colors.white)),
            ),
          ),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: 270,
          child: ListView(scrollDirection: Axis.horizontal, children: const [
            Feature('LIVE', 'Aphex Twin', 'Live performance', Color(0xFFB9B9B9), Icons.mic),
            Feature('NEW', 'Nelly Mes', 'Album presentation', Color(0xFFD7D7D7), Icons.headphones),
            Feature('', 'Amon Tobin', 'Live', Color(0xFFC4C4C4), Icons.graphic_eq),
          ]),
        ),
        const SizedBox(height: 28),
        const Text('Recently listened', style: TextStyle(fontFamily: mono, fontSize: 21, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        for (final r in recent)
          InkWell(
            onTap: () { tap(); Navigator.push(c, PageRouteBuilder(transitionDuration: const Duration(milliseconds: 500), pageBuilder: (_, a, __) => SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: Lyrics(r[0] as String, r[1] as String, r[2] as Color, r[3] as IconData)))); },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 88, height: 88, child: Art(r[2] as Color, r[3] as IconData, r: 6)),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r[0] as String, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Row(children: [const Icon(Icons.check_circle, color: green, size: 20), const SizedBox(width: 6), Text(r[1] as String, style: const TextStyle(fontSize: 16))]),
                ])),
                const Icon(Icons.more_vert),
              ]),
            ),
          ),
      ]);
}

class Feature extends StatelessWidget {
  final String badge, title, sub; final Color col; final IconData ic;
  const Feature(this.badge, this.title, this.sub, this.col, this.ic, {super.key});
  @override
  Widget build(BuildContext c) => GestureDetector(
        onTap: tap,
        child: Container(
          width: 210, margin: const EdgeInsets.only(right: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.black87, width: 1.5)),
          child: Column(children: [
            Expanded(child: Stack(children: [
              Center(child: Icon(ic, size: 90, color: Colors.black87)),
              if (badge.isNotEmpty)
                Positioned(left: 10, top: 10, child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.black26)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (badge == 'LIVE') const Padding(padding: EdgeInsets.only(right: 5), child: CircleAvatar(radius: 4, backgroundColor: Colors.deepOrange)),
                    Text(badge, style: const TextStyle(fontFamily: mono, fontSize: 12)),
                  ]),
                )),
            ])),
            Container(
              height: 64, padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: const BoxDecoration(color: ink, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
              child: Row(children: [
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                  Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ])),
                const Icon(Icons.south_east, color: Colors.white, size: 20),
              ]),
            ),
          ]),
        ),
      );
}

// ---------- Lyrics / player ----------
class Lyrics extends StatefulWidget {
  final String song, artist; final Color col; final IconData ic;
  const Lyrics(this.song, this.artist, this.col, this.ic, {super.key});
  @override State<Lyrics> createState() => _L();
}
class _L extends State<Lyrics> {
  // Placeholder lines - plug in licensed lyrics from your own API.
  final lines = List.generate(9, (k) => 'Lyric line ${k + 1} goes here');
  int cur = 3; bool playing = true; Timer? t;
  @override void initState() { super.initState(); t = Timer.periodic(const Duration(seconds: 3), (_) { if (playing && mounted) setState(() => cur = (cur + 1) % lines.length); }); }
  @override void dispose() { t?.cancel(); super.dispose(); }
  Widget ctl(IconData i, [VoidCallback? f]) => IconButton(onPressed: f ?? tap, icon: Icon(i, color: Colors.white, size: 28));
  @override
  Widget build(BuildContext c) => Scaffold(
        body: SafeArea(child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              IconButton(onPressed: () { tap(); Navigator.pop(c); }, icon: const Icon(Icons.chevron_left, size: 32)),
              const Expanded(child: Center(child: Text('Lyrics', style: TextStyle(fontFamily: mono, fontSize: 18, fontWeight: FontWeight.w600)))),
              IconButton(onPressed: tap, icon: const Icon(Icons.open_in_new)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Hero(tag: widget.song, child: Container(
              height: 300, padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.black87, width: 2)),
              child: Art(widget.col, widget.ic, r: 10),
            )),
          ),
          Text(widget.artist, style: const TextStyle(fontFamily: mono, fontSize: 19, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(16)), child: Text(widget.song.toUpperCase(), style: const TextStyle(color: Colors.white, fontFamily: mono, fontSize: 12))),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 18), itemCount: lines.length,
              itemBuilder: (_, k) => AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 400), textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: k <= cur ? FontWeight.w600 : FontWeight.w400, color: k <= cur ? ink : Colors.black38),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Text(lines[k], textAlign: TextAlign.center)),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14), padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(18)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              ctl(Icons.repeat), ctl(Icons.skip_previous, () { tap(); setState(() => cur = m.max(0, cur - 1)); }),
              GestureDetector(
                onTap: () { HapticFeedback.mediumImpact(); setState(() => playing = !playing); },
                child: Container(width: 72, height: 56, decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(14)), child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32)),
              ),
              ctl(Icons.skip_next, () { tap(); setState(() => cur = (cur + 1) % lines.length); }), ctl(Icons.shuffle),
            ]),
          ),
        ])),
      );
}
