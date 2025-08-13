import 'package:flutter/services.dart';

class ContentUriHelper {
  static const MethodChannel _channel = MethodChannel('app.channel.content_copy');

  /// Copies the content:// URI to a temporary file and returns the file path.
  /// Throws PlatformException on failure.
  static Future<String> copyContentUriToFile(String uri) async {
    final res = await _channel.invokeMethod<String>('copyUriToFile', {'uri': uri});
    if (res == null) throw Exception('Failed to copy URI to file');
    return res;
  }
}
