/// Sailfish OS implementation of screen_brightness.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider_sailfish/path_provider_sailfish.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

/// screen_brightness for Sailfish OS, through MCE.
///
/// Sailfish OS has no brightness of an app's own, so application brightness
/// works as on iOS: it sets the phone's brightness, with automatic brightness
/// off, and puts the phone's settings back on reset, while the app is in the
/// background (unless auto reset is off) and, if the app was killed with them
/// changed, the next time it starts. A setting the user changes meanwhile is
/// left as they set it.
class ScreenBrightnessSailfish extends ScreenBrightnessPlatform
    with WidgetsBindingObserver {
  ScreenBrightnessSailfish()
    : this.withBus(
        DBusClient.system,
        folder: () => SailfishAppDirs.current().data,
      );

  /// Talks to MCE on the bus [connect] returns, and keeps the phone's
  /// settings in [folder], instead of the real ones.
  @visibleForTesting
  ScreenBrightnessSailfish.withBus(
    DBusClient Function() connect, {
    required String Function() folder,
  }) : _connect = connect,
       _folder = folder;

  /// Registers this as the screen_brightness implementation, and puts back
  /// the phone's settings if the app was last killed with them changed.
  static void registerWith() {
    final plugin = ScreenBrightnessSailfish();
    ScreenBrightnessPlatform.instance = plugin;
    unawaited(plugin.restoreSaved().catchError(_report));
  }

  final DBusClient Function() _connect;
  final String Function() _folder;

  late final DBusClient _bus = _connect();
  late final DBusRemoteObject _mce = DBusRemoteObject(
    _bus,
    name: _service,
    path: DBusObjectPath('/com/nokia/mce/request'),
  );

  // The phone's settings from before the app changed them, and the
  // brightness it set: {"brightness": 78, "autobrightness": true, "set": 100}.
  late final File _saved = File('${_folder()}/screen_brightness_sailfish.json');

  // The app's brightness, or null when it uses the phone's.
  double? _application;
  // Whether the app's brightness is on the phone now.
  var _applied = false;
  var _autoReset = true;
  var _animate = true;
  var _observing = false;
  final _applicationChanges = StreamController<double>.broadcast();
  Future<void> _previous = Future<void>.value();

  // Runs [action] after the previous one, so changes and restores don't mix.
  Future<T> _inTurn<T>(Future<T> Function() action) {
    final result = _previous.then((_) => action());
    _previous = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  Future<double> get system async => await _brightness() / 100;

  @override
  Future<void> setSystemScreenBrightness(double brightness) {
    _checkRange(brightness);
    return _inTurn(() => _set(_brightnessKey, DBusInt32(_level(brightness))));
  }

  @override
  Stream<double> get onSystemScreenBrightnessChanged =>
      DBusSignalStream(
            _bus,
            sender: _service,
            interface: 'com.nokia.mce.signal',
            name: 'config_change_ind',
            path: DBusObjectPath('/com/nokia/mce/signal'),
            signature: DBusSignature('sv'),
          )
          .where((signal) => signal.values[0].asString() == _brightnessKey)
          .map((signal) => signal.values[1].asVariant().asInt32() / 100);

  @override
  Future<double> get application async => _application ?? await system;

  @override
  Future<void> setApplicationScreenBrightness(double brightness) {
    _checkRange(brightness);
    return _inTurn(() async {
      _application = brightness;
      if (!_observing) {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      }
      await _apply();
      _applicationChanges.add(brightness);
    });
  }

  @override
  Future<void> resetApplicationScreenBrightness() => _inTurn(() async {
    _application = null;
    await _restore();
    _applicationChanges.add(await system);
  });

  @override
  Stream<double> get onApplicationScreenBrightnessChanged =>
      _applicationChanges.stream;

  @override
  Future<bool> get hasApplicationScreenBrightnessChanged async =>
      _application != null;

  @override
  Future<bool> get isAutoReset async => _autoReset;

  @override
  Future<void> setAutoReset(bool isAutoReset) async => _autoReset = isAutoReset;

  // MCE fades brightness changes itself.
  @override
  Future<bool> get isAnimate async => _animate;

  @override
  Future<void> setAnimate(bool isAnimate) async => _animate = isAnimate;

  @override
  Future<bool> get canChangeSystemBrightness async => true;

  // Auto reset: the phone's settings while the app is in the background,
  // the app's brightness again when it comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_autoReset || _application == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed when !_applied:
        unawaited(_inTurn(_apply).catchError(_report));
      case AppLifecycleState.hidden ||
              AppLifecycleState.paused ||
              AppLifecycleState.detached
          when _applied:
        unawaited(_inTurn(_restore).catchError(_report));
      default:
        break;
    }
  }

  /// Puts back the phone's settings saved by an earlier run, if any.
  @visibleForTesting
  Future<void> restoreSaved() => _inTurn(_restore);

  /// Closes the connection to MCE.
  @visibleForTesting
  Future<void> close() => _bus.close();

  // Saves the phone's settings, if not yet saved, then sets the app's
  // brightness with automatic brightness off.
  Future<void> _apply() async {
    final level = _level(_application!);
    final Map<String, Object?> saved;
    if (await _saved.exists()) {
      saved = jsonDecode(await _saved.readAsString()) as Map<String, Object?>;
    } else {
      saved = {
        'brightness': await _brightness(),
        'autobrightness': await _autobrightness(),
      };
    }
    await _saved.parent.create(recursive: true);
    await _saved.writeAsString(jsonEncode({...saved, 'set': level}));
    await _set(_autobrightnessKey, const DBusBoolean(false));
    await _set(_brightnessKey, DBusInt32(level));
    _applied = true;
  }

  // Puts back the saved settings, except any the user has changed since.
  Future<void> _restore() async {
    _applied = false;
    if (!await _saved.exists()) {
      return;
    }
    final saved = jsonDecode(await _saved.readAsString()) as Map;
    if (await _brightness() == saved['set']) {
      await _set(_brightnessKey, DBusInt32(saved['brightness'] as int));
    }
    if (!await _autobrightness()) {
      await _set(
        _autobrightnessKey,
        DBusBoolean(saved['autobrightness'] as bool),
      );
    }
    await _saved.delete();
  }

  Future<int> _brightness() async => (await _get(_brightnessKey)).asInt32();

  Future<bool> _autobrightness() async =>
      (await _get(_autobrightnessKey)).asBoolean();

  Future<DBusValue> _get(String key) async {
    final reply = await _mce.callMethod(_requestInterface, 'get_config', [
      DBusString(key),
    ], replySignature: DBusSignature('v'));
    return reply.values.first.asVariant();
  }

  Future<void> _set(String key, DBusValue value) async {
    final reply = await _mce.callMethod(_requestInterface, 'set_config', [
      DBusString(key),
      DBusVariant(value),
    ], replySignature: DBusSignature('b'));
    if (!reply.values.first.asBoolean()) {
      throw PlatformException(code: 'mce', message: 'MCE refused $key');
    }
  }
}

const _service = 'com.nokia.mce';
const _requestInterface = 'com.nokia.mce.request';
const _brightnessKey = '/system/osso/dsm/display/display_brightness';
const _autobrightnessKey = '/system/osso/dsm/display/als_autobrightness';

// MCE's brightness runs from 1 to 100.
int _level(double brightness) => (brightness * 100).round().clamp(1, 100);

void _checkRange(double brightness) {
  if (brightness < 0 || brightness > 1) {
    throw RangeError.range(brightness, 0, 1, 'brightness');
  }
}

void _report(Object error) =>
    debugPrint('screen_brightness_sailfish: couldn\'t restore: $error');
