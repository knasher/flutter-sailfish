/// Sailfish OS implementation of url_launcher.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// url_launcher for Sailfish OS.
///
/// Links open in the app that handles their scheme (the browser for `https`,
/// Email for `mailto`, and so on), which the flutter-sfos runtime asks the
/// compositor to start, as Qt apps do. Whether an app handles a scheme comes
/// from the same `x-scheme-handler` entries the compositor uses. There are no
/// in-app web views.
class UrlLauncherSailfish extends UrlLauncherPlatform {
  UrlLauncherSailfish() : this.withDataDirs(_xdgDataDirs());

  /// Looks for scheme handlers in [dataDirs] instead of the XDG data folders.
  @visibleForTesting
  UrlLauncherSailfish.withDataDirs(this._dataDirs);

  /// Registers this as the url_launcher implementation.
  static void registerWith() {
    UrlLauncherPlatform.instance = UrlLauncherSailfish();
  }

  /// The runtime's channel; flutter-sfos 7.sfos6 and later have it.
  @visibleForTesting
  static const channel = MethodChannel(
    'flutter-sfos/open_url',
    JSONMethodCodec(),
  );

  final List<String> _dataDirs;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) => _hasHandler(url);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    // Only the browser opens web links on Sailfish OS.
    if (options.mode == PreferredLaunchMode.externalNonBrowserApplication &&
        (url.startsWith('http:') || url.startsWith('https:'))) {
      return false;
    }
    if (!await _hasHandler(url)) {
      return false;
    }
    try {
      return await channel.invokeMethod<bool>('openUrl', url) ?? false;
    } on MissingPluginException {
      throw PlatformException(
        code: 'unsupported',
        message:
            'This flutter-sfos runtime can\'t open links; it needs '
            '7.sfos6 or later.',
      );
    }
  }

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) => launchUrl(
    url,
    LaunchOptions(
      mode: universalLinksOnly
          ? PreferredLaunchMode.externalNonBrowserApplication
          : PreferredLaunchMode.externalApplication,
    ),
  );

  // Links open in other apps, so there's nothing to close.
  @override
  Future<void> closeWebView() async {}

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async =>
      mode == PreferredLaunchMode.platformDefault ||
      mode == PreferredLaunchMode.externalApplication ||
      mode == PreferredLaunchMode.externalNonBrowserApplication;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => false;

  // Whether an app is registered for the URL's scheme, in
  // applications/mimeapps.list or applications/mimeinfo.cache in a data
  // folder, as libcontentaction looks it up. Sailjail hides the user's own
  // ~/.local/share/applications, so in practice that's the system's.
  Future<bool> _hasHandler(String url) async {
    final scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
    if (scheme.isEmpty) {
      return false;
    }
    final key = 'x-scheme-handler/$scheme';
    for (final dir in _dataDirs) {
      for (final name in const ['mimeapps.list', 'mimeinfo.cache']) {
        final file = File('$dir/applications/$name');
        if (await file.exists() && _hasEntry(await file.readAsString(), key)) {
          return true;
        }
      }
    }
    return false;
  }
}

// Whether [key] lists an app in any group but [Removed Associations].
bool _hasEntry(String text, String key) {
  var removed = false;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      removed = line == '[Removed Associations]';
      continue;
    }
    final equals = line.indexOf('=');
    if (removed || equals < 0 || line.substring(0, equals).trim() != key) {
      continue;
    }
    if (line.substring(equals + 1).split(';').any((app) => app.isNotEmpty)) {
      return true;
    }
  }
  return false;
}

List<String> _xdgDataDirs() {
  final env = Platform.environment;
  final home = env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share';
  final dirs = env['XDG_DATA_DIRS'] ?? '/usr/local/share:/usr/share';
  return [home, ...dirs.split(':').where((dir) => dir.isNotEmpty)];
}
