import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const SurfacePlayerApp());
}

// ─────────────────────────────────────────────
//  THEME
// ─────────────────────────────────────────────
const kBg     = Color(0xFF080010);
const kCard   = Color(0xFF110020);
const kCardHi = Color(0xFF1E003A);
const kPurple = Color(0xFF7B2FFF);
const kViolet = Color(0xFF9B30FF);
const kNeon   = Color(0xFFBF7FFF);
const kPink   = Color(0xFFE040FB);
const kWhite  = Color(0xFFF0E8FF);
const kDim    = Color(0xFF6B5A80);
const kGlass  = Color(0x18FFFFFF);
const kGlassB = Color(0x0CFFFFFF);
const kBorder = Color(0x22FFFFFF);

const kDiscAsset = 'assets/top_hits_disc.png';

// ─────────────────────────────────────────────
//  LYRIC LINE MODEL
// ─────────────────────────────────────────────
class LyricLine {
  final Duration timestamp;
  final String text;
  const LyricLine({required this.timestamp, required this.text});
}

// ─────────────────────────────────────────────
//  LYRICS PARSER
// ─────────────────────────────────────────────
class LyricsParser {
  static List<LyricLine> parse(String raw) {
    final lrcPattern = RegExp(r'^\[(\d+):(\d+)[\.:](\d+)\]\s*(.*)$');
    final synced = <LyricLine>[];

    for (final line in raw.split('\n')) {
      final m = lrcPattern.firstMatch(line.trim());
      if (m != null) {
        final min  = int.parse(m.group(1)!);
        final sec  = int.parse(m.group(2)!);
        final frac = m.group(3)!;
        final text = m.group(4)!.trim();
        if (text.isEmpty) continue;
        final ms = frac.length >= 3 ? int.parse(frac) : int.parse(frac) * 10;
        synced.add(LyricLine(
          timestamp: Duration(minutes: min, seconds: sec, milliseconds: ms),
          text: text,
        ));
      }
    }
    if (synced.isNotEmpty) return synced;

    return raw.split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) => LyricLine(timestamp: Duration.zero, text: l))
        .toList();
  }

  static bool isSynced(List<LyricLine> lines) =>
      lines.length > 1 && lines.any((l) => l.timestamp > Duration.zero);
}

// ─────────────────────────────────────────────
//  TRACK MODEL
// ─────────────────────────────────────────────
class MusicTrack {
  final String id, title, artist, album, imageUrl, imageUrlHd;
  final int durationMs;
  final String? genre;

  const MusicTrack({
    required this.id, required this.title, required this.artist,
    required this.album, required this.imageUrl, required this.imageUrlHd,
    required this.durationMs, this.genre,
  });


  String get durationStr {
    final s = durationMs ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
//  SPOTIFY SERVICE
// ─────────────────────────────────────────────
class MusicService {
  static const _clientId     = 'c44ad8469e19464bb164707f2f2b5252';
  static const _clientSecret = '195fcadd1f5b4441bcc02ca58a734164';
  String? _token;
  DateTime? _tokenExpiry;

  Future<String?> _getToken() async {
    if (_token != null && _tokenExpiry != null && DateTime.now().isBefore(_tokenExpiry!)) return _token;
    final creds = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
    final res = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {'Authorization': 'Basic $creds', 'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=client_credentials',
    );
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map;
    _token = data['access_token'] as String?;
    _tokenExpiry = DateTime.now().add(Duration(seconds: (data['expires_in'] as int) - 30));
    return _token;
  }

  MusicTrack _fromSpotify(Map t) => MusicTrack(
    id:         t['id'] as String? ?? '',
    title:      t['name'] as String? ?? '',
    artist:     (t['artists'] as List).map((a) => a['name']).join(', '),
    album:      t['album']['name'] as String? ?? '',
    imageUrl:   (t['album']['images'] as List).isNotEmpty ? t['album']['images'][0]['url'] as String : '',
    imageUrlHd: (t['album']['images'] as List).isNotEmpty ? t['album']['images'][0]['url'] as String : '',
    durationMs: t['duration_ms'] as int? ?? 0,
    genre:      null,
  );

  Future<List<MusicTrack>> search(String query) async {
    final token = await _getToken();
    if (token == null) return [];
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/search?q=${Uri.encodeComponent(query)}&type=track&limit=25'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return [];
    final items = (jsonDecode(res.body) as Map)['tracks']['items'] as List;
    return items.map((t) => _fromSpotify(t as Map)).where((t) => t.title.isNotEmpty).toList();
  }

  Future<List<MusicTrack>> getTopCharts() async {
    final token = await _getToken();
    if (token == null) return [];
    final res = await http.get(
      Uri.parse('https://api.spotify.com/v1/playlists/37i9dQZEVXbMDoHDwVN2tF/tracks?limit=25'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) return search('top hits 2025');
    final items = (jsonDecode(res.body) as Map)['items'] as List;
    return items
        .where((i) => i['track'] != null)
        .map((i) => _fromSpotify(i['track'] as Map))
        .where((t) => t.title.isNotEmpty).toList();
  }

  Future<String?> getLyricsRaw(String artist, String title) async {
    try {
      final uri = Uri.parse('https://lrclib.net/api/get')
          .replace(queryParameters: {'artist_name': artist, 'track_name': title});
      final res = await http.get(uri, headers: {'User-Agent': 'SurfacePlayer/1.0'});
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body) as Map;
        final synced = d['syncedLyrics'] as String?;
        if (synced != null && synced.trim().isNotEmpty) return synced;
        final plain = d['plainLyrics'] as String?;
        if (plain != null && plain.trim().isNotEmpty) return plain;
      }
    } catch (_) {}
    return null;
  }
}

// ─────────────────────────────────────────────
//  AUDIO SERVICE  (just_audio + youtube_explode)
// ─────────────────────────────────────────────
const _kPipedInstances = [
  'https://pipedapi.kavin.rocks',
  'https://pipedapi.adminforge.de',
  'https://piped-api.garudalinux.org',
];

class AudioService {
  final _player = AudioPlayer();
  AudioPlayer get player => _player;

  Future<void> playTrack(MusicTrack track) async {
    try {
      await _player.stop();

      final query = Uri.encodeComponent('${track.artist} ${track.title} official audio');
      String? videoId;

      for (final base in _kPipedInstances) {
        try {
          final res = await http.get(
            Uri.parse('$base/search?q=$query&filter=music_songs'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) continue;
          final items = (jsonDecode(res.body) as Map)['items'] as List? ?? [];
          for (final item in items) {
            final url = item['url'] as String? ?? '';
            final title = (item['title'] as String? ?? '').toLowerCase();
            final bad = title.contains('cover') || title.contains('karaoke') || title.contains('reaction');
            if (!bad && url.contains('watch?v=')) {
              videoId = url.split('watch?v=').last.split('&').first;
              break;
            }
          }
          if (videoId != null) break;
        } catch (_) { continue; }
      }
      if (videoId == null) { debugPrint('AudioService: no video found'); return; }

      String? streamUrl;
      for (final base in _kPipedInstances) {
        try {
          final res = await http.get(
            Uri.parse('$base/streams/$videoId'),
            headers: {'Accept': 'application/json'},
          ).timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) continue;
          final data = jsonDecode(res.body) as Map;
          final streams = (data['audioStreams'] as List? ?? [])
            .where((s) => (s['mimeType'] as String? ?? '').contains('audio'))
            .toList()
            ..sort((a, b) => (b['bitrate'] as int? ?? 0).compareTo(a['bitrate'] as int? ?? 0));
          streamUrl = streams.isNotEmpty ? streams.first['url'] as String? : null;
          if (streamUrl != null) break;
        } catch (_) { continue; }
      }
      if (streamUrl == null) { debugPrint('AudioService: no stream url'); return; }

      await _player.setAudioSource(AudioSource.uri(Uri.parse(streamUrl)));
      await _player.play();
    } catch (e) {
      debugPrint('AudioService error: $e');
    }
  }

  Future<void> pause()  => _player.pause();
  Future<void> resume() => _player.play();
  Future<void> seek(Duration p) => _player.seek(p);
  void setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));
  void dispose() => _player.dispose();
}

// ─────────────────────────────────────────────
//  PLAYER STATE
// ─────────────────────────────────────────────
class PlayerState extends ChangeNotifier {
  MusicTrack? currentTrack;
  bool isPlaying = false, loadingAudio = false;
  List<MusicTrack> queue = [];
  int queueIndex = -1;

  List<LyricLine> lyricLines = [];
  bool loadingLyrics = false;
  bool get hasSyncedLyrics => LyricsParser.isSynced(lyricLines);

  double vocalVolume = 1.0; // 1=full music, 0=muted for karaoke

  final _music = MusicService();
  final audio  = AudioService();

  Duration _position = Duration.zero;
  Duration get position => _position;
  Duration get totalDuration => audio.player.duration ?? Duration.zero;

  StreamSubscription? _stateSub, _posSub;

  PlayerState() {
    _stateSub = audio.player.playerStateStream.listen((s) {
      isPlaying = s.playing;
      notifyListeners();
    });
    _posSub = audio.player.positionStream.listen((p) {
      _position = p;
      notifyListeners();
    });
  }

  void setTrack(MusicTrack track, List<MusicTrack> list, int idx) {
    currentTrack = track;
    queue = list;
    queueIndex = idx;
    isPlaying = false;
    lyricLines = [];
    loadingAudio = true;
    _position = Duration.zero;
    notifyListeners();

    audio.setVolume(vocalVolume);
    audio.playTrack(track).then((_) {
      loadingAudio = false;
      notifyListeners();
    });
    _fetchLyrics(track);
  }

  Future<void> _fetchLyrics(MusicTrack t) async {
    loadingLyrics = true; notifyListeners();
    final raw = await _music.getLyricsRaw(t.artist.split(',').first.trim(), t.title);
    lyricLines = raw != null ? LyricsParser.parse(raw) : [];
    loadingLyrics = false; notifyListeners();
  }

  void next()     { if (queueIndex < queue.length - 1) setTrack(queue[queueIndex + 1], queue, queueIndex + 1); }
  void previous() { if (queueIndex > 0) setTrack(queue[queueIndex - 1], queue, queueIndex - 1); }

  void togglePlay() => isPlaying ? audio.pause() : audio.resume();

  void setVocalVolume(double v) {
    vocalVolume = v;
    audio.setVolume(v);
    notifyListeners();
  }

  @override
  void dispose() {
    _stateSub?.cancel(); _posSub?.cancel(); audio.dispose();
    super.dispose();
  }
}

final playerState = PlayerState();

// ─────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────
class SurfacePlayerApp extends StatelessWidget {
  const SurfacePlayerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SurfacePlayer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: kBg,
          colorScheme: const ColorScheme.dark(primary: kViolet, secondary: kNeon, surface: kCard),
        ),
        home: const HomeScreen(),
      );
}

// ─────────────────────────────────────────────
//  HOME SCREEN
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focus      = FocusNode();
  final _music      = MusicService();

  List<MusicTrack> _results = [], _charts = [];
  bool _searching = false, _loadingCharts = true, _searchMode = false;
  String _searchError = '';

  late AnimationController _bgAnim, _pulseAnim, _searchFocusAnim;

  @override
  void initState() {
    super.initState();
    _bgAnim          = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _pulseAnim       = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _searchFocusAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _searchCtrl.addListener(() => setState(() {}));
    _loadCharts();
  }

  @override
  void dispose() {
    _bgAnim.dispose(); _pulseAnim.dispose(); _searchFocusAnim.dispose();
    _searchCtrl.dispose(); _focus.dispose();
    super.dispose();
  }

  Future<void> _loadCharts() async {
    try {
      final c = await _music.getTopCharts();
      if (mounted) setState(() { _charts = c; _loadingCharts = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingCharts = false);
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() { _searching = true; _searchMode = true; _searchError = ''; });
    try {
      final r = await _music.search(q.trim());
      if (mounted) setState(() {
        _results = r; _searching = false;
        _searchError = r.isEmpty ? 'No results for "$q"' : '';
      });
    } catch (_) {
      if (mounted) setState(() { _searching = false; _searchError = 'Search failed. Check connection.'; });
    }
  }

  void _clearSearch() {
    _searchCtrl.clear(); _focus.unfocus(); _searchFocusAnim.reverse();
    setState(() { _searchMode = false; _results = []; _searchError = ''; });
  }

  void _openPlayer() => Navigator.of(context).push(PageRouteBuilder(
        pageBuilder: (_, a, s) => const PlayerScreen(),
        transitionsBuilder: (_, a, s, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutQuart)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 420),
      ));

  void _playTrack(MusicTrack t, List<MusicTrack> list, int idx) {
    playerState.setTrack(t, list, idx);
    _openPlayer();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: kBg,
        body: Stack(children: [
          AnimatedBuilder(animation: _bgAnim, builder: (_, __) => Container(
            decoration: BoxDecoration(gradient: RadialGradient(
              center: Alignment(0.5 - _bgAnim.value, -0.5 + _bgAnim.value * 0.3),
              radius: 1.3,
              colors: [kPurple.withValues(alpha: 0.22), kBg], stops: const [0.0, 0.6],
            )),
          )),
          Positioned(top: 40, right: -50, child: _GlowOrb(radius: 160, color: kPurple.withValues(alpha: 0.16), anim: _bgAnim)),
          Positioned(bottom: 200, left: -70, child: _GlowOrb(radius: 200, color: kPink.withValues(alpha: 0.07), anim: _pulseAnim)),
          SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(), _buildSearchBar(),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220),
                child: _searchMode ? _buildSearchResults() : _buildHome())),
          ])),
          ListenableBuilder(listenable: playerState, builder: (_, __) =>
              playerState.currentTrack != null
                  ? Positioned(bottom: 0, left: 0, right: 0, child: _MiniPlayer(onTap: _openPlayer))
                  : const SizedBox.shrink()),
        ]),
      );

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [kNeon, kViolet, kPink]).createShader(r),
              child: const Text('SurfacePlayer', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: Colors.white)),
            ),
            Text('iTunes · YouTube Audio · Karaoke', style: TextStyle(fontSize: 10.5, color: kDim)),
          ]),
          const Spacer(),
          AnimatedBuilder(animation: _pulseAnim, builder: (_, __) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: kGlassB, border: Border.all(color: kBorder)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Color.lerp(kViolet, kPink, _pulseAnim.value),
                  boxShadow: [BoxShadow(color: kViolet.withValues(alpha: 0.9), blurRadius: 6)])),
              const SizedBox(width: 6),
              const Text('LIVE', style: TextStyle(fontSize: 10, color: kNeon, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            ]),
          )),
        ]),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: AnimatedBuilder(animation: _searchFocusAnim, builder: (_, __) => Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Color.lerp(kGlassB, kGlass, _searchFocusAnim.value),
            border: Border.all(color: Color.lerp(kBorder, kViolet.withValues(alpha: 0.55), _searchFocusAnim.value)!, width: 1.2),
            boxShadow: [BoxShadow(color: kViolet.withValues(alpha: 0.14 * _searchFocusAnim.value), blurRadius: 24)],
          ),
          child: TextField(
            controller: _searchCtrl, focusNode: _focus,
            style: const TextStyle(color: kWhite, fontSize: 15, fontWeight: FontWeight.w500),
            cursorColor: kViolet,
            onTap: () => _searchFocusAnim.forward(),
            onSubmitted: _search,
            decoration: InputDecoration(
              hintText: 'Artists, songs, albums…',
              hintStyle: TextStyle(color: kDim, fontSize: 15),
              prefixIcon: Padding(padding: const EdgeInsets.all(14),
                  child: Icon(Icons.search_rounded, color: Color.lerp(kDim, kViolet, _searchFocusAnim.value), size: 22)),
              suffixIcon: _searchCtrl.text.isNotEmpty || _searchMode
                  ? IconButton(icon: const Icon(Icons.close_rounded, color: kDim, size: 20), onPressed: _clearSearch)
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        )),
      );

  Widget _buildHome() {
    if (_loadingCharts) return const Center(child: _PurpleSpinner());
    return CustomScrollView(key: const ValueKey('home'), slivers: [
      SliverToBoxAdapter(child: _sectionHeader('🔥', 'Top Charts')),
      SliverToBoxAdapter(child: SizedBox(height: 222, child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 20, right: 8),
        itemCount: _charts.take(12).length,
        itemBuilder: (_, i) => _HeroCard(track: _charts[i], rank: i + 1,
            onTap: () => _playTrack(_charts[i], _charts, i)),
      ))),
      SliverToBoxAdapter(child: _sectionHeader('🎵', 'All Songs')),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          (_, i) => _TrackRow(track: _charts[i], onTap: () => _playTrack(_charts[i], _charts, i)),
          childCount: _charts.length,
        )),
      ),
    ]);
  }

  Widget _sectionHeader(String emoji, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)), const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kWhite, letterSpacing: -0.4)),
        ]),
      );

  Widget _buildSearchResults() {
    if (_searching) return const Center(key: ValueKey('loading'), child: _PurpleSpinner());
    if (_searchError.isNotEmpty) return Center(key: const ValueKey('err'),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.music_off_rounded, size: 60, color: kDim.withValues(alpha: 0.4)),
          const SizedBox(height: 14),
          Text(_searchError, style: TextStyle(color: kDim, fontSize: 15)),
        ]));
    return CustomScrollView(key: const ValueKey('results'), slivers: [
      SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(24, 12, 24, 10),
          child: Text('${_results.length} results', style: const TextStyle(color: kDim, fontSize: 13, fontWeight: FontWeight.w600)))),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
        sliver: SliverList(delegate: SliverChildBuilderDelegate(
          (_, i) => _TrackRow(track: _results[i], onTap: () => _playTrack(_results[i], _results, i)),
          childCount: _results.length,
        )),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
//  HERO CARD
// ─────────────────────────────────────────────
class _HeroCard extends StatefulWidget {
  final MusicTrack track; final int rank; final VoidCallback onTap;
  const _HeroCard({required this.track, required this.rank, required this.onTap});
  @override State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> with SingleTickerProviderStateMixin {
  late AnimationController _a;
  @override void initState() { super.initState(); _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 160)); }
  @override void dispose()   { _a.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap, onTapDown: (_) => _a.forward(),
        onTapUp: (_) => _a.reverse(), onTapCancel: () => _a.reverse(),
        child: AnimatedBuilder(animation: _a, builder: (_, __) => Transform.scale(
          scale: 1.0 - _a.value * 0.04,
          child: Container(
            width: 150, margin: const EdgeInsets.only(right: 14, bottom: 6, top: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: kCard,
                border: Border.all(color: kBorder),
                boxShadow: [BoxShadow(color: kPurple.withValues(alpha: 0.22), blurRadius: 18, offset: const Offset(0, 6))]),
            child: Stack(children: [
              ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: _trackImg(widget.track, 150, 150)),
              Positioned(top: 8, left: 8, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder)),
                child: Text('#${widget.rank}', style: const TextStyle(color: kNeon, fontSize: 11, fontWeight: FontWeight.w800)),
              )),
              Positioned(bottom: 0, left: 0, right: 0, child: Container(
                padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter,
                      colors: [kCard, kCard.withValues(alpha: 0)]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.track.title, style: const TextStyle(color: kWhite, fontSize: 12, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(widget.track.artist, style: TextStyle(color: kDim, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              )),
            ]),
          ),
        )),
      );
}

// ─────────────────────────────────────────────
//  TRACK ROW
// ─────────────────────────────────────────────
class _TrackRow extends StatefulWidget {
  final MusicTrack track; final VoidCallback onTap;
  const _TrackRow({required this.track, required this.onTap});
  @override State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> with SingleTickerProviderStateMixin {
  late AnimationController _a;
  @override void initState() { super.initState(); _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 120)); }
  @override void dispose()   { _a.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: playerState,
        builder: (_, __) {
          final active = playerState.currentTrack?.id == widget.track.id;
          return GestureDetector(
            onTap: widget.onTap, onTapDown: (_) => _a.forward(),
            onTapUp: (_) => _a.reverse(), onTapCancel: () => _a.reverse(),
            child: AnimatedBuilder(animation: _a, builder: (_, __) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: active ? kViolet.withValues(alpha: 0.13) : Color.lerp(kGlassB, kGlass, _a.value),
                border: Border.all(color: active ? kViolet.withValues(alpha: 0.45) : kBorder.withValues(alpha: _a.value * 2.5)),
              ),
              child: Row(children: [
                Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: _trackImg(widget.track, 52, 52)),
                  if (active) Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(12),
                      child: Container(color: Colors.black.withValues(alpha: 0.5),
                          child: const Icon(Icons.equalizer_rounded, color: kNeon, size: 22)))),
                ]),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.track.title, style: TextStyle(color: active ? kNeon : kWhite,
                      fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text('${widget.track.artist} · ${widget.track.album}',
                      style: TextStyle(color: kDim, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(widget.track.durationStr, style: const TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w500)),
                  if (widget.track.genre != null) ...[
                    const SizedBox(height: 4),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: kGlassB),
                        child: Text(widget.track.genre!, style: const TextStyle(color: kDim, fontSize: 9, fontWeight: FontWeight.w600), maxLines: 1)),
                  ],
                ]),
              ]),
            )),
          );
        },
      );
}

// ─────────────────────────────────────────────
//  MINI PLAYER
// ─────────────────────────────────────────────
class _MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  const _MiniPlayer({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final track = playerState.currentTrack!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [kCardHi, kCard], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: kViolet.withValues(alpha: 0.35), width: 1.2),
          boxShadow: [
            BoxShadow(color: kPurple.withValues(alpha: 0.38), blurRadius: 28, spreadRadius: -4),
            BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 14),
          ],
        ),
        child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Stack(children: [
          if (track.imageUrl.isNotEmpty)
            Positioned.fill(child: Opacity(opacity: 0.07, child: Image.network(track.imageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: _trackImg(track, 46, 46)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(track.title, style: const TextStyle(color: kWhite, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(track.artist, style: TextStyle(color: kDim, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              GestureDetector(onTap: playerState.previous,
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.skip_previous_rounded, color: kDim, size: 24))),
              GestureDetector(onTap: playerState.togglePlay,
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(playerState.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                          color: kNeon, size: 36))),
              GestureDetector(onTap: playerState.next,
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.skip_next_rounded, color: kDim, size: 24))),
            ]),
          ),
        ])),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PLAYER SCREEN
// ─────────────────────────────────────────────
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});
  @override State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with TickerProviderStateMixin {
  late AnimationController _discAnim, _slideAnim, _glowAnim, _artEntryAnim;
  bool _showLyrics = false;

  @override
  void initState() {
    super.initState();
    _discAnim     = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
    _slideAnim    = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
    _glowAnim     = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _artEntryAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    playerState.addListener(_onState);
    Future.delayed(const Duration(milliseconds: 180), () { if (mounted) _artEntryAnim.forward(); });
  }

  void _onState() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    _discAnim.dispose(); _slideAnim.dispose(); _glowAnim.dispose(); _artEntryAnim.dispose();
    playerState.removeListener(_onState);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = playerState.currentTrack;
    if (track == null) return const SizedBox.shrink();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        AnimatedBuilder(animation: _glowAnim, builder: (_, __) => Container(
          decoration: BoxDecoration(gradient: RadialGradient(
            center: const Alignment(0, -0.5), radius: 1.2,
            colors: [kPurple.withValues(alpha: 0.28 + _glowAnim.value * 0.1), kBg],
          )),
        )),
        if (track.imageUrlHd.isNotEmpty)
          Positioned.fill(child: Opacity(opacity: 0.055, child: Image.network(track.imageUrlHd, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()))),

        SafeArea(child: Column(children: [
          _buildTopBar(context),
          Expanded(child: _showLyrics ? _buildLyricsView(track) : _buildPlayerView(track, size)),
        ])),

        if (playerState.loadingAudio)
          Positioned(bottom: 28, left: 0, right: 0, child: Center(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(color: kCardHi, borderRadius: BorderRadius.circular(30),
                border: Border.all(color: kViolet.withValues(alpha: 0.4)),
                boxShadow: [BoxShadow(color: kPurple.withValues(alpha: 0.4), blurRadius: 20)]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(kViolet))),
              SizedBox(width: 10),
              Text('Loading audio…', style: TextStyle(color: kWhite, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ))),
      ]),
    );
  }

  Widget _buildTopBar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          IconButton(
            icon: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(shape: BoxShape.circle, color: kGlass, border: Border.all(color: kBorder)),
                child: const Icon(Icons.keyboard_arrow_down_rounded, size: 22, color: kWhite)),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Column(children: [
            Text('NOW PLAYING', style: TextStyle(fontSize: 10, color: kDim, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const SizedBox(height: 2),
            Text(_showLyrics ? 'Karaoke' : 'Player',
                style: const TextStyle(fontSize: 13, color: kWhite, fontWeight: FontWeight.w600)),
          ]),
          const Spacer(),
          IconButton(
            icon: Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(shape: BoxShape.circle, color: kGlass, border: Border.all(color: kBorder)),
                child: Icon(_showLyrics ? Icons.music_note_rounded : Icons.mic_rounded,
                    size: 20, color: _showLyrics ? kWhite : kPink)),
            onPressed: () => setState(() => _showLyrics = !_showLyrics),
          ),
        ]),
      );

  Widget _buildPlayerView(MusicTrack track, Size size) => AnimatedBuilder(
        animation: _slideAnim,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 50 * (1 - Curves.easeOutQuart.transform(_slideAnim.value))),
          child: Opacity(opacity: _slideAnim.value, child: child),
        ),
        child: SingleChildScrollView(child: Column(children: [
          const SizedBox(height: 16),
          AnimatedBuilder(animation: _artEntryAnim, builder: (_, child) => Transform.scale(
            scale: Curves.elasticOut.transform(_artEntryAnim.value).clamp(0.0, 1.06),
            child: child,
          ), child: AnimatedBuilder(animation: _discAnim, builder: (_, child) => Transform.rotate(
            angle: playerState.isPlaying ? _discAnim.value * 2 * pi : 0,
            child: child,
          ), child: _buildDisc(track, size))),
          const SizedBox(height: 30),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 36), child: Column(children: [
            Text(track.title, style: const TextStyle(color: kWhite, fontSize: 22, fontWeight: FontWeight.w800,
                letterSpacing: -0.5, height: 1.2), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(track.artist, style: TextStyle(color: kDim, fontSize: 15, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: kGlassB, border: Border.all(color: kBorder)),
                child: Text(track.album, style: const TextStyle(color: kViolet, fontSize: 11, fontWeight: FontWeight.w600),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
          ])),
          const SizedBox(height: 28),
          _buildProgress(),
          const SizedBox(height: 20),
          _buildVocalSlider(),
          const SizedBox(height: 20),
          _buildControls(),
          const SizedBox(height: 16),
        ])),
      );

  Widget _buildDisc(MusicTrack track, Size size) {
    final ds = size.width * 0.62;
    return AnimatedBuilder(
      animation: _glowAnim,
      builder: (_, child) => Container(width: ds, height: ds,
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(color: kViolet.withValues(alpha: 0.32 + _glowAnim.value * 0.2), blurRadius: 50 + _glowAnim.value * 28, spreadRadius: 4),
          BoxShadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 22),
        ]), child: child),
      child: Stack(alignment: Alignment.center, children: [
        Container(decoration: const BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [kCardHi, kBg], stops: [0.3, 1.0]))),
        for (int i = 0; i < 5; i++)
          FractionallySizedBox(widthFactor: 0.92 - i * 0.15, heightFactor: 0.92 - i * 0.15,
              child: Container(decoration: BoxDecoration(shape: BoxShape.circle,
                  border: Border.all(color: kViolet.withValues(alpha: 0.05), width: 1)))),
        ClipOval(child: SizedBox(width: ds * 0.7, height: ds * 0.7, child: _trackImg(track, ds * 0.7, ds * 0.7))),
        Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: kBg,
            border: Border.all(color: kViolet.withValues(alpha: 0.65), width: 2),
            boxShadow: [BoxShadow(color: kViolet.withValues(alpha: 0.45), blurRadius: 8)])),
      ]),
    );
  }

  Widget _buildProgress() => ListenableBuilder(
        listenable: playerState,
        builder: (_, __) {
          final pos  = playerState.position;
          final dur  = playerState.totalDuration;
          final prog = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: Column(children: [
            SliderTheme(
              data: SliderThemeData(trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                  activeTrackColor: kNeon, inactiveTrackColor: kGlass,
                  thumbColor: Colors.white, overlayColor: kViolet.withValues(alpha: 0.2)),
              child: Slider(value: prog, onChanged: (v) =>
                  playerState.audio.seek(Duration(milliseconds: (v * dur.inMilliseconds).toInt()))),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_fmt(pos), style: TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w500)),
              Text(_fmt(dur), style: TextStyle(color: kDim, fontSize: 12, fontWeight: FontWeight.w500)),
            ])),
          ]));
        },
      );

  Widget _buildVocalSlider() => ListenableBuilder(
        listenable: playerState,
        builder: (_, __) {
          final v = playerState.vocalVolume;
          final isKaraoke = v < 0.15;
          return Padding(padding: const EdgeInsets.symmetric(horizontal: 28), child: Column(children: [
            Row(children: [
              AnimatedContainer(duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: isKaraoke ? kPink.withValues(alpha: 0.18) : kGlassB,
                  border: Border.all(color: isKaraoke ? kPink.withValues(alpha: 0.6) : kBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(isKaraoke ? Icons.mic_rounded : Icons.volume_up_rounded,
                      color: isKaraoke ? kPink : kDim, size: 13),
                  const SizedBox(width: 5),
                  Text(isKaraoke ? 'KARAOKE MODE' : 'Singer Volume',
                      style: TextStyle(color: isKaraoke ? kPink : kDim, fontSize: 11,
                          fontWeight: FontWeight.w800, letterSpacing: isKaraoke ? 0.8 : 0)),
                ]),
              ),
              const Spacer(),
              Text('${(v * 100).round()}%',
                  style: TextStyle(color: isKaraoke ? kPink : kDim, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderThemeData(trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                  activeTrackColor: isKaraoke ? kPink : kViolet, inactiveTrackColor: kGlass,
                  thumbColor: isKaraoke ? kPink : kWhite,
                  overlayColor: (isKaraoke ? kPink : kViolet).withValues(alpha: 0.2)),
              child: Slider(value: v, onChanged: playerState.setVocalVolume),
            ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('🎤 You sing', style: TextStyle(color: kDim, fontSize: 10)),
              Text('🎵 Listen', style: TextStyle(color: kDim, fontSize: 10)),
            ])),
          ]));
        },
      );

  Widget _buildControls() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _iconBtn(Icons.shuffle_rounded, 22, kDim, () {}),
          _iconBtn(Icons.skip_previous_rounded, 32, kWhite, playerState.previous),
          GestureDetector(onTap: playerState.togglePlay, child: AnimatedBuilder(animation: _glowAnim, builder: (_, __) => Container(
            width: 72, height: 72,
            decoration: BoxDecoration(shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [kViolet, kPink], begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(color: kViolet.withValues(alpha: 0.5 + _glowAnim.value * 0.25),
                    blurRadius: 28 + _glowAnim.value * 14, spreadRadius: 2)]),
            child: Icon(playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 38),
          ))),
          _iconBtn(Icons.skip_next_rounded, 32, kWhite, playerState.next),
          _iconBtn(Icons.repeat_rounded, 22, kDim, () {}),
        ]),
      );

  Widget _iconBtn(IconData icon, double size, Color color, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Padding(padding: const EdgeInsets.all(10), child: Icon(icon, color: color, size: size)));

  Widget _buildLyricsView(MusicTrack track) {
    if (playerState.loadingLyrics) return const Center(child: _PurpleSpinner());
    if (playerState.lyricLines.isEmpty) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.lyrics_outlined, size: 52, color: kDim.withValues(alpha: 0.4)),
      const SizedBox(height: 14),
      Text('No lyrics found', style: TextStyle(color: kDim, fontSize: 15)),
    ]));
    return playerState.hasSyncedLyrics
        ? _KaraokeLyricsView(lines: playerState.lyricLines)
        : _PlainLyricsView(track: track, lines: playerState.lyricLines);
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────
//  KARAOKE LYRICS VIEW
// ─────────────────────────────────────────────
class _KaraokeLyricsView extends StatefulWidget {
  final List<LyricLine> lines;
  const _KaraokeLyricsView({required this.lines});
  @override State<_KaraokeLyricsView> createState() => _KaraokeLyricsViewState();
}

class _KaraokeLyricsViewState extends State<_KaraokeLyricsView> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _keys = {};
  int _activeIndex = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < widget.lines.length; i++) _keys[i] = GlobalKey();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _sync());
  }

  @override
  void dispose() { _ticker?.cancel(); _scroll.dispose(); super.dispose(); }

  void _sync() {
    if (!mounted) return;
    final pos = playerState.position;
    int idx = 0;
    for (int i = 0; i < widget.lines.length; i++) {
      if (pos >= widget.lines[i].timestamp) idx = i;
    }
    if (idx != _activeIndex) {
      setState(() => _activeIndex = idx);
      final ctx = _keys[idx]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOutCubic, alignment: 0.3);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        // Karaoke banner
        ListenableBuilder(listenable: playerState, builder: (_, __) {
          final isKaraoke = playerState.vocalVolume < 0.15;
          return AnimatedContainer(duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.fromLTRB(28, 8, 28, 0),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isKaraoke ? kPink.withValues(alpha: 0.15) : kGlassB,
              border: Border.all(color: isKaraoke ? kPink.withValues(alpha: 0.5) : kBorder),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.mic_rounded, color: isKaraoke ? kPink : kDim, size: 14),
              const SizedBox(width: 6),
              Text(isKaraoke ? '🎤 Karaoke Mode — Sing Along!' : 'Lower singer volume to go karaoke',
                  style: TextStyle(color: isKaraoke ? kPink : kDim, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          );
        }),
        const SizedBox(height: 8),
        Expanded(child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(28, 16, 28, 100),
          itemCount: widget.lines.length,
          itemBuilder: (_, i) {
            final next = i + 1 < widget.lines.length ? widget.lines[i + 1] : null;
            return _KaraokeLineWidget(
              key: _keys[i],
              line: widget.lines[i], nextLine: next,
              isActive: i == _activeIndex, isPast: i < _activeIndex,
              positionStream: playerState.audio.player.positionStream,
              onTap: () {
                playerState.audio.seek(widget.lines[i].timestamp);
                setState(() => _activeIndex = i);
              },
            );
          },
        )),
      ]);
}

// ─────────────────────────────────────────────
//  KARAOKE LINE WIDGET  (gray → white sweep)
// ─────────────────────────────────────────────
class _KaraokeLineWidget extends StatefulWidget {
  final LyricLine line, nextLine_unused = const LyricLine(timestamp: Duration.zero, text: '');
  final LyricLine? nextLine;
  final bool isActive, isPast;
  final Stream<Duration> positionStream;
  final VoidCallback onTap;

  const _KaraokeLineWidget({
    super.key,
    required this.line, required this.nextLine,
    required this.isActive, required this.isPast,
    required this.positionStream, required this.onTap,
  });

  @override State<_KaraokeLineWidget> createState() => _KaraokeLineWidgetState();
}

class _KaraokeLineWidgetState extends State<_KaraokeLineWidget> with SingleTickerProviderStateMixin {
  late AnimationController _scale;
  StreamSubscription<Duration>? _sub;
  double _fill = 0.0;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    if (widget.isActive) { _scale.forward(); _startFill(); }
    if (widget.isPast) _fill = 1.0;
  }

  void _startFill() {
    _sub?.cancel();
    _sub = widget.positionStream.listen((pos) {
      if (!mounted || !widget.isActive) return;
      final start = widget.line.timestamp.inMilliseconds;
      final end   = widget.nextLine?.timestamp.inMilliseconds ?? (start + 4000);
      final prog  = ((pos.inMilliseconds - start) / (end - start)).clamp(0.0, 1.0);
      if ((prog - _fill).abs() > 0.004) setState(() => _fill = prog);
    });
  }

  @override
  void didUpdateWidget(_KaraokeLineWidget old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _scale.forward(from: 0); _fill = 0; _startFill();
    } else if (!widget.isActive && old.isActive) {
      _scale.reverse(); _sub?.cancel();
      setState(() => _fill = widget.isPast ? 1.0 : 0.0);
    } else if (widget.isPast && !old.isPast) {
      setState(() => _fill = 1.0);
    }
  }

  @override
  void dispose() { _scale.dispose(); _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final fs = widget.isActive ? 26.0 : 22.0;
    final fw = widget.isActive ? FontWeight.w800 : FontWeight.w700;
    final op = widget.isActive ? 1.0 : (widget.isPast ? 0.55 : 0.3);

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, __) => Transform.scale(
          scale: 1.0 + _scale.value * 0.04, alignment: Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 10),
              child: AnimatedOpacity(duration: const Duration(milliseconds: 300), opacity: op,
                child: widget.isActive ? _karaokeText(fs, fw) : Text(widget.line.text,
                    style: TextStyle(
                      color: widget.isPast ? kNeon.withValues(alpha: 0.7) : kDim,
                      fontSize: fs, fontWeight: fw, height: 1.25, letterSpacing: -0.2,
                    )),
              )),
        ),
      ),
    );
  }

  Widget _karaokeText(double fs, FontWeight fw) => Stack(children: [
        // Unsung — gray
        Text(widget.line.text, style: TextStyle(
            color: kDim.withValues(alpha: 0.4), fontSize: fs, fontWeight: fw, height: 1.25, letterSpacing: -0.5)),
        // Sung — white sweep left→right
        ClipRect(clipper: _FillClipper(_fill), child: ShaderMask(
          shaderCallback: (b) => const LinearGradient(colors: [kWhite, kNeon], stops: [0.75, 1.0]).createShader(b),
          child: Text(widget.line.text, style: TextStyle(
              color: Colors.white, fontSize: fs, fontWeight: fw, height: 1.25, letterSpacing: -0.5)),
        )),
      ]);
}

// ─────────────────────────────────────────────
//  FILL CLIPPER
// ─────────────────────────────────────────────
class _FillClipper extends CustomClipper<Rect> {
  final double p;
  const _FillClipper(this.p);
  @override Rect getClip(Size s) => Rect.fromLTWH(0, 0, s.width * p, s.height);
  @override bool shouldReclip(_FillClipper o) => o.p != p;
}

// ─────────────────────────────────────────────
//  PLAIN LYRICS VIEW
// ─────────────────────────────────────────────
class _PlainLyricsView extends StatelessWidget {
  final MusicTrack track; final List<LyricLine> lines;
  const _PlainLyricsView({required this.track, required this.lines});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 12, 28, 100),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: _trackImg(track, 52, 52)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(track.title, style: const TextStyle(color: kWhite, fontWeight: FontWeight.w700, fontSize: 15),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(track.artist, style: TextStyle(color: kDim, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            ])),
          ]),
          const SizedBox(height: 32),
          ...lines.map((l) => Padding(padding: const EdgeInsets.only(bottom: 18),
              child: Text(l.text, style: const TextStyle(color: kWhite, fontSize: 22, height: 1.35, fontWeight: FontWeight.w700)))),
        ]),
      );
}

// ─────────────────────────────────────────────
//  SHARED HELPERS
// ─────────────────────────────────────────────
Widget _trackImg(MusicTrack track, double w, double h) {
  if (track.imageUrl.isNotEmpty) {
    return Image.network(track.imageUrl, width: w, height: h, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _discFallback(w, h));
  }
  return _discFallback(w, h);
}

Widget _discFallback(double w, double h) => Image.asset(kDiscAsset, width: w, height: h, fit: BoxFit.cover,
    errorBuilder: (_, __, ___) => Container(width: w, height: h, color: kCardHi,
        child: const Icon(Icons.music_note_rounded, color: kDim, size: 30)));

class _GlowOrb extends StatelessWidget {
  final double radius; final Color color; final AnimationController anim;
  const _GlowOrb({required this.radius, required this.color, required this.anim});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: anim, builder: (_, __) => Container(
        width: radius * 2 + anim.value * 30, height: radius * 2 + anim.value * 30,
        decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, Colors.transparent], stops: const [0.2, 1.0])),
      ));
}

class _PurpleSpinner extends StatelessWidget {
  const _PurpleSpinner();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 32, height: 32,
      child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(kViolet)));
}