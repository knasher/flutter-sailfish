# flutter_sailfish

Sailfish OS features for Flutter apps running on the flutter-sailfish runtime.
On other platforms it does nothing, so apps can use it without platform checks.

Not published on pub.dev yet.

## Display cut-outs

Apps run full screen, so they are drawn under the camera cut-out. Runtimes
with the view padding patches (flutter-sfos 7.sfos7 and later: engine patch
plus 0014) report the cut-out in `MediaQuery.padding`, so app bars draw behind
it with their contents below, and `SafeArea` and scroll views keep clear of
it, in every app with no code.

On older runtimes (patch 0009 only), use `SailfishCutouts.builder` as the
app's builder for the same result. It's safe to keep: on newer runtimes it
adds nothing.

```dart
MaterialApp(builder: SailfishCutouts.builder, home: const MyHomePage())
```

## App cover

The cover is what the home screen shows in the app's tile while the app is in
the background. Set it once, usually in `main()`:

```dart
SailfishCover.set(
  const MyCover(),
  actions: [
    CoverAction(icon: 'icon-cover-refresh', onPressed: refresh),
  ],
);
```

- The cover is an ordinary widget, drawn at the tile's size. Tiles are about
  446×714 pixels with four or fewer apps open and about 284×454 with more, so
  lay it out for both; it gets its size through `MediaQuery`.
- It has its own widget tree, so give it the app's state through listenables
  such as `ValueNotifier`s, not inherited widgets.
- It is redrawn while the home screen shows it, whenever it changes.
  `SailfishCover.visible` tells you when it's shown, for example to run a
  timer only then.
- Cover buttons are drawn by the home screen from Sailfish theme icons. Leave
  room for them at the bottom of the cover. The theme on SFOS 5.2 has:
  `icon-cover-alarm`, `-answer`, `-backup`, `-camera`, `-cancel`, `-dialer`,
  `-favorite`, `-hangup`, `-location`, `-message`, `-mute`, `-new`, `-next`,
  `-next-song`, `-pause`, `-people`, `-play`, `-previous`, `-previous-song`,
  `-refresh`, `-reject`, `-search`, `-shuffle`, `-subview`, `-sync`,
  `-timer`, `-transfers` and `-unmute`.

Needs a runtime with patch 0010.
