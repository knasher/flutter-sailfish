import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'sailfish_app_dirs.dart';

/// path_provider for Sailfish OS: the app's Sailjail folders.
///
/// - Application support and documents: `~/.local/share/<org>/<app>`.
/// - Application cache and temporary: `~/.cache/<org>/<app>` (as on Android,
///   where the temporary folder is the cache folder).
/// - Downloads: `~/Downloads` (the app needs the Downloads permission).
///
/// Library and external storage folders don't exist on Sailfish OS.
class PathProviderSailfish extends PathProviderPlatform {
  PathProviderSailfish() : this.withDirs(SailfishAppDirs.current);

  @visibleForTesting
  PathProviderSailfish.withDirs(SailfishAppDirs Function() dirs)
    : _findDirs = dirs;

  final SailfishAppDirs Function() _findDirs;

  // Found on first use, so registering reads no files.
  late final SailfishAppDirs _dirs = _findDirs();

  /// Registers this as the path_provider implementation.
  static void registerWith() {
    PathProviderPlatform.instance = PathProviderSailfish();
  }

  @override
  Future<String?> getTemporaryPath() => _created(_dirs.cache);

  @override
  Future<String?> getApplicationSupportPath() => _created(_dirs.data);

  @override
  Future<String?> getApplicationDocumentsPath() => _created(_dirs.data);

  @override
  Future<String?> getApplicationCachePath() => _created(_dirs.cache);

  @override
  Future<String?> getDownloadsPath() async => '${_dirs.home}/Downloads';

  // Sailjail creates these folders for sandboxed apps; create them for apps
  // run outside it.
  Future<String> _created(String path) async {
    await Directory(path).create(recursive: true);
    return path;
  }
}
