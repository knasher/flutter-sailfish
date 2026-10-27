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
- Hardware decoding, with frames drawn straight by the GPU, a time limit on
  starting, a later start for GStreamer and a safer dispose (see
  [How it plays](#how-it-plays)).
- Renamed (`VideoPlayerSailfishPlugin`, `VideoPlayerSailfish`), and updated
  to video_player_platform_interface 6.9.

## Use

The flutter-sailfish build adds it to apps that use `video_player`, so
there's nothing to add (runtime 7.sfos8 and later). To use another copy, or
with an older runtime, list it next to `video_player`; the build then uses
yours:

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

GStreamer's `playbin` decodes the video. Where Sailfish OS's hardware decoder
(gst-droid's `droidvdec`) can decode it, its frames, Android graphics
buffers, go to Flutter as EGLImages and the GPU draws them as they are:
nothing is converted or copied on the CPU. Anything else (formats the
hardware doesn't decode, or devices without gst-droid) is decoded in software
(gstreamer1.0-libav), turned into RGBA by `videoconvert` and copied into a
Flutter texture, which costs CPU and battery for large videos.

- **Hardware decoding.** Needs runtime 7.sfos15 or later, whose embedder and
  engine draw these frames (as external textures, with Impeller or Skia). An
  app can use software decoding instead with
  `GST_PLUGIN_FEATURE_RANK=droidvdec:NONE` (needed with an older runtime).
  In `playbin`, gst-droid waited forever before the first frame: decodebin
  sends the decoder a second, identical `STREAM_START`, and gst-droid then
  waits for its codec to end a stream it was never given. The plugin drops
  that repeat. Known issue: an app closed just after showing a hardware video
  sometimes crashes as its process exits, in the phone's graphics buffer
  mapper, while the codec's buffers are still being freed (Jolla Phone
  2026). Nothing shows, and disposing a player while the app runs is fine.
- **No freezes.** `create` waits at most 5 seconds for the first frame, then
  fails, so `VideoPlayerController.initialize` throws instead of the app
  hanging. Sony's version waited forever on the platform thread.
- **Started when needed.** GStreamer is set up before the first video, not at
  app start, as without its plugin cache that means loading every plugin
  (about half a second).
- **A plugin cache in the sandbox.** Sailjail only shows GStreamer's shared
  cache (`~/.cache/gstreamer-1.0`) to apps with the `Audio` permission, so
  for other apps the plugin keeps one in the app's cache folder
  (`~/.cache/<org>/<app>/gstreamer-1.0`). Only the first video the app ever
  plays loads every plugin; after that GStreamer starts in a few
  milliseconds. An app that sets `GST_REGISTRY` keeps its own.
- **A safer dispose.** Flutter's raster thread can still ask a disposed
  player's texture for a frame until the texture is unregistered, so the
  player's texture and buffers are freed only after that. Sony's version
  freed them at once.

Changes to Sony's code are listed at the top of this file and in the
comments where they were made.
