# Porting a Flutter app to Sailfish OS

Copy the app-side files into an existing Flutter project:

```bash
cp -a template/elinux your_app/elinux
cp -a template/.sfosbuild your_app/.sfosbuild
cp -a template/rpm your_app/rpm
# rename elinux/app.desktop.in and rpm/app.yaml.in to your app's name
# set BINARY_NAME in elinux/CMakeLists.txt (the same name)
# set FLUTTER_VERSION in elinux/flutter-sfos.env
# set Name, Exec and the [X-Sailjail] section in the desktop file
# the yaml's ExtraInstall lines must use the same name
```

```bash
cd your_app
./elinux/build.sh              # flutter-elinux build + RPM inside sfosbuild
./elinux/build.sh deploy       # DEVICE=defaultuser@192.168.1.177
```

No host Flutter SDK is required. ExtraInstall runs stock
`flutter-elinux build elinux --release --target-arch=arm64 --target-backend-type=wayland`
in the aarch64 Sailfish image (plugins and native `.so` included). The
only Sailfish-specific step is overlaying our engine/embedder `.so` in
the flutter-elinux cache, then dropping those `.so` from the app RPM so
the device uses `flutter-sfos-<ver>`.

`elinux/CMakeLists.txt` and `elinux/flutter/CMakeLists.txt` are stock
flutter-elinux templates (`ephemeral/`). Do not point them at
`find_package(flutter-sfos)`.

## What you need (and what to host)

You do **not** need the Flutter engine source in the app repo.

**On the machine that builds the app**

- Docker + [sfosbuild](https://github.com/mrcyjanek/sfosbuild)
- Matching **device RPMs** (`flutter-sfos-<ver>` and `-devel`)  
  From this repo: `make FLUTTER=<ver> runtime` → `versions/<ver>/runtime/rpms/`  
  `FLUTTER_SFOS_RPMS=/path/to/rpms ./elinux/build.sh`

`-devel` ships a full aarch64 Flutter SDK (real git checkout and default
`flutter precache`), `gen_snapshot`, and flutter-elinux. ExtraInstall
`rpm -Uvh`s it, then `flutter-sfos-aot` (the elinux driver).

**On the phone**

- `flutter-sfos-<ver>` (same pin as AOT). OpenRepos or `make deploy` from this repo.

**What to publish** if other people should build without this git tree

1. `flutter-sfos-<ver>` and `flutter-sfos-<ver>-devel` aarch64 RPMs (OpenRepos and/or GitHub Releases).

Engine/embedder source stays in *this* repo. App repos only consume those
RPMs plus `elinux/`, `rpm/`, and `.sfosbuild/`.

See `examples/hello/` (`./elinux/build.sh`).

## Sailfish features: the flutter_sailfish package

Features only Sailfish has, such as app covers, and fixes that need app code,
such as display cut-outs, are in the Dart package `packages/flutter_sailfish`.
It isn't on pub.dev yet, so add it as a git dependency:

```yaml
dependencies:
  flutter_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/flutter_sailfish
```

On other platforms nothing answers its channels, so it does nothing there and
needs no platform checks.

Apps built through this repo's Makefile (`make FLUTTER=<ver> app APP=<dir>`)
use the copy in `packages/flutter_sailfish` instead, so the package matches
the runtime built here. `./elinux/build.sh` does the same when
`FLUTTER_SAILFISH_PATH` points at a copy: it copies the package into the app
(the build container only sees the app's folder) and writes a marked
`pubspec_overrides.yaml`. Add both to the app's `.gitignore`:

```
/.flutter_sailfish/
/pubspec_overrides.yaml
```

`examples/hello/` uses both features.

### Camera cut-outs

Apps run full screen, so content is drawn under the camera cut-out, and the
Flutter embedder API can't set `MediaQuery.padding`. Use the package's builder
wherever the app creates its `MaterialApp` (in `MyApp.build` for a project made
with `flutter create`):

```dart
import 'package:flutter_sailfish/flutter_sailfish.dart';

return MaterialApp(
  builder: SailfishCutouts.builder,
  // ...the rest unchanged
);
```

If the `MaterialApp` already has a `builder`, wrap it:
`builder: (context, child) => SailfishCutouts.builder(context, yourBuilder(context, child))`.

`AppBar` then draws its background behind the cut-out and keeps its contents
below it, and `SafeArea` and scroll views keep clear of it, as on a phone with
a notch. Needs a `flutter-sfos` runtime with patch 0009.

How it works: the runtime reads the cut-outs from the device's Silica settings
and sends them, at start-up and whenever the orientation changes, as JSON on
`flutter-sfos/display_cutouts`, in physical pixels for the current
orientation (`version` changes only if the format changes incompatibly):

```json
{"version": 1,
 "padding": {"top": 66, "right": 0, "bottom": 0, "left": 0},
 "cutouts": [{"left": 310, "top": 0, "width": 414, "height": 66}]
}
```

### App covers

The cover is what the home screen shows in the app's tile while the app is in
the background. Without one, the home screen shows a shrunken copy of the app.
Set it in `main()`:

```dart
import 'package:flutter_sailfish/flutter_sailfish.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // needed before using a channel
  SailfishCover.set(
    const MyCover(),
    actions: [
      CoverAction(icon: 'icon-cover-refresh', onPressed: refresh),
    ],
  );
  runApp(const MyApp());
}
```

- **Size.** The cover is an ordinary widget, laid out at the tile's size:
  about 446×714 pixels with four or fewer apps open and 284×454 with more (on
  the Jolla Phone 2026). The home screen resizes it when the number of apps
  changes, so lay it out for both; `MediaQuery` gives the size.
- **State.** It has its own widget tree, separate from the app's, so give it
  the app's state through listenables such as `ValueNotifier`s rather than
  inherited widgets (see `CounterCover` in `examples/hello/lib/main.dart`).
- **When it's drawn.** Once when set, then only while the home screen shows
  it: again whenever it changes, for example on `setState`.
  `SailfishCover.visible` says when it's shown, for example to run a clock
  only then. Covers are meant for occasional updates, not animation.
- **Buttons.** The home screen draws `CoverAction`s along the bottom of the
  cover from Sailfish theme icons (`icon-cover-new`, `-refresh`, `-next`,
  `-pause`, `-play`, …; the package README lists them all), so leave room
  there. Taps call `onPressed`, and don't open the app.

Needs a `flutter-sfos` runtime with patch 0010. Works in sandboxed apps:
Sailjail lets every app own the cover buttons' D-Bus name
(`org.sailfishos.coveraction.*`).

How it works: the package draws the cover off-screen and sends the picture on
`flutter-sfos/cover_frame`; the first one makes the runtime create a cover
window, which Lipstick shows in the tile instead of the app's window, so
opening the app is as smooth as for native apps. `flutter-sfos/cover` tells
the app whether it can have a cover, whether it's shown and its size, and
carries the buttons and their taps.

## App lifecycle

Works without app code. Apps get Flutter's usual lifecycle states, so
`AppLifecycleListener` and `WidgetsBindingObserver.didChangeAppLifecycleState`
behave as on Android and iOS:

- **resumed** while the app is in front;
- **hidden** while it's only shown as its tile on the home screen (apps
  without a cover);
- **paused** while it isn't shown at all: minimised behind its cover,
  another app in front, or the screen off.

When hidden or paused, the app stops drawing frames and animations stop, which
saves battery; timers and other Dart code keep running. A cover set with
`SailfishCover` keeps updating while the app is paused. Needs a `flutter-sfos`
runtime with patch 0011.

## Plugins

Flutter apps on Sailfish OS are Linux apps to Dart (`Platform.isLinux`), and
flutter-elinux builds them with the Linux plugin registrant. So:

- **Pure-Dart plugins** work as they are.
- **Plugins with a Dart-only Linux version** (`dartPluginClass` for `linux`,
  e.g. path_provider_linux, shared_preferences_linux, package_info_plus,
  connectivity_plus, geolocator_linux) are registered automatically. Whether
  they work depends on what they use on Linux: GNOME's NetworkManager or
  GeoClue2, for instance, aren't on Sailfish OS, and Sailjail limits where
  apps can write.
- **Plugins with native Linux code** (C++/GTK, e.g. url_launcher_linux,
  flutter_secure_storage_linux) and plugins with no Linux version at all
  (Firebase, video_player, screen_brightness) aren't available: calling them
  throws (`MissingPluginException`, a channel `PlatformException` or
  `UnimplementedError`).

Sailfish versions of standard plugins are separate packages in
[packages/](../packages), one per plugin. They are `elinux` Dart plugins:
flutter-elinux registers them after the Linux ones, in Sailfish builds only.
Add the ones you use next to the plugin itself:

| Plugin | Sailfish package | Notes |
|---|---|---|
| path_provider | [path_provider_sailfish](../packages/path_provider_sailfish) | The app's Sailjail folders |
| shared_preferences | [shared_preferences_sailfish](../packages/shared_preferences_sailfish) | Kept in the app's data folder |
| flutter_secure_storage | [flutter_secure_storage_sailfish](../packages/flutter_secure_storage_sailfish) | A private file, not encrypted ([how safe](../packages/flutter_secure_storage_sailfish/README.md#how-safe-it-is)) |
| package_info_plus | [package_info_plus_sailfish](../packages/package_info_plus_sailfish) | Name and id from the desktop file |
| connectivity_plus | [connectivity_plus_sailfish](../packages/connectivity_plus_sailfish) | From ConnMan; needs the `Internet` permission |
| url_launcher | [url_launcher_sailfish](../packages/url_launcher_sailfish) | Opens links in other apps; needs runtime 7.sfos6 (patch 0013) |

## Sandboxing (Sailjail)

Apps run in Sailjail's sandbox, like native ones. The `[X-Sailjail]` section
of the desktop file says what the app may use:

```ini
[X-Sailjail]
Permissions=Internet;Pictures
OrganizationName=org.example
ApplicationName=MyFlutterApp
```

- `Permissions` lists what the app needs beyond the basics (display,
  keyboard, covers, dconf), e.g. `Internet`, `Audio`, `Pictures`, `Location`.
  The list is in [sailjail-permissions](https://github.com/sailfishos/sailjail-permissions#permissions).
  Leave it empty if the app needs none.
- The app can only write to `~/.local/share`, `~/.config` and `~/.cache`
  under `<OrganizationName>/<ApplicationName>`. Other files in the home
  folder aren't visible.
- There's no network without `Internet`, and the app can't run other
  programs: the sandbox's `/usr/bin` holds only the app.

The template already has the layout Sailjail expects: the app binary is
`/usr/bin/<name>`, its desktop file `/usr/share/applications/<name>.desktop`
and its files `/usr/share/<name>`. The binary is the Flutter runner itself,
not a script, because Sailjail only starts ELF binaries. It finds its bundle
in `/usr/share/<name>` and the runtime's libraries through its RPATH;
`LD_LIBRARY_PATH` doesn't reach sandboxed apps. Needs a `flutter-sfos`
runtime with patch 0012 (otherwise cut-outs and the pixel ratio are wrong in
the sandbox) and its `flutter-sfos-aot` (which sets the RPATH).

Started from a shell, `/usr/bin/<name>` runs outside the sandbox. To run it
sandboxed, with Sailjail's logs, see its
[debugging guide](https://github.com/sailfishos/sailjail/blob/master/APPDEBUG.md):
`sailjail --trace=<dir> -p <name>.desktop /usr/bin/<name>`.
