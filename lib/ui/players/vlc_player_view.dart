// lib/ui/players/vlc_player_view.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'vlc_controls.dart';

class VLCPlayerView extends StatefulWidget {
  final String videoPath;
  final bool isFullscreen;
  final ValueChanged<bool>? onFullscreenChanged;

  const VLCPlayerView({
    super.key,
    required this.videoPath,
    required this.isFullscreen,
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

  double _currentPosition = 0.0; // ms
  double _duration = 1.0; // ms
  bool _isPlaying = false;
  bool _isEnded = false;

  DateTime? _ignorePlayingUntil;
  static const int _ignoreAfterPlayMs = 1200;

  double _videoAspect = 16.0 / 9.0;
  double _playbackSpeed = 1.0;

  Map<int, String> _audioTracks = {};
  Map<int, String> _subtitleTracks = {};
  int? _selectedAudioId;
  int? _selectedSubtitleId;

  String? _initError;

  static const int _skipMs = 10000;
  final List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static const int _endedThresholdMs = 800;

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

    final pos = v.position;
    final dur = v.duration;
    final playing = v.isPlaying;
    final endedFlag = v.isEnded;

    final posMs = pos.inMilliseconds.toDouble();
    final durMs = (dur.inMilliseconds > 0) ? dur.inMilliseconds.toDouble() : _duration;

    final now = DateTime.now();
    final ignoreActive = _ignorePlayingUntil != null && now.isBefore(_ignorePlayingUntil!);

    final asp = v.aspectRatio;
    if (asp > 0 && asp.isFinite && asp != _videoAspect) {
      _videoAspect = asp;
    }

    if (!mounted) return;

    final effectivePlaying = !ignoreActive && playing;
    final effectiveEnded = ignoreActive ? false : endedFlag;

    setState(() {
      _currentPosition = posMs;
      if (durMs > 0) _duration = durMs;

      _isPlaying = effectivePlaying;

      if (effectiveEnded) {
        _isEnded = true;
      } else if (_duration > 0) {
        final nearEnd = _currentPosition >= (_duration - _endedThresholdMs);
        _isEnded = ((!_isPlaying) && nearEnd);
      } else {
        _isEnded = false;
      }

      if (_ignorePlayingUntil != null && !now.isBefore(_ignorePlayingUntil!)) {
        _ignorePlayingUntil = null;
      }
    });

    // Manage wakelock: keep screen on only while actively playing
    try {
      if (effectivePlaying) {
        WakelockPlus.enable();
      } else {
        // if paused/stopped/ended -> allow screen to sleep
        WakelockPlus.disable();
      }
    } catch (e) {
      debugPrint('wakelock error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initController();
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
    if (!mounted) return;
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

  Future<bool> _ensureController() async {
    if (_vlcController != null) return true;

    debugPrint('ensureController: controller null — attempting init');
    try {
      await _initController();
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

    try {
      if (path.startsWith('content://') || path.startsWith('http://') || path.startsWith('https://')) {
        _vlcController = VlcPlayerController.network(
          path,
          hwAcc: HwAcc.full,
          autoPlay: true,
          options: VlcPlayerOptions(),
        );
      } else {
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
          debugPrint('file not found — attempting network fallback for path: $path');
          _vlcController = VlcPlayerController.network(
            path,
            hwAcc: HwAcc.full,
            autoPlay: true,
            options: VlcPlayerOptions(),
          );
        }
      }

      _attachControllerListener();

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
    final maxMs = _duration > 0 ? _duration : millis;
    final ms = millis.clamp(0.0, maxMs).toInt();
    try {
      await c.seekTo(Duration(milliseconds: ms));
      if (mounted) {
        _currentPosition = ms.toDouble();
        if (_currentPosition < (_duration - _endedThresholdMs)) _isEnded = false;
      }
    } catch (e) {
      debugPrint('seekTo error: $e');
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

  /// Instead of toggling a local fullscreen flag, we ask the parent to change it.
  void _requestToggleFullscreen() {
    widget.onFullscreenChanged?.call(!widget.isFullscreen);
    _startHideTimer();
  }

  Future<bool> _forceRestartPlayback() async {
    final c = _vlcController;
    if (c == null) return false;

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
      if (c.value.isPlaying) return true;
    } catch (e) {
      debugPrint('forceRestartPlayback step1 error: $e');
    }

    try {
      _ignorePlayingUntil = DateTime.now().add(Duration(milliseconds: _ignoreAfterPlayMs));
      await c.stop();
      await Future.delayed(const Duration(milliseconds: 150));
      await c.play();
      await Future.delayed(const Duration(milliseconds: 400));
      if (c.value.isPlaying) return true;
    } catch (e) {
      debugPrint('forceRestartPlayback step2 error: $e');
    }

    try {
      await _disposeControllerSafe();
      await Future.delayed(const Duration(milliseconds: 120));
      await _initController();
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
        if (c2.value.isPlaying) return true;
      }
    } catch (e) {
      debugPrint('forceRestartPlayback step3 error: $e');
    }

    return false;
  }

  Future<void> _onPlayPausePressed() async {
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
        final success = await _forceRestartPlayback();
        if (!success) {
          setState(() => _initError = 'Unable to restart playback (see logs).');
        } else {
          if (mounted) {
            setState(() {
              _currentPosition = 0.0;
              _isPlaying = true;
              _isEnded = false;
              _initError = null;
            });
          }
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

  @override
  void dispose() {
    _hideTimer?.cancel();
    _detachControllerListener();
    try {
      _vlcController?.dispose();
    } catch (_) {}
    // Always disable wakelock when leaving the player
    try {
      WakelockPlus.disable();
    } catch (_) {}
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

    return LayoutBuilder(builder: (context, constraints) {
      final availHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : mq.size.height;
      final topPadding = mq.padding.top;
      final bottomPadding = mq.padding.bottom;

      final usableHeight = (availHeight - topPadding - bottomPadding).clamp(0.0, mq.size.height);

      double displayWidth;
      double displayHeight;

      if (widget.isFullscreen) {
        displayHeight = usableHeight;
        displayWidth = screenWidth;
      } else {
        if (_videoAspect > 0 && _videoAspect < 1.0) {
          // portrait -> height-first
          displayHeight = usableHeight * 0.95;
          displayWidth = displayHeight * _videoAspect;
          if (displayWidth > screenWidth) {
            displayWidth = screenWidth;
            displayHeight = displayWidth / _videoAspect;
          }
        } else {
          // landscape -> width-first
          displayWidth = screenWidth;
          displayHeight = displayWidth / (_videoAspect > 0 ? _videoAspect : (16.0 / 9.0));
          if (displayHeight > usableHeight * 0.95) {
            displayHeight = usableHeight * 0.95;
            displayWidth = displayHeight * (_videoAspect > 0 ? _videoAspect : (16.0 / 9.0));
          }
        }
      }

      final playerWidget = _vlcController == null
          ? const Center(child: CircularProgressIndicator())
          : widget.isFullscreen
          ? SizedBox.expand(
        child: VlcPlayer(
          controller: _vlcController!,
          aspectRatio: _videoAspect,
          placeholder: const Center(child: CircularProgressIndicator()),
          virtualDisplay: true,
        ),
      )
          : Center(
        child: SizedBox(
          width: displayWidth,
          height: displayHeight,
          child: VlcPlayer(
            controller: _vlcController!,
            aspectRatio: _videoAspect,
            placeholder: const Center(child: CircularProgressIndicator()),
            virtualDisplay: true,
          ),
        ),
      );

      return Container(
        color: Colors.black,
        child: Stack(
          children: [
            Align(alignment: widget.isFullscreen ? Alignment.topCenter : Alignment.center, child: playerWidget),

            // Gesture detector to toggle controls + double-tap to skip
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() => _showControls = !_showControls);
                if (_showControls) _startHideTimer();
              },
              onDoubleTapDown: (details) {
                final width = MediaQuery.of(context).size.width;
                // left half -> back, right half -> forward
                if (details.globalPosition.dx < width / 2) {
                  _skipBackward();
                } else {
                  _skipForward();
                }
                _startHideTimer();
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
                    isFullscreen: widget.isFullscreen, // <- rely on parent's authoritative state
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
                    onToggleFullscreen: _requestToggleFullscreen, // request parent to toggle
                    onOpenSettings: _openSettingsSheet,
                  ),
                ),
              ),
            ),

            errorOverlay,
          ],
        ),
      );
    });
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
}
