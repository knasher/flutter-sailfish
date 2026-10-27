import 'dart:io';

import 'package:async/async.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';
import 'package:screen_brightness_sailfish/screen_brightness_sailfish.dart';

const _brightness = '/system/osso/dsm/display/display_brightness';
const _auto = '/system/osso/dsm/display/als_autobrightness';

// MCE's settings, which announces each change as config_change_ind.
class _Mce extends DBusObject {
  _Mce(this.bus) : super(DBusObjectPath('/com/nokia/mce/request'));

  final DBusClient bus;
  final config = <String, DBusValue>{
    _brightness: const DBusInt32(78),
    _auto: const DBusBoolean(true),
  };

  Future<void> change(String key, DBusValue value) async {
    config[key] = value;
    await bus.emitSignal(
      path: DBusObjectPath('/com/nokia/mce/signal'),
      interface: 'com.nokia.mce.signal',
      name: 'config_change_ind',
      values: [DBusString(key), DBusVariant(value)],
    );
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    final key = call.values[0].asString();
    switch ((call.interface, call.name)) {
      case ('com.nokia.mce.request', 'get_config'):
        return DBusMethodSuccessResponse([DBusVariant(config[key]!)]);
      case ('com.nokia.mce.request', 'set_config'):
        await change(key, call.values[1].asVariant());
        return DBusMethodSuccessResponse([const DBusBoolean(true)]);
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late File saved;
  late DBusServer server;
  late DBusAddress address;
  late DBusClient mceBus;
  late _Mce mce;
  late ScreenBrightnessSailfish plugin;

  // The server doesn't check the uid, and dbus can't look it up on macOS.
  DBusClient connect() =>
      DBusClient(address, authClient: DBusAuthClient(uid: '0'));

  ScreenBrightnessSailfish newPlugin() =>
      ScreenBrightnessSailfish.withBus(connect, folder: () => temp.path);

  int brightness() => mce.config[_brightness]!.asInt32();
  bool auto() => mce.config[_auto]!.asBoolean();

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('screen_brightness_sailfish');
    saved = File('${temp.path}/screen_brightness_sailfish.json');
    server = DBusServer();
    address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    mceBus = connect();
    mce = _Mce(mceBus);
    await mceBus.requestName('com.nokia.mce');
    await mceBus.registerObject(mce);
    plugin = newPlugin();
  });
  tearDown(() async {
    WidgetsBinding.instance.removeObserver(plugin);
    await plugin.close();
    await mceBus.close();
    await server.close();
    temp.deleteSync(recursive: true);
  });

  test('registers itself', () async {
    // Its check for saved settings can't find the app here, and says so.
    ScreenBrightnessSailfish.registerWith();
    expect(ScreenBrightnessPlatform.instance, isA<ScreenBrightnessSailfish>());
    await settle();
  });

  test('reads, sets and follows the phone\'s brightness', () async {
    expect(await plugin.system, 0.78);
    final changes = StreamQueue(plugin.onSystemScreenBrightnessChanged);
    final set = changes.next; // starts listening
    await settle();

    await plugin.setSystemScreenBrightness(0.5);
    expect(brightness(), 50);
    expect(await set, 0.5);

    await mce.change(_brightness, const DBusInt32(20)); // from Settings
    expect(await changes.next, 0.2);
    await changes.cancel();

    expect(() => plugin.setSystemScreenBrightness(1.5), throwsRangeError);
    expect(auto(), isTrue);
  });

  test('sets the app\'s brightness and puts the phone\'s back', () async {
    final changes = StreamQueue(plugin.onApplicationScreenBrightnessChanged);
    await plugin.setApplicationScreenBrightness(1);
    expect(brightness(), 100);
    expect(auto(), isFalse);
    expect(await plugin.application, 1);
    expect(await plugin.hasApplicationScreenBrightnessChanged, isTrue);
    expect(saved.existsSync(), isTrue);
    expect(await changes.next, 1);

    await plugin.resetApplicationScreenBrightness();
    expect(brightness(), 78);
    expect(auto(), isTrue);
    expect(await plugin.application, 0.78);
    expect(await plugin.hasApplicationScreenBrightnessChanged, isFalse);
    expect(saved.existsSync(), isFalse);
    expect(await changes.next, 0.78);
    await changes.cancel();
  });

  test('keeps what the user changed meanwhile', () async {
    await plugin.setApplicationScreenBrightness(0.9);
    await plugin.setApplicationScreenBrightness(1); // saved settings kept
    await mce.change(_brightness, const DBusInt32(40));

    await plugin.resetApplicationScreenBrightness();
    expect(brightness(), 40);
    expect(auto(), isTrue);

    await plugin.setApplicationScreenBrightness(1);
    await mce.change(_auto, const DBusBoolean(true));
    await plugin.resetApplicationScreenBrightness();
    expect(brightness(), 40);
    expect(auto(), isTrue);
  });

  test('puts the phone\'s settings back while in the background', () async {
    await plugin.setApplicationScreenBrightness(1);

    plugin.didChangeAppLifecycleState(AppLifecycleState.hidden);
    plugin.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    expect(brightness(), 78);
    expect(auto(), isTrue);
    expect(await plugin.application, 1);

    plugin.didChangeAppLifecycleState(AppLifecycleState.hidden);
    plugin.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle();
    expect(brightness(), 100);
    expect(auto(), isFalse);
  });

  test('leaves the app\'s brightness without auto reset', () async {
    await plugin.setAutoReset(false);
    expect(await plugin.isAutoReset, isFalse);
    await plugin.setApplicationScreenBrightness(1);

    plugin.didChangeAppLifecycleState(AppLifecycleState.paused);
    await settle();
    expect(brightness(), 100);
  });

  test('puts back settings left by a killed app', () async {
    await plugin.setApplicationScreenBrightness(1);
    expect(brightness(), 100);

    // The app was killed; the next run restores at registration.
    final next = newPlugin();
    await next.restoreSaved();
    expect(brightness(), 78);
    expect(auto(), isTrue);
    expect(saved.existsSync(), isFalse);
    await next.close();
  });
}
