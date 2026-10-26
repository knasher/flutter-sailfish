/// Sailfish OS implementation of connectivity_plus.
library;

import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

/// connectivity_plus for Sailfish OS, from ConnMan.
///
/// The results are the types of ConnMan's connected services (state `ready`
/// or `online`), the one in use first, or `none`. Apps need the `Internet`
/// Sailjail permission, which lets them ask ConnMan.
class ConnectivityPlusSailfish extends ConnectivityPlatform {
  ConnectivityPlusSailfish() : this.withBus(DBusClient.system);

  /// Asks ConnMan on the bus [connect] returns instead of the system bus.
  @visibleForTesting
  ConnectivityPlusSailfish.withBus(this._connect);

  /// Registers this as the connectivity_plus implementation.
  static void registerWith() {
    ConnectivityPlatform.instance = ConnectivityPlusSailfish();
  }

  final DBusClient Function() _connect;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    final client = _connect();
    try {
      return await _connectivity(client);
    } finally {
      await client.close();
    }
  }

  late final _changes = StreamController<List<ConnectivityResult>>.broadcast(
    onListen: _listen,
    onCancel: _stopListening,
  );

  DBusClient? _client;
  final _signals = <StreamSubscription<DBusSignal>>[];
  Future<void> _updating = Future<void>.value();
  List<ConnectivityResult>? _last;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _changes.stream;

  // Sends the connectivity now, then again whenever ConnMan's state or a
  // service's state changes. Other changes, like signal strength, are ignored.
  void _listen() {
    final client = _client = _connect();
    for (final interface in ['net.connman.Manager', 'net.connman.Service']) {
      final signals = DBusSignalStream(
        client,
        sender: _connman,
        interface: interface,
        name: 'PropertyChanged',
        signature: DBusSignature('sv'),
      );
      _signals.add(
        signals.listen((signal) {
          if (signal.values.first.asString() == 'State') {
            _update(client);
          }
        }),
      );
    }
    _update(client);
  }

  // Asks one at a time, so the answers are sent in order, and only sends
  // ones that differ from the last.
  void _update(DBusClient client) {
    _updating = _updating.then((_) async {
      if (client != _client) {
        return;
      }
      try {
        final results = await _connectivity(client);
        if (client == _client && !listEquals(results, _last)) {
          _last = results;
          _changes.add(results);
        }
      } catch (error, stack) {
        if (client == _client) {
          _changes.addError(error, stack);
        }
      }
    });
  }

  Future<void> _stopListening() async {
    final client = _client;
    _client = null;
    _last = null;
    for (final signals in _signals) {
      await signals.cancel();
    }
    _signals.clear();
    await _updating;
    await client?.close();
  }
}

const _connman = 'net.connman';

// ConnMan's service types. Others (gadget, p2p) are `other`.
const _types = {
  'wifi': ConnectivityResult.wifi,
  'cellular': ConnectivityResult.mobile,
  'ethernet': ConnectivityResult.ethernet,
  'bluetooth': ConnectivityResult.bluetooth,
  'vpn': ConnectivityResult.vpn,
};

// ConnMan lists services in order of preference, so the one in use is first.
Future<List<ConnectivityResult>> _connectivity(DBusClient client) async {
  final reply = await client.callMethod(
    destination: _connman,
    path: DBusObjectPath('/'),
    interface: 'net.connman.Manager',
    name: 'GetServices',
    replySignature: DBusSignature('a(oa{sv})'),
  );
  final results = <ConnectivityResult>[];
  for (final service in reply.values.first.asArray()) {
    final properties = service.asStruct()[1].asStringVariantDict();
    final state = properties['State']?.asString();
    if (state != 'ready' && state != 'online') {
      continue;
    }
    final result =
        _types[properties['Type']?.asString()] ?? ConnectivityResult.other;
    if (!results.contains(result)) {
      results.add(result);
    }
  }
  return results.isEmpty ? [ConnectivityResult.none] : results;
}
