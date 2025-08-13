// lib/ui/players/better_player_view.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:better_player_plus/better_player_plus.dart';
import '../../utils/content_uri_helper.dart'; // make sure path is correct

typedef PlaybackErrorCallback = void Function(String? message);

class BetterPlayerView extends StatefulWidget {
  final String videoPath;
  final PlaybackErrorCallback? onPlaybackError;

  const BetterPlayerView({
    super.key,
    required this.videoPath,
    this.onPlaybackError,
  });

  @override
  State<BetterPlayerView> createState() => _BetterPlayerViewState();
}

class _BetterPlayerViewState extends State<BetterPlayerView> {
  BetterPlayerController? _controller;
  bool _hasError = false;
  String? _errorMessage;
  String? _copiedTempPath;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    String playPath = widget.videoPath;

    // If this is a content:// URI or the file doesn't exist locally, copy it to a temp file
    try {
      final isContentUri = playPath.startsWith('content://');
      final fileExists = await File(playPath).exists().catchError((_) => false);

      if (isContentUri || !fileExists) {
        // copy via platform channel
        try {
          final copied = await ContentUriHelper.copyContentUriToFile(playPath);
          _copiedTempPath = copied;
          playPath = copied;
        } catch (e) {
          // copying failed — tell parent to fallback to VLC
          _reportError('Could not copy content URI to local file: $e');
          return;
        }
      }

      // initialize BetterPlayer with the local file path
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.file,
        playPath,
      );

      _controller = BetterPlayerController(
        const BetterPlayerConfiguration(
          autoPlay: true,
          aspectRatio: 16 / 9,
          fit: BoxFit.contain,
          controlsConfiguration: BetterPlayerControlsConfiguration(showControls: true),
        ),
        betterPlayerDataSource: dataSource,
      );

      _controller?.addEventsListener(_handleBetterPlayerEvent);
      _attachVideoPlayerListenerWhenReady();
      if (mounted) setState(() {});
    } catch (e) {
      _reportError('Failed to initialize BetterPlayer: $e');
    }
  }

  Future<void> _attachVideoPlayerListenerWhenReady() async {
    for (int i = 0; i < 10; i++) {
      final vp = _controller?.videoPlayerController;
      if (vp != null) {
        vp.addListener(_videoPlayerListener);
        return;
      }
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  void _videoPlayerListener() {
    final vp = _controller?.videoPlayerController;
    if (vp == null) return;
    try {
      if (vp.value.hasError) {
        final msg = vp.value.errorDescription ?? 'Platform player error';
        _reportError(msg);
      }
    } catch (_) {}
  }

  void _handleBetterPlayerEvent(BetterPlayerEvent event) {
    if (_hasError) return;
    if (event.betterPlayerEventType == BetterPlayerEventType.exception) {
      final msg = event.parameters?['message']?.toString() ?? 'Playback exception';
      _reportError(msg);
    }
  }

  void _reportError(String? message) {
    if (_hasError) return;
    _hasError = true;
    _errorMessage = message;
    widget.onPlaybackError?.call(message);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    try {
      _controller?.removeEventsListener(_handleBetterPlayerEvent);
    } catch (_) {}
    try {
      _controller?.videoPlayerController?.removeListener(_videoPlayerListener);
    } catch (_) {}
    _controller?.dispose();

    // delete temp file if we created one
    if (_copiedTempPath != null) {
      try {
        final f = File(_copiedTempPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 56),
            const SizedBox(height: 12),
            Text(
              _errorMessage ?? 'Playback error — switching to fallback player',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return BetterPlayer(controller: _controller!);
  }
}
