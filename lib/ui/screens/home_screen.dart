// lib/ui/screens/home_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:list_all_videos/list_all_videos.dart';
import 'package:list_all_videos/model/video_model.dart';
import 'package:list_all_videos/thumbnail/ThumbnailTile.dart';
import 'video_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  List<VideoDetails> _videos = [];

  @override
  void initState() {
    super.initState();
    _loadAndMergeVideos();
  }

  Future<void> _loadAndMergeVideos() async {
    final status = await Permission.videos.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) _showPermissionDialog();
      setState(() => _isLoading = false);
      return;
    }

    // Load from MediaStore
    final mediaVideos = await ListAllVideos().getAllVideosPath();
    final pathsSet = mediaVideos.map((v) => v.videoPath).toSet();

    // Manually scan folders for MKV
    for (var folderName in ['Download', 'Movies', 'DCIM']) {
      final dir = Directory('/storage/emulated/0/$folderName');
      if (await dir.exists()) {
        for (var entity in dir.listSync(recursive: true)) {
          if (entity is File && entity.path.toLowerCase().endsWith('.mkv')) {
            pathsSet.add(entity.path);
          }
        }
      }
    }

    // Build VideoDetails list—preserve thumbnails from MediaStore and create raw details for MKV
    final mergedVideos = <VideoDetails>[];
    for (var vid in mediaVideos) {
      mergedVideos.add(vid);
    }
    for (var path in pathsSet.difference(mediaVideos.map((v) => v.videoPath).toSet())) {
      mergedVideos.add(VideoDetails(path));
    }

    setState(() {
      _videos = mergedVideos;
      _isLoading = false;
    });
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'This app needs access to your videos to list and play them. Please grant permission in settings.'),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openAppSettings();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }

  void _openVideo(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(videoPath: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Video Player Home')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _videos.isEmpty
          ? const Center(child: Text('No videos found'))
          : RefreshIndicator(
        onRefresh: () async => _loadAndMergeVideos(),
        child: ListView.separated(
          itemCount: _videos.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, idx) {
            final v = _videos[idx];
            return ListTile(
              leading: ThumbnailTile(
                thumbnailController: v.thumbnailController,
                height: 64,
                width: 96,
              ),
              title: Text(v.videoName, overflow: TextOverflow.ellipsis),
              subtitle: Text(v.videoSize, overflow: TextOverflow.ellipsis),
              onTap: () => _openVideo(v.videoPath),
            );
          },
        ),
      ),
    );
  }
}
