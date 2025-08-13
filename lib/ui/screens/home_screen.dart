import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:list_all_videos/list_all_videos.dart';
import 'package:list_all_videos/model/video_model.dart';
import 'folder_videos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isLoading = true;
  Map<String, List<VideoDetails>> _folderMap = {};

  @override
  void initState() {
    super.initState();
    _loadAndGroupVideos();
  }

  Future<void> _loadAndGroupVideos() async {
    final status = await Permission.videos.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied) _showPermissionDialog();
      setState(() => _isLoading = false);
      return;
    }

    final mediaVideos = await ListAllVideos().getAllVideosPath();
    final pathsSet = mediaVideos.map((v) => v.videoPath).toSet();

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

    final mergedVideos = <VideoDetails>[];
    for (var vid in mediaVideos) {
      mergedVideos.add(vid);
    }
    for (var path in pathsSet.difference(mediaVideos.map((v) => v.videoPath).toSet())) {
      mergedVideos.add(VideoDetails(path));
    }

    // Group by folder
    final Map<String, List<VideoDetails>> grouped = {};
    for (var video in mergedVideos) {
      final folder = Directory(video.videoPath).parent.path;
      grouped.putIfAbsent(folder, () => []).add(video);
    }

    setState(() {
      _folderMap = grouped;
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

  @override
  Widget build(BuildContext context) {
    final folderNames = _folderMap.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Video Folders')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : folderNames.isEmpty
          ? const Center(child: Text('No videos found'))
          : ListView.separated(
        itemCount: folderNames.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, idx) {
          final folder = folderNames[idx];
          final count = _folderMap[folder]?.length ?? 0;
          return ListTile(
            leading: const Icon(Icons.folder, color: Colors.amber),
            title: Text(
              folder.split('/').last,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('$count videos'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FolderVideosScreen(
                    folderName: folder.split('/').last,
                    videos: _folderMap[folder]!,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
