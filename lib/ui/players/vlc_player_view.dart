// lib/ui/players/vlc_player_view.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'vlc_controls.dart';

class VLCPlayerView extends StatefulWidget {
  final String videoPath;
  final ValueChanged<bool>? onFullscreenChanged;

  const VLCPlayerView({
    super.key,
    required this.videoPath,
    this.onFullscreenChanged,
  });

  @override
  State<VLCPlayerView> createState() => _VLCPlayerViewState();
}

class _VLCPlayerViewState extends State<VLCPlayerView> {
  VlcPlayerController? _vlcController;

  Timer? _hideTimer;
  bool _loading = true;
  bool _showControls = true;

  // UI state driven by controller.value via listener:
  double _currentPosition = 0.0; // ms
  double _duration = 1.0; // ms
  bool _isPlaying = false;
  bool _isEnded = false;

  // temporary ignore window after issuing play to avoid racing UI updates (ms)
  DateTime? _ignorePlayingUntil;
  // increased slightly to give controller time to stabilize
  static const int _ignoreAfterPlayMs = 1200;

  bool _isFullscreen = false;
  double _videoAspect = 16.0 / 9.0;
  double _playbackSpeed = 1.0;

  Map<int, String> _audioTracks = {};
  Map<int, String> _subtitleTracks = {};
  int? _selectedAudioId;
  int? _selectedSubtitleId;

  String? _initError; // human readable init error message

  static const int _skipMs = 10000;
  final List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  // ended threshold for manual checks (ms)
  static const int _endedThresholdMs = 800;

  // Attach / detach listener
  void _attachControllerListener() {
    try {
      _vlcController?.addListener(_controllerListener);
    } catch (e) {
      debugPrint('attachListener failed: $e');
    }
  }

  void _detachControllerListener() {
    try {
      _vlcController?.removeListener(_controllerListener);
    } catch (_) {}
  }

  void _controllerListener() {
    final c = _vlcController;
    if (c == null) return;
    final v = c.value;

    // debug: log authoritative state
    debugPrint(
        'controllerListener: playing=${v.isPlaying} pos=${v.position.inMilliseconds} dur=${v.duration.inMilliseconds} ended=${v.isEnded} aspect=${v.aspectRatio} ignoreUntil=$_ignorePlayingUntil');

    // controller value fields
    final pos = v.position;
    final dur = v.duration;
    final playing = v.isPlaying;
    final endedFlag = v.isEnded;

    final posMs = pos.inMilliseconds.toDouble();
    final durMs = (dur.inMilliseconds > 0) ? dur.inMilliseconds.toDouble() : _duration;

    final now = DateTime.now();
    final ignoreActive = _ignorePlayingUntil != null && now.isBefore(_ignorePlayingUntil!);

    // Use aspect ratio reported by controller if available
    final asp = v.aspectRatio;
    if (asp > 0 && asp.isFinite && asp != _videoAspect) {
      _videoAspect = asp;
    }

    if (!mounted) return;
    setState(() {
      // update duration/position
      _currentPosition = posMs;
      if (durMs > 0) _duration = durMs;

      // update playing but respect ignore window (don't overwrite immediately after our play())
      if (!ignoreActive) {
        _isPlaying = playing;
      }

      // IMPORTANT: during the ignore window we *don't* accept controller's isEnded=true
      final effectiveEnded = ignoreActive ? false : endedFlag;

      // ended detection: prefer controller's isEnded when not ignored; otherwise fallback to near-end & not playing
      if (effectiveEnded) {
        _isEnded = true;
      } else if (_duration > 0) {
        final nearEnd = _currentPosition >= (_duration - _endedThresholdMs);
        _isEnded = ((!_isPlaying) && nearEnd);
      } else {
        _isEnded = false;
      }

      // clear ignore window if expired
      if (_ignorePlayingUntil != null && !now.isBefore(_ignorePlayingUntil!)) {
        _ignorePlayingUntil = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initController(); // create controller initially
  }

  @override
  void didUpdateWidget(covariant VLCPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // if path changed, recreate controller
    if (oldWidget.videoPath != widget.videoPath) {
      debugPrint('videoPath changed -> reinit controller');
      _recreateController();
    }
  }

  String _normalize(String p) {
    if (p.startsWith('content://') || p.startsWith('http://') || p.startsWith('https://')) return p;
    return p.startsWith('/') ? p : '/$p';
  }

  Future<bool> _fileExists(String path) async {
    try {
      final f = File(path);
      return await f.exists();
    } catch (_) {
      return false;
    }
  }

  Future<void> _recreateController() async {
    await _disposeControllerSafe();
    setState(() {
      _loading = true;
      _initError = null;
      _currentPosition = 0.0;
      _duration = 1.0;
      _isPlaying = false;
      _isEnded = false;
    });
    await _initController();
  }

  Future<void> _disposeControllerSafe() async {
    _detachControllerListener();
    try {
      await _vlcController?.stop();
    } catch (_) {}
    try {
      await _vlcController?.dispose();
    } catch (_) {}
    _vlcController = null;
  }

  /// Try to create controller if missing. Returns true if controller exists after this call.
  Future<bool> _ensureController() async {
    if (_vlcController != null) return true;

    debugPrint('ensureController: controller null — attempting init');
    try {
      await _initController();
      // short wait to allow value to populate
      await Future.delayed(const Duration(milliseconds: 120));
      return _vlcController != null;
    } catch (e) {
      debugPrint('ensureController failed: $e');
      return false;
    }
  }

  Future<void> _initController() async {
    final raw = widget.videoPath;
    final path = _normalize(raw);
    debugPrint('VLC init: raw="$raw" normalized="$path"');

    // defensive checks & choose method
    try {
      // If it's a content or http(s) uri — use network
      if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://')) {
        _vlcController = VlcPlayerController.network(
          path,
          hwAcc: HwAcc.full,
          autoPlay: true,
          options: VlcPlayerOptions(),
        );
      } else {
        // treat as file path; verify exists
        final exists = await _fileExists(path);
        debugPrint('file exists? $exists path=$path');
        if (exists) {
          _vlcController = VlcPlayerController.file(
            File(path),
            hwAcc: HwAcc.full,
            autoPlay: true,
            options: VlcPlayerOptions(),
          );
        } else {
          // fallback attempt: try network creation (some paths might be accessible via file URI)
          debugPrint('file not found — attempting network fallback for path: $path');
          _vlcController = VlcPlayerController.network(
            path,
            hwAcc: HwAcc.full,
            autoPlay: true,
            options: VlcPlayerOptions(),
          );
        }
      }

      // Attach listener and start
      _attachControllerListener();

      // small delays to populate controller.value
      await Future.delayed(const Duration(milliseconds: 300));
      Future.delayed(const Duration(milliseconds: 700), _refreshTrackLists);

      if (!mounted) return;
      setState(() {
        _loading = false;
        _initError = null;
      });
    } catch (e, st) {
      debugPrint('VLC init error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _initError = 'Failed to open video (${e.toString()})';
      });
    }
  }

  Future<void> _refreshTrackLists() async {
    final c = _vlcController;
    if (c == null) return;
    try {
      final audio = await c.getAudioTracks();
      final subs = await c.getSpuTracks();
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

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  Future<void> _seekTo(double millis) async {
    final c = _vlcController;
    if (c == null) return;
    final ms = millis.clamp(0.0, _duration).toInt();
    try {
      // prefer seekTo API when available (it accepts Duration)
      await c.seekTo(Duration(milliseconds: ms));
      if (mounted) {
        _currentPosition = ms.toDouble();
        if (_currentPosition < (_duration - _endedThresholdMs)) _isEnded = false;
      }
    } catch (e) {
      debugPrint('seekTo error: $e');
      // fallback to setTime if needed
      try {
        await c.setTime(ms);
        if (mounted) {
          _currentPosition = ms.toDouble();
          if (_currentPosition < (_duration - _endedThresholdMs)) _isEnded = false;
        }
      } catch (e2) {
        debugPrint('setTime fallback error: $e2');
      }
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

  /// Forceful restart sequence with multiple fallback attempts.
  Future<bool> _forceRestartPlayback() async {
    final c = _vlcController;
    if (c == null) return false;

    debugPrint('forceRestartPlayback: start sequence');

    // 1) seekTo(0) + play()
    try {
      _ignorePlayingUntil = DateTime.now().add(Duration(milliseconds: _ignoreAfterPlayMs));
      try {
        await c.seekTo(Duration.zero);
      } catch (_) {
        try {
          await c.setTime(0);
        } catch (_) {}
      }
      await c.play();
      await Future.delayed(const Duration(milliseconds: 400));
      if (c.value.isPlaying) {
        debugPrint('forceRestartPlayback: success with seek+play');
        return true;
      }
      debugPrint('forceRestartPlayback: seek+play did not start');
    } catch (e) {
      debugPrint('forceRestartPlayback: seek+play error: $e');
    }

    // 2) stop + play
    try {
      _ignorePlayingUntil = DateTime.now().add(Duration(milliseconds: _ignoreAfterPlayMs));
      await c.stop();
      await Future.delayed(const Duration(milliseconds: 150));
      await c.play();
      await Future.delayed(const Duration(milliseconds: 400));
      if (c.value.isPlaying) {
        debugPrint('forceRestartPlayback: success with stop+play');
        return true;
      }
      debugPrint('forceRestartPlayback: stop+play did not start');
    } catch (e) {
      debugPrint('forceRestartPlayback: stop+play error: $e');
    }

    // 3) recreate controller and play
    try {
      debugPrint('forceRestartPlayback: recreating controller as fallback');
      final oldPath = widget.videoPath;
      await _disposeControllerSafe();
      await Future.delayed(const Duration(milliseconds: 120));
      await _initController(); // this attaches listener again
      await Future.delayed(const Duration(milliseconds: 300));
      if (_vlcController != null) {
        final c2 = _vlcController!;
        _ignorePlayingUntil = DateTime.now().add(Duration(milliseconds: _ignoreAfterPlayMs));
        try {
          await c2.seekTo(Duration.zero);
        } catch (_) {
          try {
            await c2.setTime(0);
          } catch (_) {}
        }
        await c2.play();
        await Future.delayed(const Duration(milliseconds: 400));
        if (c2.value.isPlaying) {
          debugPrint('forceRestartPlayback: success after recreate');
          return true;
        }
        debugPrint('forceRestartPlayback: recreate+play did not start');
      } else {
        debugPrint('forceRestartPlayback: recreate resulted in null controller');
      }
    } catch (e) {
      debugPrint('forceRestartPlayback: recreate error: $e');
    }

    debugPrint('forceRestartPlayback: all fallbacks failed');
    return false;
  }

  /// Play/pause button handler. If video ended, restart from 0.
  Future<void> _onPlayPausePressed() async {
    // Ensure controller exists (try to recreate if null)
    final ok = await _ensureController();
    if (!ok) {
      setState(() {
        _initError = 'Unable to open video. Tap Retry.';
      });
      return;
    }

    final c = _vlcController!;
    try {
      final v = c.value;
      final playing = v.isPlaying;
      final durMs = v.duration.inMilliseconds.toDouble();
      final posMs = v.position.inMilliseconds.toDouble();

      final nearEnd = (durMs > 0) && (posMs >= (durMs - _endedThresholdMs));

      if ((v.isEnded || nearEnd) && !playing) {
        // Try forceful restart sequence
        final success = await _forceRestartPlayback();
        if (!success) {
          setState(() => _initError = 'Unable to restart playback (see logs).');
        } else {
          if (mounted) setState(() {
            _currentPosition = 0.0;
            _isPlaying = true;
            _isEnded = false;
            _initError = null;
          });
        }
      } else {
        if (playing) {
          await c.pause();
          if (mounted) setState(() => _isPlaying = false);
        } else {
          _ignorePlayingUntil = DateTime.now().add(Duration(milliseconds: _ignoreAfterPlayMs));
          await c.play();
          if (mounted) setState(() => _isPlaying = true);
        }
      }
    } catch (e) {
      debugPrint('onPlayPausePressed error: $e');
      setState(() => _initError = 'Playback error: ${e.toString()}');
    }

    _startHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _isFullscreen = !_isFullscreen);
    widget.onFullscreenChanged?.call(_isFullscreen);

    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    }
    _startHideTimer();
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
                  final label = (e.value ?? '').isNotEmpty ? e.value : 'Audio $id';
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
                  final label = (e.value ?? '').isNotEmpty ? e.value : 'Subtitle $id';
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
    _hideTimer?.cancel();
    _detachControllerListener();
    try {
      _vlcController?.dispose();
    } catch (_) {}
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final mq = MediaQuery.of(context);
    final screenWidth = mq.size.width;
    final screenHeight = mq.size.height;

    // compute display size (portrait videos should take most height)
    double displayWidth;
    double displayHeight;

    if (_isFullscreen) {
      displayWidth = screenWidth;
      displayHeight = screenHeight;
    } else {
      if (_videoAspect < 1.0) {
        displayHeight = min(screenHeight * 0.95, screenHeight);
        displayWidth = displayHeight * _videoAspect;
        if (displayWidth > screenWidth) {
          displayWidth = screenWidth;
          displayHeight = displayWidth / _videoAspect;
        }
      } else {
        displayWidth = screenWidth;
        displayHeight = displayWidth / _videoAspect;
        if (displayHeight > screenHeight) {
          displayHeight = screenHeight;
          displayWidth = displayHeight * _videoAspect;
        }
      }
    }

    final alignment = _isFullscreen ? Alignment.topCenter : Alignment.center;

    // If there was an init error, show overlay with retry
    final errorOverlay = _initError != null
        ? Positioned.fill(
      child: Container(
        color: Colors.black87,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_initError!, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                _recreateController();
              },
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            Text('Path: ${widget.videoPath}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      ),
    )
        : const SizedBox.shrink();

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Align(
            alignment: alignment,
            child: _isFullscreen
                ? SizedBox.expand(
              child: _vlcController == null
                  ? const Center(child: CircularProgressIndicator())
                  : VlcPlayer(
                controller: _vlcController!,
                aspectRatio: _videoAspect,
                placeholder: const Center(child: CircularProgressIndicator()),
                virtualDisplay: true,
              ),
            )
                : SizedBox(
              width: displayWidth,
              height: displayHeight,
              child: _vlcController == null
                  ? const Center(child: CircularProgressIndicator())
                  : VlcPlayer(
                controller: _vlcController!,
                aspectRatio: _videoAspect,
                placeholder: const Center(child: CircularProgressIndicator()),
                virtualDisplay: true,
              ),
            ),
          ),

          // Controls overlay at bottom (still present)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _showControls = !_showControls);
              if (_showControls) _startHideTimer();
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: _showControls && _initError == null ? 1.0 : 0.0,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: VLCControls(
                  currentPosition: _currentPosition,
                  duration: _duration,
                  isPlaying: _isPlaying,
                  isFullscreen: _isFullscreen,
                  playbackSpeed: _playbackSpeed,
                  audioTracks: _audioTracks,
                  subtitleTracks: _subtitleTracks,
                  selectedAudioId: _selectedAudioId,
                  selectedSubtitleId: _selectedSubtitleId,
                  onSeekChanged: (v) {
                    setState(() => _currentPosition = v);
                  },
                  onSeekEnd: (v) async {
                    await _seekTo(v);
                    _startHideTimer();
                  },
                  onSeekStart: () {
                    _hideTimer?.cancel();
                  },
                  onPlayPause: _onPlayPausePressed,
                  onSkipForward: _skipForward,
                  onSkipBackward: _skipBackward,
                  onToggleFullscreen: _toggleFullscreen,
                  onOpenSettings: _openSettingsSheet,
                ),
              ),
            ),
          ),

          // error overlay (if present)
          errorOverlay,
        ],
      ),
    );
  }
}
