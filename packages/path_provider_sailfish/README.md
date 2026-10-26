# path_provider_sailfish

Sailfish OS implementation of [path_provider](https://pub.dev/packages/path_provider).
Not published on pub.dev yet.

Without it, Sailfish apps use `path_provider_linux`, whose folders don't fit
Sailfish: it looks up the user's Documents folder with a program the sandbox
doesn't have, and its other folders, named after the binary, aren't kept by
Sailjail for apps that declare their own names.

Add it next to `path_provider`; it registers itself:

```yaml
dependencies:
  path_provider: ^2.1.5
  path_provider_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/path_provider_sailfish
```

| path_provider | Sailfish OS folder |
|---|---|
| `getApplicationSupportDirectory` | `~/.local/share/<org>/<app>` |
| `getApplicationDocumentsDirectory` | `~/.local/share/<org>/<app>` |
| `getApplicationCacheDirectory` | `~/.cache/<org>/<app>` |
| `getTemporaryDirectory` | `~/.cache/<org>/<app>` |
| `getDownloadsDirectory` | `~/Downloads` (needs the `Downloads` permission) |

`<org>/<app>` are `OrganizationName` and `ApplicationName` from the
`[X-Sailjail]` section of the app's desktop file
(`/usr/share/applications/<binary>.desktop`), the only folders Sailjail lets a
sandboxed app write to. Apps without them get folders named after the binary,
as Sailjail's default profile does. The library and external storage folders
don't exist on Sailfish OS.

Other Sailfish packages can use the same folders through `SailfishAppDirs`.

It is an `elinux` Dart plugin: flutter-elinux registers it after Flutter has
registered the Linux plugins, so it replaces `path_provider_linux` in
Sailfish builds only.
