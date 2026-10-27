# package_info_plus_sailfish

Sailfish OS implementation of
[package_info_plus](https://pub.dev/packages/package_info_plus).
Not published on pub.dev yet.

Without it, Sailfish apps use package_info_plus's Linux version, which looks
for the app's version next to its binary. Sailfish apps keep the binary in
`/usr/bin` and everything else in `/usr/share/<app>`, so the version came
back empty.

The flutter-sailfish build adds it to apps that use `package_info_plus`, so
there's nothing to add (runtime 7.sfos8 and later). To use another copy, or
with an older runtime, list it next to `package_info_plus`; the build then
uses yours:

```yaml
dependencies:
  package_info_plus: ^9.0.1
  package_info_plus_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/package_info_plus_sailfish
```

| Field | On Sailfish OS |
| --- | --- |
| `appName` | `Name` from the app's desktop file: the name in the app grid, like Android's label |
| `packageName` | `<OrganizationName>.<ApplicationName>` from the desktop file's `[X-Sailjail]` section, like an Android or iOS id (the binary name if they're missing) |
| `version`, `buildNumber` | From `pubspec.yaml`, as on other platforms |
| `installTime`, `updateTime` | When the app was last installed |
| `buildSignature` | Empty |
| `installerStore` | `null` |

`version` and `buildNumber` need an app built with flutter-sailfish's
`flutter-elinux` patch, which writes `version.json` into the app's assets as
Linux builds do. Older builds give empty strings. `appName` isn't translated
(`Name[fi]` and the like are ignored).
