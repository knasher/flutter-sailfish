# shared_preferences_sailfish

Sailfish OS implementation of [shared_preferences](https://pub.dev/packages/shared_preferences).
Not published on pub.dev yet.

Without it, Sailfish apps use `shared_preferences_linux`, which keeps its file
in a folder named after the binary. Sailjail doesn't keep that folder for apps
that declare their own names, so preferences would be lost when the app
closes.

Add it next to `shared_preferences`; it registers itself:

```yaml
dependencies:
  shared_preferences: ^2.5.5
  shared_preferences_sailfish:
    git:
      url: https://github.com/knasher/flutter-sailfish.git
      path: packages/shared_preferences_sailfish
```

It uses shared_preferences_linux's stores, for both `SharedPreferences` and
`SharedPreferencesAsync`, with their file (`shared_preferences.json`) in the
app's Sailjail data folder, `~/.local/share/<org>/<app>`, from
[path_provider_sailfish](../path_provider_sailfish).
