/// Sailfish OS implementation of shared_preferences.
library;

import 'package:flutter/foundation.dart';
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_sailfish/path_provider_sailfish.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// shared_preferences for Sailfish OS.
///
/// shared_preferences_linux's stores and JSON file, kept in the app's
/// Sailjail data folder (`~/.local/share/<org>/<app>`) instead of a folder
/// named after the binary, which Sailjail doesn't keep.
abstract final class SharedPreferencesSailfish {
  /// Registers the stores for `SharedPreferences` and
  /// `SharedPreferencesAsync`.
  static void registerWith() => registerWithPaths(PathProviderSailfish());

  /// Registers the stores, keeping their file in [paths]' support folder.
  @visibleForTesting
  static void registerWithPaths(PathProviderSailfish paths) {
    final folder = _SupportFolder(paths);
    // The Linux stores only take another folder through these test hooks.
    final store = SharedPreferencesLinux();
    // ignore: invalid_use_of_visible_for_testing_member
    store.pathProvider = folder;
    final asyncStore = SharedPreferencesAsyncLinux();
    // ignore: invalid_use_of_visible_for_testing_member
    asyncStore.pathProvider = folder;
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferencesAsyncPlatform.instance = asyncStore;
  }
}

// The only path the Linux stores ask for.
class _SupportFolder extends PathProviderLinux {
  _SupportFolder(this._paths);

  final PathProviderSailfish _paths;

  @override
  Future<String?> getApplicationSupportPath() =>
      _paths.getApplicationSupportPath();
}
