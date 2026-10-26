# flutter_secure_storage_sailfish

Sailfish OS implementation of
[flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage).
Not published on pub.dev yet.

Without it, `flutter_secure_storage` doesn't work on Sailfish OS: its Linux
version is native code built on libsecret (GNOME Keyring), which Sailfish
doesn't have.

Add it next to `flutter_secure_storage`; it registers itself:

```yaml
dependencies:
  flutter_secure_storage: ^10.3.1
  flutter_secure_storage_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/flutter_secure_storage_sailfish
```

## How safe it is

This first version keeps values in a private file, not in a keyring:
`flutter_secure_storage.json` in the app's Sailjail data folder,
`~/.local/share/<org>/<app>` (from
[path_provider_sailfish](../path_provider_sailfish)).

- Other sandboxed apps can't see it: Sailjail hides every other app's folders.
- Only the user can read it (mode 0600), and it is replaced in one step, so
  it is never left half written.
- It is **not encrypted** beyond the phone's own storage encryption, and
  programs running outside the sandbox as the user, or as root, can read it.

That is roughly an Android app's private files without the Android Keystore.
Sailfish OS's own secret store, Sailfish Secrets, may replace the file later;
it isn't installed on every phone, so apps would need to depend on it. Options
passed to `flutter_secure_storage` (iOS, Android and so on) are ignored.
