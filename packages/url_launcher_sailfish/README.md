# url_launcher_sailfish

Sailfish OS implementation of
[url_launcher](https://pub.dev/packages/url_launcher).
Not published on pub.dev yet.

Without it, Sailfish apps use `url_launcher_linux`, whose native GTK code
isn't built for Sailfish OS, so links didn't open. Sailjail's sandbox has no
`xdg-open` either.

The flutter-sailfish build adds it to apps that use `url_launcher`, so
there's nothing to add (runtime 7.sfos8 and later). To use another copy, or
with an older runtime, list it next to `url_launcher`; the build then uses
yours:

```yaml
dependencies:
  url_launcher: ^6.3.2
  url_launcher_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/url_launcher_sailfish
```

Links open in the app that handles their scheme: the browser for `http` and
`https`, Email for `mailto`, Phone for `tel`, Messages for `sms`. The
flutter-sfos runtime asks Lipstick to open them over Wayland, as Qt apps do,
so no Sailjail permission is needed. It needs runtime 7.sfos6 or later;
older ones make `launchUrl` throw a `PlatformException`.

- `canLaunchUrl` is true when an app is registered for the scheme
  (`x-scheme-handler/<scheme>` in the system's `mimeinfo.cache`), the same
  check Lipstick makes. `launchUrl` returns false for the others, such as
  `geo:` on a phone without a maps app.
- There are no in-app web views: `LaunchMode.inAppWebView` and
  `inAppBrowserView` open the browser instead, and `supportsLaunchMode` says
  so.
- `LaunchMode.externalNonBrowserApplication` never opens web links, since
  only the browser handles them on Sailfish OS.
