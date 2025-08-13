// lib/ui/screens/video_player_screen.dart
import 'package:flutter/material.dart';
import '../players/vlc_player_view.dart';

class VideoPlayerScreen extends StatelessWidget {
  final String videoPath;
  const VideoPlayerScreen({super.key, required this.videoPath});

  @override
  Widget build(BuildContext context) {
    // Debug print: show path when opening
    debugPrint('VideoPlayerScreen: opening -> ${videoPath}');
    return Scaffold(
      appBar: AppBar(title: const Text('Playing Video'), backgroundColor: Colors.black),
      backgroundColor: Colors.black,
      body: SafeArea(
        child: VLCPlayerView(videoPath: videoPath),
      ),
    );
  }
}
