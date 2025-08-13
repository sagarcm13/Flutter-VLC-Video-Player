import 'package:flutter/material.dart';
import 'package:list_all_videos/model/video_model.dart';
import 'package:list_all_videos/thumbnail/ThumbnailTile.dart';
import 'video_player_screen.dart';

class FolderVideosScreen extends StatelessWidget {
  final String folderName;
  final List<VideoDetails> videos;

  const FolderVideosScreen({
    super.key,
    required this.folderName,
    required this.videos,
  });

  void _openVideo(BuildContext context, String path) {
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
      appBar: AppBar(title: Text(folderName)),
      body: ListView.separated(
        itemCount: videos.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, idx) {
          final v = videos[idx];
          return ListTile(
            leading: ThumbnailTile(
              thumbnailController: v.thumbnailController,
              height: 64,
              width: 96,
            ),
            title: Text(v.videoName, overflow: TextOverflow.ellipsis),
            subtitle: Text(v.videoSize, overflow: TextOverflow.ellipsis),
            onTap: () => _openVideo(context, v.videoPath),
          );
        },
      ),
    );
  }
}
