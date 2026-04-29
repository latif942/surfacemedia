import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

// ─────────────────────────────────────────────
//  ENTRY POINT
// ─────────────────────────────────────────────
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark,
  ));
  runApp(const SurfacePlayerApp());
}

// ─────────────────────────────────────────────
//  THEME CONSTANTS
// ─────────────────────────────────────────────
const kPurple1 = Color(0xFF0D0014);
const kPurple2 = Color(0xFF1A0033);
const kPurple3 = Color(0xFF3B0066);
const kPurple4 = Color(0xFF6A00B8);
const kViolet  = Color(0xFF9B30FF);
const kNeon    = Color(0xFFBF7FFF);
const kWhite   = Color(0xFFF2E8FF);
const kGlass   = Color(0x22FFFFFF);
const kGlassB  = Color(0x11FFFFFF);

// ─────────────────────────────────────────────
//  SPOTIFY SERVICE
// ─────────────────────────────────────────────
class SpotifyService {
  static const _clientId     = '1953647748c2485ebc9ecb6460d69b21';
  static const _clientSecret = '8852bb1f3d3c4813a4f7929867ace7fe';
  String? _accessToken;
  DateTime? _tokenExpiry;

  Future<void> _ensureToken() async {
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return;
    }
    final creds = base64.encode(utf8.encode('$_clientId:$_clientSecret'));
    final res = await http.post(
      Uri.parse('https://accounts.spotify.com/api/token'),
      headers: {
        'Authorization': 'Basic $creds',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'grant_type': 'client_credentials'},
    );
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    _accessToken = data['access_token'] as String;
    _tokenExpiry = DateTime.now()
        .add(Duration(seconds: (data['expires_in'] as int) - 60));
  }

  Future<List<SpotifyTrack>> search(String query) async {
    await _ensureToken();
    final uri = Uri.parse('https://api.spotify.com/v1/search').replace(
      queryParameters: {'q': query, 'type': 'track', 'limit': '20'},
    );
    final res = await http.get(uri,
        headers: {'Authorization': 'Bearer $_accessToken'});
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final items = (data['tracks'] as Map<String, dynamic>)['items'] as List<dynamic>;
    return items
        .map((t) => SpotifyTrack.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<List<SpotifyTrack>> getFeatured() async {
    await _ensureToken();
    final uri = Uri.parse('https://api.spotify.com/v1/browse/new-releases')
        .replace(queryParameters: {'limit': '10'});
    final res = await http.get(uri,
        headers: {'Authorization': 'Bearer $_accessToken'});
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final albums = (data['albums'] as Map<String, dynamic>)['items'] as List<dynamic>;
    final List<SpotifyTrack> tracks = [];
    for (final album in albums.take(8)) {
      final albumMap = album as Map<String, dynamic>;
      final albumId = albumMap['id'] as String;
      final tRes = await http.get(
        Uri.parse('https://api.spotify.com/v1/albums/$albumId/tracks?limit=1'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );
      final tData = jsonDecode(tRes.body) as Map<String, dynamic>;
      final tItems = tData['items'] as List<dynamic>;
      if (tItems.isNotEmpty) {
        final t = tItems[0] as Map<String, dynamic>;
        final images = albumMap['images'] as List<dynamic>;
        tracks.add(SpotifyTrack(
          id: t['id'] as String,
          title: t['name'] as String,
          artist: (albumMap['artists'] as List<dynamic>)
              .map((a) => (a as Map<String, dynamic>)['name'] as String)
              .join(', '),
          album: albumMap['name'] as String,
          imageUrl: images.isNotEmpty
              ? (images[0] as Map<String, dynamic>)['url'] as String
              : '',
          durationMs: (t['duration_ms'] as int?) ?? 0,
          previewUrl: t['preview_url'] as String?,
        ));
      }
    }
    return tracks;
  }

  Future<String?> getLyrics(String artist, String title) async {
    try {
      final uri = Uri.parse(
          'https://api.lyrics.ovh/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['lyrics'] as String?;
      }
    } catch (_) {}
    return null;
  }
}

// ─────────────────────────────────────────────
//  SPOTIFY TRACK MODEL
// ─────────────────────────────────────────────
class SpotifyTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String imageUrl;
  final int durationMs;
  final String? previewUrl;

  const SpotifyTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.imageUrl,
    required this.durationMs,
    this.previewUrl,
  });

  factory SpotifyTrack.fromJson(Map<String, dynamic> j) {
    final albumData = j['album'] as Map<String, dynamic>;
    final images = albumData['images'] as List<dynamic>;
    return SpotifyTrack(
      id: j['id'] as String,
      title: j['name'] as String,
      artist: (j['artists'] as List<dynamic>)
          .map((a) => (a as Map<String, dynamic>)['name'] as String)
          .join(', '),
      album: albumData['name'] as String,
      imageUrl: images.isNotEmpty
          ? (images[0] as Map<String, dynamic>)['url'] as String
          : '',
      durationMs: (j['duration_ms'] as int?) ?? 0,
      previewUrl: j['preview_url'] as String?,
    );
  }

  String get duration {
    final total = durationMs ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
//  YOUTUBE SERVICE
// ─────────────────────────────────────────────
class YouTubeService {
  // Get a free key at console.cloud.google.com → YouTube Data API v3
  static const _ytKey = 'YOUR_YOUTUBE_API_KEY_HERE';

  Future<String?> findVideoId(SpotifyTrack track) async {
    final queries = [
      '"${track.title}" "${track.artist}" official audio',
      '"${track.title}" "${track.artist}" official video',
      '${track.artist} ${track.title} official audio',
    ];
    for (final q in queries) {
      final id = await _searchYT(q, track);
      if (id != null) return id;
    }
    return null;
  }

  Future<String?> _searchYT(String query, SpotifyTrack track) async {
    try {
      final uri = Uri.parse('https://www.googleapis.com/youtube/v3/search')
          .replace(queryParameters: {
        'part': 'snippet',
        'q': query,
        'type': 'video',
        'maxResults': '5',
        'videoCategoryId': '10',
        'key': _ytKey,
      });
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = data['items'] as List<dynamic>;
      if (items.isEmpty) return null;

      for (var i = 0; i < items.length; i++) {
        final item = items[i] as Map<String, dynamic>;
        final snippet = item['snippet'] as Map<String, dynamic>;
        final videoTitle = (snippet['title'] as String).toLowerCase();
        final channelTitle = (snippet['channelTitle'] as String).toLowerCase();
        final trackTitle = track.title.toLowerCase();
        final artistName = track.artist.toLowerCase().split(',').first.trim();

        final isCover = videoTitle.contains('cover') ||
            videoTitle.contains('tribute') ||
            videoTitle.contains('karaoke') ||
            videoTitle.contains('reaction') ||
            (videoTitle.contains('remix') && !trackTitle.contains('remix'));

        final isOfficial = channelTitle.contains('vevo') ||
            channelTitle.contains(artistName) ||
            videoTitle.contains('official');

        if (!isCover && (isOfficial || i == 0)) {
          return (item['id'] as Map<String, dynamic>)['videoId'] as String;
        }
      }
      return ((items[0] as Map<String, dynamic>)['id']
          as Map<String, dynamic>)['videoId'] as String;
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────
//  APP ROOT
// ─────────────────────────────────────────────
class SurfacePlayerApp extends StatelessWidget {
  const SurfacePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SurfacePlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kPurple1,
        colorScheme: const ColorScheme.dark(
          primary: kViolet,
          secondary: kNeon,
          surface: kPurple2,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// ─────────────────────────────────────────────
//  PLAYER STATE
// ─────────────────────────────────────────────
class PlayerState extends ChangeNotifier {
  SpotifyTrack? currentTrack;
  String? currentVideoId;
  bool isPlaying = false;
  List<SpotifyTrack> queue = [];
  int queueIndex = -1;
  String? lyrics;
  bool loadingLyrics = false;
  YoutubePlayerController? ytController;

  final _spotify = SpotifyService();
  final _youtube = YouTubeService();

  void setTrack(SpotifyTrack track, List<SpotifyTrack> list, int idx) {
    currentTrack = track;
    queue = list;
    queueIndex = idx;
    isPlaying = false;
    lyrics = null;
    currentVideoId = null;
    notifyListeners();
    _loadVideo(track);
    _fetchLyrics(track);
  }

  Future<void> _loadVideo(SpotifyTrack track) async {
    final vid = await _youtube.findVideoId(track);
    currentVideoId = vid;
    notifyListeners();
  }

  Future<void> _fetchLyrics(SpotifyTrack track) async {
    loadingLyrics = true;
    notifyListeners();
    lyrics = await _spotify.getLyrics(
      track.artist.split(',').first.trim(),
      track.title,
    );
    loadingLyrics = false;
    notifyListeners();
  }

  void next() {
    if (queueIndex < queue.length - 1) {
      setTrack(queue[queueIndex + 1], queue, queueIndex + 1);
    }
  }

  void previous() {
    if (queueIndex > 0) {
      setTrack(queue[queueIndex - 1], queue, queueIndex - 1);
    }
  }

  void togglePlay() {
    isPlaying = !isPlaying;
    if (isPlaying) {
      ytController?.play();
    } else {
      ytController?.pause();
    }
    notifyListeners();
  }

  // Expose notifyListeners publicly for onReady callback
  void notifyReady() {
    isPlaying = true;
    notifyListeners();
  }
}

// Singleton
final playerState = PlayerState();

// ─────────────────────────────────────────────
//  HOME SCREEN
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _spotify = SpotifyService();
  List<SpotifyTrack> _results = [];
  List<SpotifyTrack> _featured = [];
  bool _searching = false;
  bool _loadingFeatured = true;
  bool _searchMode = false;
  late AnimationController _bgAnim;
  late AnimationController _pulseAnim;

  @override
  void initState() {
    super.initState();
    _bgAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 8))
      ..repeat(reverse: true);
    _pulseAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _loadFeatured();
  }

  @override
  void dispose() {
    _bgAnim.dispose();
    _pulseAnim.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFeatured() async {
    try {
      final f = await _spotify.getFeatured();
      if (mounted) {
        setState(() {
          _featured = f;
          _loadingFeatured = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFeatured = false);
    }
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _searching = true;
      _searchMode = true;
    });
    try {
      final r = await _spotify.search(q.trim());
      if (mounted) setState(() { _results = r; _searching = false; });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPurple1,
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _bgAnim,
            builder: (_, child) => Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    kPurple1,
                    Color.lerp(kPurple2, kPurple3, _bgAnim.value)!,
                    kPurple1,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -60,
            right: -60,
            child: _Orb(
              size: 220,
              color: kPurple4.withValues(alpha: 0.25),
              anim: _bgAnim,
            ),
          ),
          Positioned(
            bottom: 100,
            left: -80,
            child: _Orb(
              size: 280,
              color: kViolet.withValues(alpha: 0.12),
              anim: _pulseAnim,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildSearchBar(),
                Expanded(
                  child: _searchMode ? _buildSearchResults() : _buildHome(),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: playerState,
            builder: (_, child) => playerState.currentTrack != null
                ? Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: _MiniPlayer(),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        child: Row(
          children: [
            ShaderMask(
              shaderCallback: (b) =>
                  const LinearGradient(colors: [kViolet, kNeon]).createShader(b),
              child: const Text(
                'SurfacePlayer',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const Spacer(),
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color.lerp(kViolet, kNeon, _pulseAnim.value),
                  boxShadow: [
                    BoxShadow(
                      color: kViolet.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildSearchBar() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: kGlass,
            border: Border.all(color: kViolet.withValues(alpha: 0.3), width: 1),
            boxShadow: [
              BoxShadow(color: kViolet.withValues(alpha: 0.1), blurRadius: 20),
            ],
          ),
          child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: kWhite),
            decoration: InputDecoration(
              hintText: 'Search songs, artists…',
              hintStyle: TextStyle(color: kWhite.withValues(alpha: 0.4)),
              prefixIcon: const Icon(Icons.search_rounded, color: kViolet),
              suffixIcon: _searchMode
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: kWhite.withValues(alpha: 0.5),
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchMode = false;
                          _results = [];
                        });
                      },
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onSubmitted: _search,
          ),
        ),
      );

  Widget _buildHome() {
    if (_loadingFeatured) return const Center(child: _PurpleSpinner());
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle('New Releases'),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _featured.length,
              separatorBuilder: (_, i) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _FeaturedCard(
                track: _featured[i],
                onTap: () => _playTrack(_featured[i], _featured, i),
              ),
            ),
          ),
          const SizedBox(height: 28),
          const _SectionTitle('Trending'),
          const SizedBox(height: 12),
          ..._featured.map((t) => _TrackTile(
                track: t,
                onTap: () => _playTrack(t, _featured, _featured.indexOf(t)),
              )),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searching) return const Center(child: _PurpleSpinner());
    if (_results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded,
                size: 56, color: kViolet.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text('No results',
                style: TextStyle(
                    color: kWhite.withValues(alpha: 0.4), fontSize: 16)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: _results.length,
      itemBuilder: (_, i) => _TrackTile(
        track: _results[i],
        onTap: () => _playTrack(_results[i], _results, i),
      ),
    );
  }

  void _playTrack(SpotifyTrack track, List<SpotifyTrack> list, int idx) {
    playerState.setTrack(track, list, idx);
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, a, s) => const PlayerScreen(),
        transitionsBuilder: (_, a, s, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  PLAYER SCREEN
// ─────────────────────────────────────────────
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with TickerProviderStateMixin {
  late AnimationController _discAnim;
  late AnimationController _slideAnim;
  late AnimationController _glowAnim;
  YoutubePlayerController? _ytCtrl;
  bool _showLyrics = false;
  String? _loadedVideoId;

  @override
  void initState() {
    super.initState();
    _discAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
    _slideAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _glowAnim = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);

    playerState.addListener(_onStateChange);
    if (playerState.currentVideoId != null) {
      _initYT(playerState.currentVideoId!);
    }
  }

  void _onStateChange() {
    if (!mounted) return;
    final vid = playerState.currentVideoId;
    if (vid != null && vid != _loadedVideoId) {
      _initYT(vid);
    }
    setState(() {});
  }

  void _initYT(String videoId) {
    _loadedVideoId = videoId;
    _ytCtrl?.dispose();
    _ytCtrl = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        disableDragSeek: false,
        loop: false,
        enableCaption: false,
        hideControls: true,
      ),
    );
    playerState.ytController = _ytCtrl;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _discAnim.dispose();
    _slideAnim.dispose();
    _glowAnim.dispose();
    _ytCtrl?.dispose();
    playerState.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final track = playerState.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [kPurple2, kPurple1, kPurple1],
              ),
            ),
          ),
          if (track.imageUrl.isNotEmpty)
            Positioned.fill(
              child: Opacity(
                opacity: 0.07,
                child: Image.network(
                  track.imageUrl,
                  fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, child) => Positioned(
              top: 100,
              left: MediaQuery.of(context).size.width / 2 - 120,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kViolet.withValues(
                          alpha: 0.15 + _glowAnim.value * 0.15),
                      blurRadius: 80 + _glowAnim.value * 40,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: _showLyrics
                      ? _buildLyricsView(track)
                      : _buildPlayerView(track),
                ),
              ],
            ),
          ),
          if (_ytCtrl != null)
            Positioned(
              bottom: -300,
              left: 0,
              child: SizedBox(
                width: 1,
                height: 1,
                child: YoutubePlayer(
                  controller: _ytCtrl!,
                  onReady: () => playerState.notifyReady(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 32, color: kWhite),
              onPressed: () => Navigator.pop(context),
            ),
            const Spacer(),
            ShaderMask(
              shaderCallback: (b) =>
                  const LinearGradient(colors: [kViolet, kNeon])
                      .createShader(b),
              child: const Text(
                'Now Playing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              icon: Icon(
                _showLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
                color: kWhite,
              ),
              onPressed: () =>
                  setState(() => _showLyrics = !_showLyrics),
            ),
          ],
        ),
      );

  Widget _buildPlayerView(SpotifyTrack track) {
    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 60 * (1 - _slideAnim.value)),
        child: Opacity(opacity: _slideAnim.value, child: child),
      ),
      child: Column(
        children: [
          const SizedBox(height: 24),
          AnimatedBuilder(
            animation: _discAnim,
            builder: (_, child) => Transform.rotate(
              angle: playerState.isPlaying ? _discAnim.value * 2 * pi : 0,
              child: _buildDisc(track),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Text(
                  track.title,
                  style: const TextStyle(
                    color: kWhite,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  track.artist,
                  style: TextStyle(
                      color: kWhite.withValues(alpha: 0.55),
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  track.album,
                  style: TextStyle(
                      color: kViolet.withValues(alpha: 0.7), fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _buildProgress(),
          const SizedBox(height: 24),
          _buildControls(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDisc(SpotifyTrack track) => Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: kViolet.withValues(alpha: 0.4),
                blurRadius: 40,
                spreadRadius: 8),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 20),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 220,
              height: 220,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0xFF1A0033), Color(0xFF0D0014)],
                  stops: [0.4, 1.0],
                ),
              ),
            ),
            ClipOval(
              child: track.imageUrl.isNotEmpty
                  ? Image.network(
                      track.imageUrl,
                      width: 160,
                      height: 160,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 160,
                        height: 160,
                        color: kPurple3,
                        child: const Icon(Icons.music_note_rounded,
                            size: 48, color: kViolet),
                      ),
                    )
                  : Container(
                      width: 160,
                      height: 160,
                      color: kPurple3,
                      child: const Icon(Icons.music_note_rounded,
                          size: 48, color: kViolet),
                    ),
            ),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPurple1,
                border: Border.all(
                    color: kViolet.withValues(alpha: 0.5), width: 2),
              ),
            ),
          ],
        ),
      );

  Widget _buildProgress() {
    final ctrl = _ytCtrl;
    if (ctrl == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                  color: kGlass, borderRadius: BorderRadius.circular(2)),
              child: playerState.currentVideoId == null
                  ? const LinearProgressIndicator(
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation(kViolet),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('0:00',
                    style: TextStyle(
                        color: kWhite.withValues(alpha: 0.4), fontSize: 12)),
                Text(playerState.currentTrack?.duration ?? '--:--',
                    style: TextStyle(
                        color: kWhite.withValues(alpha: 0.4), fontSize: 12)),
              ],
            ),
          ],
        ),
      );
    }

    // ValueListenableBuilder works with YoutubePlayerController
    return ValueListenableBuilder<YoutubePlayerValue>(
      valueListenable: ctrl,
      builder: (context, value, child) {
        final pos = value.position;
        final dur = value.metaData.duration;
        final progress = dur.inMilliseconds > 0
            ? pos.inMilliseconds / dur.inMilliseconds
            : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                  activeTrackColor: kViolet,
                  inactiveTrackColor: kGlass,
                  thumbColor: kNeon,
                  overlayColor: kViolet.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (v) {
                    final seekTo = Duration(
                        milliseconds: (v * dur.inMilliseconds).toInt());
                    ctrl.seekTo(seekTo);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_fmtDuration(pos),
                        style: TextStyle(
                            color: kWhite.withValues(alpha: 0.4),
                            fontSize: 12)),
                    Text(_fmtDuration(dur),
                        style: TextStyle(
                            color: kWhite.withValues(alpha: 0.4),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CtrlBtn(
              icon: Icons.skip_previous_rounded,
              size: 32,
              onTap: () => playerState.previous()),
          const SizedBox(width: 20),
          GestureDetector(
            onTap: () => playerState.togglePlay(),
            child: AnimatedBuilder(
              animation: _glowAnim,
              builder: (_, child) => Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [kViolet, kNeon],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: kViolet.withValues(
                          alpha: 0.4 + _glowAnim.value * 0.3),
                      blurRadius: 24 + _glowAnim.value * 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  playerState.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          _CtrlBtn(
              icon: Icons.skip_next_rounded,
              size: 32,
              onTap: () => playerState.next()),
        ],
      );

  Widget _buildLyricsView(SpotifyTrack track) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: track.imageUrl.isNotEmpty
                    ? Image.network(
                        track.imageUrl,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(width: 56, height: 56, color: kPurple3),
                      )
                    : Container(width: 56, height: 56, color: kPurple3),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        style: const TextStyle(
                            color: kWhite,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    Text(track.artist,
                        style: TextStyle(
                            color: kWhite.withValues(alpha: 0.5),
                            fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          if (playerState.loadingLyrics)
            const Center(child: _PurpleSpinner())
          else if (playerState.lyrics == null || playerState.lyrics!.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.lyrics_outlined,
                      size: 48, color: kViolet.withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text('Lyrics not available',
                      style: TextStyle(
                          color: kWhite.withValues(alpha: 0.35), fontSize: 15)),
                ],
              ),
            )
          else
            Text(
              playerState.lyrics!,
              style: const TextStyle(
                  color: kWhite, fontSize: 16, height: 1.9, letterSpacing: 0.2),
            ),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────
//  MINI PLAYER
// ─────────────────────────────────────────────
class _MiniPlayer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final track = playerState.currentTrack!;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, a, s) => const PlayerScreen(),
          transitionsBuilder: (_, a, s, child) => SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            colors: [kPurple3, kPurple2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
                color: kViolet.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 2),
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.5), blurRadius: 10),
          ],
          border: Border.all(color: kViolet.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: track.imageUrl.isNotEmpty
                  ? Image.network(
                      track.imageUrl,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: kPurple3,
                        child: const Icon(Icons.music_note_rounded,
                            color: kViolet),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      color: kPurple3,
                      child: const Icon(Icons.music_note_rounded,
                          color: kViolet),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(track.title,
                      style: const TextStyle(
                          color: kWhite,
                          fontWeight: FontWeight.w600,
                          fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(track.artist,
                      style: TextStyle(
                          color: kWhite.withValues(alpha: 0.5), fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                playerState.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: kNeon,
              ),
              onPressed: () => playerState.togglePlay(),
            ),
            IconButton(
              icon: Icon(Icons.skip_next_rounded,
                  color: kWhite.withValues(alpha: 0.7)),
              onPressed: () => playerState.next(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  REUSABLE WIDGETS
// ─────────────────────────────────────────────
class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  final AnimationController anim;

  const _Orb({required this.size, required this.color, required this.anim});

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: anim,
        builder: (_, child) => Container(
          width: size + anim.value * 20,
          height: size + anim.value * 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, Colors.transparent],
              stops: const [0.3, 1.0],
            ),
          ),
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => ShaderMask(
        shaderCallback: (b) =>
            const LinearGradient(colors: [kWhite, kNeon]).createShader(b),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      );
}

class _FeaturedCard extends StatefulWidget {
  final SpotifyTrack track;
  final VoidCallback onTap;

  const _FeaturedCard({required this.track, required this.onTap});

  @override
  State<_FeaturedCard> createState() => _FeaturedCardState();
}

class _FeaturedCardState extends State<_FeaturedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _hoverAnim;

  @override
  void initState() {
    super.initState();
    _hoverAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
  }

  @override
  void dispose() {
    _hoverAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _hoverAnim.forward(),
        onTapUp: (_) => _hoverAnim.reverse(),
        onTapCancel: () => _hoverAnim.reverse(),
        child: AnimatedBuilder(
          animation: _hoverAnim,
          builder: (_, child) => Transform.scale(
            scale: 1.0 - _hoverAnim.value * 0.03,
            child: Container(
              width: 145,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                color: kGlass,
                border: Border.all(
                    color: kViolet.withValues(alpha: 0.2), width: 1),
                boxShadow: [
                  BoxShadow(
                      color: kPurple4.withValues(alpha: 0.2),
                      blurRadius: 16),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(18)),
                    child: widget.track.imageUrl.isNotEmpty
                        ? Image.network(
                            widget.track.imageUrl,
                            width: 145,
                            height: 130,
                            fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                              width: 145,
                              height: 130,
                              color: kPurple3,
                              child: const Icon(Icons.music_note_rounded,
                                  size: 40, color: kViolet),
                            ),
                          )
                        : Container(
                            width: 145,
                            height: 130,
                            color: kPurple3,
                            child: const Icon(Icons.music_note_rounded,
                                size: 40, color: kViolet),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.track.title,
                            style: const TextStyle(
                                color: kWhite,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(widget.track.artist,
                            style: TextStyle(
                                color: kWhite.withValues(alpha: 0.45),
                                fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TrackTile extends StatefulWidget {
  final SpotifyTrack track;
  final VoidCallback onTap;

  const _TrackTile({required this.track, required this.onTap});

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _anim.forward(),
        onTapUp: (_) => _anim.reverse(),
        onTapCancel: () => _anim.reverse(),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, child) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Color.lerp(kGlassB, kGlass, _anim.value),
              border: Border.all(
                  color: kViolet.withValues(alpha: 0.1 + _anim.value * 0.15),
                  width: 1),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.track.imageUrl.isNotEmpty
                      ? Image.network(
                          widget.track.imageUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                            width: 50,
                            height: 50,
                            color: kPurple3,
                            child: const Icon(Icons.music_note_rounded,
                                color: kViolet),
                          ),
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: kPurple3,
                          child: const Icon(Icons.music_note_rounded,
                              color: kViolet),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.track.title,
                          style: const TextStyle(
                              color: kWhite,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(widget.track.artist,
                          style: TextStyle(
                              color: kWhite.withValues(alpha: 0.45),
                              fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.track.duration,
                    style: TextStyle(
                        color: kWhite.withValues(alpha: 0.3), fontSize: 12)),
              ],
            ),
          ),
        ),
      );
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _CtrlBtn({required this.icon, required this.size, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kGlass,
            border: Border.all(
                color: kViolet.withValues(alpha: 0.2), width: 1),
          ),
          child: Icon(icon, color: kWhite, size: size),
        ),
      );
}

class _PurpleSpinner extends StatelessWidget {
  const _PurpleSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 32,
        height: 32,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation(kViolet),
        ),
      );
}