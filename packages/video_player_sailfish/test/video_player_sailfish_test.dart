import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:video_player_sailfish/video_player_sailfish.dart';

void main() {
  test('registers itself', () {
    VideoPlayerSailfish.registerWith();
    expect(VideoPlayerPlatform.instance, isA<VideoPlayerSailfish>());
  });
}
