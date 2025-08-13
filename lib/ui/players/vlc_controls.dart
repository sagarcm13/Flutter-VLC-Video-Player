// lib/ui/players/vlc_controls.dart
import 'package:flutter/material.dart';

class VLCControls extends StatelessWidget {
  final double currentPosition;
  final double duration;
  final bool isPlaying;
  final bool isFullscreen;
  final double playbackSpeed;
  final Map<int, String> audioTracks;
  final Map<int, String> subtitleTracks;
  final int? selectedAudioId;
  final int? selectedSubtitleId;

  final VoidCallback onSeekStart;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;

  final VoidCallback onPlayPause;
  final VoidCallback onSkipForward;
  final VoidCallback onSkipBackward;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onOpenSettings;

  const VLCControls({
    super.key,
    required this.currentPosition,
    required this.duration,
    required this.isPlaying,
    required this.isFullscreen,
    required this.playbackSpeed,
    required this.audioTracks,
    required this.subtitleTracks,
    required this.selectedAudioId,
    required this.selectedSubtitleId,
    required this.onSeekStart,
    required this.onSeekChanged,
    required this.onSeekEnd,
    required this.onPlayPause,
    required this.onSkipForward,
    required this.onSkipBackward,
    required this.onToggleFullscreen,
    required this.onOpenSettings,
  });

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
    final bottom = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      bottom: true,
      child: Container(
        color: Colors.black54,
        padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottom),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // slider row
          Row(children: [
            Text(_formatMs(currentPosition), style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 8),
            Expanded(
              child: Slider(
                min: 0,
                max: duration > 0 ? duration : 1.0,
                value: currentPosition.clamp(0, duration),
                onChangeStart: (_) => onSeekStart(),
                onChanged: (v) => onSeekChanged(v),
                onChangeEnd: (v) => onSeekEnd(v),
              ),
            ),
            const SizedBox(width: 8),
            Text(_formatMs(duration), style: const TextStyle(color: Colors.white)),
          ]),

          const SizedBox(height: 6),

          // control buttons
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: onSkipBackward),
            const SizedBox(width: 12),
            IconButton(
              iconSize: 44,
              icon: Icon(isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white),
              onPressed: onPlayPause,
            ),
            const SizedBox(width: 12),
            IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: onSkipForward),
            const SizedBox(width: 16),
            IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: onOpenSettings),
            const SizedBox(width: 12),
            IconButton(icon: Icon(isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: onToggleFullscreen),
          ]),
        ]),
      ),
    );
  }
}
