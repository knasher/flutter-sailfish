/// Sailfish OS implementation of package_info_plus.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus_platform_interface/package_info_data.dart';
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';

/// package_info_plus for Sailfish OS.
///
/// - `appName` is `Name` from the app's desktop file, the name in the app
///   grid.
/// - `packageName` is `<OrganizationName>.<ApplicationName>` from the desktop
///   file's `[X-Sailjail]` section, the app's id on Sailfish OS. Apps without
///   those names get their binary name.
/// - `version` and `buildNumber` come from `version.json` in the app's
///   assets, which the build writes from `pubspec.yaml`.
/// - `installTime` and `updateTime` are when the app's binary was last
///   installed.
class PackageInfoPlusSailfish extends PackageInfoPlatform {
  PackageInfoPlusSailfish() : this.inRoot('');

  /// Reads the app's files under [root] instead of `/`.
  @visibleForTesting
  PackageInfoPlusSailfish.inRoot(this._root);

  /// Registers this as the package_info_plus implementation.
  static void registerWith() {
    PackageInfoPlatform.instance = PackageInfoPlusSailfish();
  }

  final String _root;

  @override
  Future<PackageInfoData> getAll({String? baseUrl}) async {
    final binary = await File('$_root/proc/self/exe').resolveSymbolicLinks();
    final binaryName = binary.substring(binary.lastIndexOf('/') + 1);
    final desktop = await _desktopFile(binaryName);
    final entry = desktop['Desktop Entry'] ?? const <String, String>{};
    final sailjail = desktop['X-Sailjail'] ?? const <String, String>{};
    final organization = sailjail['OrganizationName'] ?? '';
    final application = sailjail['ApplicationName'] ?? '';
    final version = await _versionJson(binaryName);
    // The binary's mtime is when it was built; its ctime is when RPM wrote it.
    final installed = (await File(binary).stat()).changed;
    return PackageInfoData(
      appName: entry['Name'] ?? binaryName,
      packageName: organization.isEmpty || application.isEmpty
          ? binaryName
          : '$organization.$application',
      version: version['version'] as String? ?? '',
      buildNumber: version['build_number'] as String? ?? '',
      buildSignature: '',
      installTime: installed,
      updateTime: installed,
    );
  }

  // `<binary name>.desktop` from where Sailjail reads it, as groups of keys.
  Future<Map<String, Map<String, String>>> _desktopFile(String name) async {
    for (final dir in const [
      '/usr/share/applications',
      '/etc/sailjail/applications',
    ]) {
      final file = File('$_root$dir/$name.desktop');
      if (await file.exists()) {
        return _parseDesktopFile(await file.readAsString());
      }
    }
    return const {};
  }

  // The app's bundle is /usr/share/<binary name>, where the runner looks for
  // it. Apps built before the build wrote version.json have none.
  Future<Map<String, dynamic>> _versionJson(String name) async {
    final file = File(
      '$_root/usr/share/$name/data/flutter_assets/version.json',
    );
    if (!await file.exists()) {
      return const {};
    }
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }
}

Map<String, Map<String, String>> _parseDesktopFile(String text) {
  final groups = <String, Map<String, String>>{};
  Map<String, String>? group;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      group = groups.putIfAbsent(line.substring(1, line.length - 1), () => {});
      continue;
    }
    final equals = line.indexOf('=');
    if (group != null && equals > 0) {
      final key = line.substring(0, equals).trim();
      group[key] = line.substring(equals + 1).trim();
    }
  }
  return groups;
}
