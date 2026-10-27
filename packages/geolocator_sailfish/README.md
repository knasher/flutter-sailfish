# geolocator_sailfish

Sailfish OS implementation of
[geolocator](https://pub.dev/packages/geolocator).
Not published on pub.dev yet.

Without it, Sailfish apps use `geolocator_linux`, which asks GeoClue 2.
Sailfish OS has the older GeoClue (0.12) instead, with Jolla's GPS and
cell-based providers, so it failed.

The flutter-sailfish build adds it to apps that use `geolocator`, so there's
nothing to add (runtime 7.sfos8 and later). To use another copy, or with an
older runtime, list it next to `geolocator`; the build then uses yours:

```yaml
dependencies:
  geolocator: ^14.0.2
  geolocator_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/geolocator_sailfish
```

The app needs the `Location` Sailjail permission:

```ini
[X-Sailjail]
Permissions=Internet;Location
```

| Call | On Sailfish OS |
| --- | --- |
| `checkPermission`, `requestPermission` | `whileInUse` with the `Location` permission, otherwise `deniedForever`. Sailjail asks the user when the app starts, so there's nothing to request later. |
| `isLocationServiceEnabled` | The switch in Settings > Location |
| `getCurrentPosition`, `getPositionStream` | From GeoClue's master, which picks the GPS or a coarser source to suit the accuracy asked for. Time limits and distance filters work as elsewhere. |
| `getLastKnownPosition` | `null`: GeoClue keeps none for apps |
| `getServiceStatusStream` | Only the status when you listen |
| `openAppSettings`, `openLocationSettings` | `false`: sandboxed apps can't open Settings |

Speed and heading aren't filled in yet.
