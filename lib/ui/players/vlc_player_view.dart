// lib/ui/players/vlc_player_view.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class VLCPlayerView extends StatefulWidget {
  final String videoPath;
  const VLCPlayerView({super.key, required this.videoPath});

  @override
  State<VLCPlayerView> createState() => _VLCPlayerViewState();
}

class _VLCPlayerViewState extends State<VLCPlayerView> {
  VlcPlayerController? _vlcController;
  Timer? _positionTimer;
  Timer? _hideTimer;

  bool _loading = true;
  bool _showControls = true;
  bool _isPlaying = false;
  bool _isSeeking = false;
  bool _isFullscreen = false;

  double _currentPosition = 0.0; // ms
  double _duration = 1.0; // ms

  // Use video aspect if available; default to 16/9
  double _videoAspect = 16.0 / 9.0;
  double _playbackSpeed = 1.0;

  Map<int, String> _audioTracks = {};
  Map<int, String> _subtitleTracks = {};
  int? _selectedAudioId;
  int? _selectedSubtitleId; // -1 => none

  static const int _skipMs = 10000;
  final List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _initController();
  }

  String _normalize(String p) {
    if (p.startsWith('content://') || p.startsWith('http://') || p.startsWith('https://')) return p;
    return p.startsWith('/') ? p : '/$p';
  }

  Future<void> _initController() async {
    final raw = widget.videoPath;
    final path = _normalize(raw);
    debugPrint('VLC init: raw="$raw" normalized="$path"');

    try {
      if (path.startsWith('content://')) {
        _vlcController = VlcPlayerController.network(path, hwAcc: HwAcc.full, autoPlay: true, options: VlcPlayerOptions());
      } else {
        final file = File(path);
        final exists = await file.exists().catchError((_) => false);
        debugPrint('VLC init: fileExists=$exists for "$path"');
        if (exists) {
          _vlcController = VlcPlayerController.file(file, hwAcc: HwAcc.full, autoPlay: true, options: VlcPlayerOptions());
        } else {
          // fallback: try network
          _vlcController = VlcPlayerController.network(path, hwAcc: HwAcc.full, autoPlay: true, options: VlcPlayerOptions());
        }
      }

      // give controller a short time to init
      await Future.delayed(const Duration(milliseconds: 400));

      // try to read aspect ratio from VLC (if available)
      await _tryReadAspectRatio();

      // start position polling (guarded)
      _positionTimer = Timer.periodic(const Duration(milliseconds: 400), (_) => _updatePosition());

      // refresh tracks a little later
      Future.delayed(const Duration(milliseconds: 700), _refreshTrackLists);

      // auto-hide
      _startHideTimer();

      setState(() => _loading = false);
    } catch (e, st) {
      debugPrint('VLC init error: $e\n$st');
      setState(() => _loading = false);
    }
  }

  Future<void> _tryReadAspectRatio() async {
    final c = _vlcController;
    if (c == null) return;
    try {
      final aspStr = await c.getVideoAspectRatio(); // e.g. "16:9"
      debugPrint('VLC aspect string: $aspStr');
      if (aspStr != null && aspStr.isNotEmpty) {
        final parsed = _parseAspectString(aspStr);
        if (parsed != null) {
          if (mounted) setState(() => _videoAspect = parsed);
          return;
        }
      }

      // fallback: if we can't read aspect, give portrait videos a taller default so they don't appear tiny
      final mq = MediaQuery.maybeOf(context);
      if (mq != null) {
        final deviceAsp = mq.size.aspectRatio;
        if (deviceAsp < 0.8) {
          if (mounted) setState(() => _videoAspect = 2.0 / 3.0); // more vertical default
        } else {
          if (mounted) setState(() => _videoAspect = 16.0 / 9.0);
        }
      }
    } catch (e) {
      debugPrint('tryReadAspectRatio failed: $e');
    }
  }

  double? _parseAspectString(String s) {
    try {
      final cleaned = s.replaceAll(' ', '').replaceAll('x', ':').replaceAll('/', ':');
      final reg = RegExp(r'(\d+\.?\d*):(\d+\.?\d*)');
      final m = reg.firstMatch(cleaned);
      if (m != null) {
        final a = double.tryParse(m.group(1)!);
        final b = double.tryParse(m.group(2)!);
        if (a != null && b != null && b > 0) return a / b;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _refreshTrackLists() async {
    final c = _vlcController;
    if (c == null) return;
    try {
      final audio = await c.getAudioTracks(); // Map<int, String>
      final subs = await c.getSpuTracks(); // Map<int, String>
      if (!mounted) return;
      setState(() {
        _audioTracks = audio ?? {};
        _subtitleTracks = subs ?? {};
        _selectedAudioId ??= _audioTracks.isNotEmpty ? _audioTracks.keys.first : null;
        _selectedSubtitleId ??= _subtitleTracks.isNotEmpty ? _subtitleTracks.keys.first : -1;
      });
    } catch (e) {
      debugPrint('refreshTrackLists: $e');
    }
  }

  Future<void> _updatePosition() async {
    final c = _vlcController;
    if (c == null || !mounted) return;
    try {
      final playingNullable = await c.isPlaying();
      if (playingNullable == null) return;
      final playing = playingNullable;
      final pos = await c.getPosition();
      final dur = await c.getDuration();

      final posMs = pos?.inMilliseconds.toDouble() ?? _currentPosition;
      final durMs = dur?.inMilliseconds.toDouble() ?? _duration;

      if (!_isSeeking) {
        setState(() {
          _isPlaying = playing;
          _currentPosition = posMs;
          if (durMs > 0) _duration = durMs;
        });
      } else {
        setState(() => _isPlaying = playing);
      }
    } catch (e) {
      debugPrint('updatePosition error: $e');
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  Future<void> _togglePlayPause() async {
    final c = _vlcController;
    if (c == null) return;
    try {
      final playingNullable = await c.isPlaying();
      final playing = playingNullable ?? false;
      if (playing) {
        await c.pause();
      } else {
        await c.play();
      }
      if (mounted) setState(() => _isPlaying = !playing);
    } catch (e) {
      debugPrint('togglePlayPause error: $e');
    }
    _startHideTimer();
  }

  Future<void> _seekTo(double millis) async {
    final c = _vlcController;
    if (c == null) return;
    final ms = millis.clamp(0.0, _duration).toInt();
    try {
      await c.setTime(ms);
      if (mounted) _currentPosition = ms.toDouble();
    } catch (e) {
      debugPrint('seekTo error: $e');
    }
  }

  Future<void> _skipForward() => _seekTo((_currentPosition + _skipMs).clamp(0.0, _duration));
  Future<void> _skipBackward() => _seekTo((_currentPosition - _skipMs).clamp(0.0, _duration));

  Future<void> _setPlaybackSpeed(double s) async {
    final c = _vlcController;
    if (c == null) return;
    try {
      await c.setPlaybackSpeed(s);
      if (mounted) setState(() => _playbackSpeed = s);
    } catch (e) {
      debugPrint('setPlaybackSpeed error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Speed not supported')));
    }
  }

  Future<void> _changeAudioTrack(int id) async {
    final c = _vlcController;
    if (c == null) return;
    try {
      await c.setAudioTrack(id);
      if (mounted) setState(() => _selectedAudioId = id);
    } catch (e) {
      debugPrint('changeAudioTrack error: $e');
    }
  }

  Future<void> _changeSubtitleTrack(int? id) async {
    final c = _vlcController;
    if (c == null) return;
    try {
      if (id == -1) {
        await c.setSpuTrack(-1);
        if (mounted) setState(() => _selectedSubtitleId = -1);
      } else if (id != null) {
        await c.setSpuTrack(id);
        if (mounted) setState(() => _selectedSubtitleId = id);
      }
    } catch (e) {
      debugPrint('changeSubtitleTrack error: $e');
    }
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _isFullscreen = !_isFullscreen);
    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
    _startHideTimer();
  }

  String _formatMs(double ms) {
    final totalSeconds = (ms / 1000).floor();
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildControlBar({required bool fullscreen}) {
    final padding = fullscreen ? 16.0 : 8.0;
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      bottom: true,
      child: Container(
        color: Colors.black54,
        padding: EdgeInsets.fromLTRB(padding, 8, padding, 8 + bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text(_formatMs(_currentPosition), style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                min: 0,
                max: _duration > 0 ? _duration : 1.0,
                value: _currentPosition.clamp(0, _duration),
                onChangeStart: (_) {
                  _isSeeking = true;
                  _hideTimer?.cancel();
                },
                onChanged: (v) => setState(() => _currentPosition = v),
                onChangeEnd: (v) async {
                  await _seekTo(v);
                  _isSeeking = false;
                  _startHideTimer();
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(_formatMs(_duration), style: const TextStyle(color: Colors.white)),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: _skipBackward),
            const SizedBox(width: 12),
            IconButton(
              iconSize: 44,
              icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
              onPressed: _togglePlayPause,
            ),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: _skipForward),
            const SizedBox(width: 16),
            IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: _openSettingsSheet),
            const SizedBox(width: 12),
            IconButton(icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: _toggleFullscreen),
          ]),
        ]),
      ),
    );
  }

  void _openSettingsSheet() {
    _refreshTrackLists();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, sc) {
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: ListView(controller: sc, shrinkWrap: true, children: [
                const ListTile(title: Text('Playback Speed')),
                Wrap(spacing: 8, children: _speedOptions.map((s) {
                  final sel = _playbackSpeed == s;
                  return ChoiceChip(label: Text('${s}x'), selected: sel, onSelected: (_) async {
                    await _setPlaybackSpeed(s);
                    if (ctx.mounted) Navigator.pop(ctx);
                  });
                }).toList()),
                const Divider(),
                const ListTile(title: Text('Audio Tracks')),
                if (_audioTracks.isEmpty) const ListTile(title: Text('No audio tracks found'))
                else ..._audioTracks.entries.map((e) {
                  final id = e.key;
                  final label = e.value.isNotEmpty ? e.value : 'Audio $id';
                  return RadioListTile<int>(title: Text(label), value: id, groupValue: _selectedAudioId, onChanged: (val) async {
                    if (val != null) {
                      await _changeAudioTrack(val);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  });
                }),
                const Divider(),
                const ListTile(title: Text('Subtitles')),
                RadioListTile<int>(title: const Text('None'), value: -1, groupValue: _selectedSubtitleId ?? -2, onChanged: (val) async {
                  await _changeSubtitleTrack(-1);
                  if (ctx.mounted) Navigator.pop(ctx);
                }),
                if (_subtitleTracks.isEmpty) const ListTile(title: Text('No subtitles found'))
                else ..._subtitleTracks.entries.map((e) {
                  final id = e.key;
                  final label = e.value.isNotEmpty ? e.value : 'Subtitle $id';
                  return RadioListTile<int>(title: Text(label), value: id, groupValue: _selectedSubtitleId ?? -2, onChanged: (val) async {
                    if (val != null) {
                      await _changeSubtitleTrack(val);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  });
                }),
                const SizedBox(height: 12),
              ]),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _hideTimer?.cancel();
    try {
      _vlcController?.dispose();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_vlcController == null) return const Center(child: Text('Player not initialized', style: TextStyle(color: Colors.white)));

    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // Compute width & height that best fit the screen according to video aspect:
    double width = screenWidth;
    double height = width / _videoAspect;

    if (height > screenHeight) {
      height = screenHeight;
      width = height * _videoAspect;
    }

    // If NOT fullscreen, clamp height so very tall portrait videos don't take the entire screen
    final maxNonFsHeight = (screenHeight * 0.78).clamp(200.0, screenHeight);
    final displayHeight = _isFullscreen ? (height) : height.clamp(200.0, maxNonFsHeight);
    final displayWidth = _isFullscreen ? (width) : width;

    // When fullscreen, align video to top so controls sit at the bottom of the screen
    final alignment = _isFullscreen ? Alignment.topCenter : Alignment.center;

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // video area - virtualDisplay so overlays get taps
          Align(
            alignment: alignment,
            child: SizedBox(
              width: displayWidth,
              height: _isFullscreen ? screenHeight : displayHeight,
              child: VlcPlayer(
                controller: _vlcController!,
                aspectRatio: _videoAspect,
                placeholder: const Center(child: CircularProgressIndicator()),
                virtualDisplay: true,
              ),
            ),
          ),

          // Controls overlay (cover full screen) — taps will toggle
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _showControls = !_showControls);
              if (_showControls) _startHideTimer();
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showControls ? 1.0 : 0.0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildControlBar(fullscreen: _isFullscreen),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
