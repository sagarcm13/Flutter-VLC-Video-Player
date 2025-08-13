import 'package:flutter/material.dart';
import '../players/vlc_player_view.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoPath;
  const VideoPlayerScreen({super.key, required this.videoPath});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  bool _isFullscreen = false;

  void _onFullscreenChanged(bool isFs) {
    setState(() {
      _isFullscreen = isFs;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isFullscreen
          ? null
          : AppBar(
        title: const Text('Playing Video'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: VLCPlayerView(
          videoPath: widget.videoPath,
          onFullscreenChanged: _onFullscreenChanged,
        ),
      ),
    );
  }
}
