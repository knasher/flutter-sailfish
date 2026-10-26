import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// The folders a Sailfish OS app can write to.
///
/// In Sailjail's sandbox an app can only write to `~/.local/share`,
/// `~/.config` and `~/.cache` under `<OrganizationName>/<ApplicationName>`,
/// which come from the `[X-Sailjail]` section of the app's desktop file. Apps
/// without those names get folders named after their binary, as Sailjail's
/// default profile does.
class SailfishAppDirs {
  @visibleForTesting
  const SailfishAppDirs({required this.home, required this.name});

  /// The folders of the running app.
  ///
  /// The desktop file is `<binary name>.desktop` in `/usr/share/applications`
  /// or `/etc/sailjail/applications`, the places Sailjail reads it from.
  factory SailfishAppDirs.current() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is not set');
    }
    final exe = File('/proc/self/exe').resolveSymbolicLinksSync();
    return SailfishAppDirs.resolve(
      home: home,
      binaryName: exe.substring(exe.lastIndexOf('/') + 1),
    );
  }

  /// The folders for [binaryName], from its desktop file in [desktopDirs].
  @visibleForTesting
  factory SailfishAppDirs.resolve({
    required String home,
    required String binaryName,
    List<String> desktopDirs = const [
      '/usr/share/applications',
      '/etc/sailjail/applications',
    ],
  }) {
    for (final dir in desktopDirs) {
      final file = File('$dir/$binaryName.desktop');
      if (file.existsSync()) {
        final name = sailjailName(file.readAsStringSync());
        if (name != null) {
          return SailfishAppDirs(home: home, name: name);
        }
      }
    }
    return SailfishAppDirs(home: home, name: binaryName);
  }

  /// The user's home folder.
  final String home;

  /// `<OrganizationName>/<ApplicationName>`, or the binary name.
  final String name;

  /// `~/.local/share/<name>`: the app's own data.
  String get data => '$home/.local/share/$name';

  /// `~/.config/<name>`: the app's settings.
  String get config => '$home/.config/$name';

  /// `~/.cache/<name>`: data the app can download or make again.
  String get cache => '$home/.cache/$name';

  /// `<OrganizationName>/<ApplicationName>` from a desktop file's
  /// `[X-Sailjail]` section, or null if either is missing.
  @visibleForTesting
  static String? sailjailName(String desktopFile) {
    String? section;
    String? organization;
    String? application;
    for (final raw in const LineSplitter().convert(desktopFile)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1);
        continue;
      }
      final equals = line.indexOf('=');
      if (section != 'X-Sailjail' || equals < 0) {
        continue;
      }
      final value = line.substring(equals + 1).trim();
      switch (line.substring(0, equals).trim()) {
        case 'OrganizationName':
          organization = value;
        case 'ApplicationName':
          application = value;
      }
    }
    if (organization == null ||
        organization.isEmpty ||
        application == null ||
        application.isEmpty) {
      return null;
    }
    return '$organization/$application';
  }
}
