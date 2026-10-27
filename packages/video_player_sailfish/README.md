# video_player_sailfish

Sailfish OS implementation of
[video_player](https://pub.dev/packages/video_player), playing video with
GStreamer. Not published on pub.dev yet.

video_player has no Linux version, so without this its calls fail on
Sailfish OS.

Based on Sony's
[video_player_elinux](https://github.com/sony/flutter-elinux-plugins/tree/main/packages/video_player)
(commit `b791e87`, December 2024; BSD-3-Clause, see [LICENSE](LICENSE)).
Changes for Sailfish OS:

- Assets are found in `/usr/share/<app>/data/flutter_assets`, where
  Sailfish apps keep their bundle, as well as next to the binary.
- Software decoding, a time limit on starting and a later start for
  GStreamer (see [How it plays](#how-it-plays)).
- Renamed (`VideoPlayerSailfishPlugin`, `VideoPlayerSailfish`), and updated
  to video_player_platform_interface 6.9.

## Use

```yaml
dependencies:
  video_player: ^2.14.1
  video_player_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/video_player_sailfish
```

It's a native plugin, so the app's RPM must be built with GStreamer's
headers, and should require the GStreamer plugins that play its videos
(`rpm/<app>.yaml`):

```yaml
Requires:
- gstreamer1.0-plugins-base   # playbin, videoconvert
- gstreamer1.0-plugins-good   # MP4
- gstreamer1.0-libav          # H.264 and other decoders
PkgBR:
- pkgconfig(gstreamer-1.0)
```

## How it plays

GStreamer's `playbin` decodes the video, `videoconvert` turns each frame into
RGBA, and the frames are copied into a Flutter texture. That works on any
device but uses the CPU for the conversion and copy, so large videos cost
battery.

- **Software decoding.** Sailfish OS's hardware decoder (gst-droid) stalled
  before the first frame with this pipeline, so the plugin turns it off
  (rank `droidvdec` to none) and GStreamer uses FFmpeg's decoders
  (gstreamer1.0-libav). An app can still choose with
  `GST_PLUGIN_FEATURE_RANK`, which the plugin leaves alone if it names
  `droidvdec`.
- **No freezes.** `create` waits at most 5 seconds for the first frame, then
  fails, so `VideoPlayerController.initialize` throws instead of the app
  hanging. Sony's version waited forever on the platform thread.
- **Started when needed.** GStreamer is set up before the first video, not at
  app start: in Sailjail's sandbox it can't keep its plugin cache, so setting
  up means loading every plugin (about half a second).

Changes to Sony's code are listed at the top of this file and in the
comments where they were made.
