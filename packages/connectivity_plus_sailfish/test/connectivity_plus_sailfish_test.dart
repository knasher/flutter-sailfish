import 'dart:io';

import 'package:async/async.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:connectivity_plus_sailfish/connectivity_plus_sailfish.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';

// ConnMan's manager object, with services as path -> {Type, State}, in
// ConnMan's order.
class _ConnMan extends DBusObject {
  _ConnMan() : super(DBusObjectPath('/'));

  final services = <String, Map<String, String>>{};

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'net.connman.Manager' || call.name != 'GetServices') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse([
      DBusArray(DBusSignature('(oa{sv})'), [
        for (final MapEntry(key: path, value: properties) in services.entries)
          DBusStruct([
            DBusObjectPath(path),
            DBusDict.stringVariant({
              for (final MapEntry(:key, :value) in properties.entries)
                key: DBusString(value),
            }),
          ]),
      ]),
    ]);
  }
}

void main() {
  late DBusServer server;
  late DBusAddress address;
  late DBusClient connmanBus;
  late _ConnMan connman;
  late ConnectivityPlusSailfish connectivity;

  // The server doesn't check the uid, and dbus can't look it up on macOS.
  DBusClient connect() =>
      DBusClient(address, authClient: DBusAuthClient(uid: '0'));

  // Sets a service's state, then sends ConnMan's PropertyChanged signal.
  Future<void> setState(String path, String state) async {
    connman.services[path]!['State'] = state;
    await connmanBus.emitSignal(
      path: DBusObjectPath(path),
      interface: 'net.connman.Service',
      name: 'PropertyChanged',
      values: [DBusString('State'), DBusVariant(DBusString(state))],
    );
  }

  // Gives the plugin time to act on a signal it should ignore, so a mistake
  // shows up as an extra result.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  setUp(() async {
    server = DBusServer();
    address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    connmanBus = connect();
    connman = _ConnMan();
    await connmanBus.requestName('net.connman');
    await connmanBus.registerObject(connman);
    connectivity = ConnectivityPlusSailfish.withBus(connect);
  });
  tearDown(() async {
    await connmanBus.close();
    await server.close();
  });

  test('registers itself', () {
    ConnectivityPlusSailfish.registerWith();
    expect(ConnectivityPlatform.instance, isA<ConnectivityPlusSailfish>());
  });

  test('lists connected service types, the one in use first', () async {
    connman.services.addAll({
      '/net/connman/service/cellular_1': {'Type': 'cellular', 'State': 'ready'},
      '/net/connman/service/wifi_1': {'Type': 'wifi', 'State': 'online'},
      '/net/connman/service/wifi_2': {'Type': 'wifi', 'State': 'idle'},
      '/net/connman/service/vpn_1': {'Type': 'vpn', 'State': 'ready'},
      '/net/connman/service/gadget_1': {'Type': 'gadget', 'State': 'online'},
      '/net/connman/service/ethernet_1': {
        'Type': 'ethernet',
        'State': 'failure',
      },
    });
    expect(await connectivity.checkConnectivity(), [
      ConnectivityResult.mobile,
      ConnectivityResult.wifi,
      ConnectivityResult.vpn,
      ConnectivityResult.other,
    ]);
  });

  test('is none with nothing connected', () async {
    connman.services['/net/connman/service/wifi_1'] = {
      'Type': 'wifi',
      'State': 'idle',
    };
    expect(await connectivity.checkConnectivity(), [ConnectivityResult.none]);
  });

  test('sends the connectivity, then each change', () async {
    const wifi = '/net/connman/service/wifi_1';
    connman.services[wifi] = {'Type': 'wifi', 'State': 'online'};
    final changes = StreamQueue(connectivity.onConnectivityChanged);
    expect(await changes.next, [ConnectivityResult.wifi]);

    await setState(wifi, 'disconnect');
    expect(await changes.next, [ConnectivityResult.none]);

    // Unchanged results aren't sent again.
    await setState(wifi, 'idle');
    await settle();
    await setState(wifi, 'association');
    await settle();
    await setState(wifi, 'ready');
    expect(await changes.next, [ConnectivityResult.wifi]);

    await changes.cancel();
  });

  test('ignores changes other than states', () async {
    const wifi = '/net/connman/service/wifi_1';
    connman.services[wifi] = {'Type': 'wifi', 'State': 'online'};
    final changes = StreamQueue(connectivity.onConnectivityChanged);
    expect(await changes.next, [ConnectivityResult.wifi]);

    // Changed without a State signal, so [none] is never noticed: only
    // [mobile], after ConnMan's own State signal.
    connman.services[wifi]!['State'] = 'idle';
    await connmanBus.emitSignal(
      path: DBusObjectPath(wifi),
      interface: 'net.connman.Service',
      name: 'PropertyChanged',
      values: [DBusString('Strength'), DBusVariant(DBusByte(40))],
    );
    await settle();
    connman.services['/net/connman/service/cellular_1'] = {
      'Type': 'cellular',
      'State': 'online',
    };
    await connmanBus.emitSignal(
      path: DBusObjectPath('/'),
      interface: 'net.connman.Manager',
      name: 'PropertyChanged',
      values: [DBusString('State'), DBusVariant(DBusString('online'))],
    );
    expect(await changes.next, [ConnectivityResult.mobile]);

    await changes.cancel();
  });

  test('listens again after every listener has gone', () async {
    const wifi = '/net/connman/service/wifi_1';
    connman.services[wifi] = {'Type': 'wifi', 'State': 'online'};
    final first = StreamQueue(connectivity.onConnectivityChanged);
    expect(await first.next, [ConnectivityResult.wifi]);
    await first.cancel();

    await setState(wifi, 'idle');
    final second = StreamQueue(connectivity.onConnectivityChanged);
    expect(await second.next, [ConnectivityResult.none]);
    await second.cancel();
  });
}
