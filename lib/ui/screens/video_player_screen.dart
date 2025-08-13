// lib/ui/screens/video_player_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../players/vlc_player_view.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  const VideoPlayerScreen({super.key, required this.videoPath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _isFullscreen = false;
  bool _changingFullscreen = false; // guard to avoid re-entrancy

  /// Called by child when user requests fullscreen toggle.
  /// We update UI immediately and then apply SystemChrome/orientation changes.
  Future<void> _onFullscreenChanged(bool requestedFs) async {
    if (_changingFullscreen) return;
    _changingFullscreen = true;

    // remember previous state in case we need to revert
    final prev = _isFullscreen;

    // update UI immediately so icon reflects requested action
    if (mounted) setState(() => _isFullscreen = requestedFs);

    try {
      if (requestedFs) {
        // enter fullscreen (immersive + landscape)
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        } catch (e) {
          debugPrint('enter fullscreen system chrome error: $e');
          // revert if system chrome failed
          if (mounted) setState(() => _isFullscreen = prev);
        }
      } else {
        // exit fullscreen (edgeToEdge + portrait)
        try {
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          await SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
        } catch (e) {
          debugPrint('exit fullscreen system chrome error: $e');
          if (mounted) setState(() => _isFullscreen = prev);
        }
      }
    } finally {
      _changingFullscreen = false;
    }
  }

  @override
  void dispose() {
    // restore a safe state when leaving the screen
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _isFullscreen
          ? null
          : AppBar(
        title: const Text('Playing Video'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: _isFullscreen
      // fullscreen: let player occupy whole area (no SafeArea)
          ? VLCPlayerView(
        videoPath: widget.videoPath,
        isFullscreen: _isFullscreen,
        onFullscreenChanged: _onFullscreenChanged,
      )
      // normal: keep SafeArea so status bar / notch respected
          : SafeArea(
        child: VLCPlayerView(
          videoPath: widget.videoPath,
          isFullscreen: _isFullscreen,
          onFullscreenChanged: _onFullscreenChanged,
        ),
      ),
    );
  }
}
