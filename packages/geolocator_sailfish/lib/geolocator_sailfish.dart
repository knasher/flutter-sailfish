/// Sailfish OS implementation of geolocator.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

/// geolocator for Sailfish OS, from GeoClue.
///
/// Positions come from Sailfish OS's GeoClue master, which picks the GPS or a
/// coarser source to suit the accuracy asked for. Apps need the `Location`
/// Sailjail permission. The user grants it when the app starts, so there's
/// nothing to ask for later: `requestPermission` only reports it.
class GeolocatorSailfish extends GeolocatorPlatform {
  GeolocatorSailfish()
    : this.withBus(DBusClient.session, settings: '/etc/location/location.conf');

  /// Asks GeoClue on the bus [connect] returns, and reads the location
  /// settings from [settings], instead of the real ones.
  @visibleForTesting
  GeolocatorSailfish.withBus(this._connect, {required String settings})
    : _settings = File(settings);

  /// Registers this as the geolocator implementation.
  static void registerWith() {
    GeolocatorPlatform.instance = GeolocatorSailfish();
  }

  final DBusClient Function() _connect;
  final File _settings;

  // Sailjail shows apps with the Location permission the location settings;
  // others have no /etc/location at all.
  @override
  Future<LocationPermission> checkPermission() async => await _settings.exists()
      ? LocationPermission.whileInUse
      : LocationPermission.deniedForever;

  @override
  Future<LocationPermission> requestPermission() => checkPermission();

  // The switch in Settings > Location. Without the permission the settings
  // can't be read, so this says yes and checkPermission says no.
  @override
  Future<bool> isLocationServiceEnabled() async {
    if (!await _settings.exists()) {
      return true;
    }
    return _locationEnabled(await _settings.readAsString());
  }

  // GeoClue keeps no last position for apps to read.
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => null;

  // The stream's own timeout, so that giving up also stops GeoClue.
  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) {
    var positions = _positions(
      locationSettings?.accuracy ?? LocationAccuracy.best,
    );
    final limit = locationSettings?.timeLimit;
    if (limit != null) {
      positions = positions.timeout(limit);
    }
    return positions.first;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    final distance = locationSettings?.distanceFilter ?? 0;
    Position? last;
    return _positions(
      locationSettings?.accuracy ?? LocationAccuracy.best,
    ).where((position) {
      if (last != null &&
          distanceBetween(
                last!.latitude,
                last!.longitude,
                position.latitude,
                position.longitude,
              ) <
              distance) {
        return false;
      }
      last = position;
      return true;
    });
  }

  // Only the status now: Sailjail gives apps a copy of the settings.
  @override
  Stream<ServiceStatus> getServiceStatusStream() => Stream.fromFuture(
    isLocationServiceEnabled().then(
      (enabled) => enabled ? ServiceStatus.enabled : ServiceStatus.disabled,
    ),
  );

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() async =>
      LocationAccuracyStatus.precise;

  // The sandbox can't open Settings.
  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;

  // Positions from a GeoClue master client for as long as they're listened
  // to, starting with the one it has now, if any.
  Stream<Position> _positions(LocationAccuracy accuracy) {
    late final StreamController<Position> positions;
    late final DBusClient bus;
    late final Future<void> started;
    DBusRemoteObject? client;
    StreamSubscription<DBusSignal>? changes;
    var referenced = false;

    Future<void> start() async {
      if (!await isLocationServiceEnabled()) {
        throw const LocationServiceDisabledException();
      }
      if (await checkPermission() == LocationPermission.deniedForever) {
        throw const PermissionDeniedException(
          'The app needs the Location Sailjail permission.',
        );
      }
      final master = DBusRemoteObject(
        bus,
        name: _service,
        path: DBusObjectPath('/org/freedesktop/Geoclue/Master'),
      );
      final created = await master.callMethod(
        'org.freedesktop.Geoclue.Master',
        'Create',
        const [],
        replySignature: DBusSignature('o'),
      );
      final c = client = DBusRemoteObject(
        bus,
        name: _service,
        path: created.values.first.asObjectPath(),
      );
      // Listening before starting, so no change is missed.
      changes =
          DBusRemoteObjectSignalStream(
            object: c,
            interface: _positionInterface,
            name: 'PositionChanged',
            signature: DBusSignature(_positionSignature),
          ).listen(
            (signal) => _send(positions, signal.values),
            onError: positions.addError,
          );
      await c.callMethod(_clientInterface, 'SetRequirements', [
        DBusInt32(_accuracyLevel(accuracy)),
        const DBusInt32(0), // no minimum time between updates
        const DBusBoolean(true), // updates wanted
        const DBusInt32(_allResources),
      ], replySignature: DBusSignature(''));
      await c.callMethod(
        _clientInterface,
        'PositionStart',
        const [],
        replySignature: DBusSignature(''),
      );
      await c.callMethod(
        _geoclueInterface,
        'AddReference',
        const [],
        replySignature: DBusSignature(''),
      );
      referenced = true;
      try {
        final now = await c.callMethod(
          _positionInterface,
          'GetPosition',
          const [],
          replySignature: DBusSignature(_positionSignature),
        );
        _send(positions, now.values);
      } on DBusMethodResponseException catch (error) {
        // No provider can give positions yet (the GPS has no fix). GeoClue
        // sends PositionChanged once one can.
        if (error.errorName != _notAvailable) {
          rethrow;
        }
      }
    }

    // Waits for start to finish, so a reference it took is given back.
    Future<void> stop() async {
      await started;
      await changes?.cancel();
      if (referenced) {
        try {
          await client!.callMethod(
            _geoclueInterface,
            'RemoveReference',
            const [],
            replySignature: DBusSignature(''),
          );
        } on DBusMethodResponseException {
          // GeoClue has gone, and with it the reference.
        }
      }
      await bus.close();
    }

    positions = StreamController<Position>(
      onListen: () {
        bus = _connect();
        started = start().catchError(positions.addError);
      },
      onCancel: stop,
    );
    return positions.stream;
  }
}

const _service = 'org.freedesktop.Geoclue.Master';
const _geoclueInterface = 'org.freedesktop.Geoclue';
const _clientInterface = 'org.freedesktop.Geoclue.MasterClient';
const _positionInterface = 'org.freedesktop.Geoclue.Position';
const _notAvailable = 'org.freedesktop.Geoclue.Error.notAvailable';

// fields, timestamp, latitude, longitude, altitude, (level, horizontal and
// vertical accuracy in metres).
const _positionSignature = 'iiddd(idd)';

// GeoClue's GEOCLUE_POSITION_FIELDS_* and GEOCLUE_RESOURCE_ALL.
const _latitudeField = 1;
const _longitudeField = 2;
const _altitudeField = 4;
const _allResources = (1 << 10) - 1;

// GeoClue's accuracy levels: country 1, locality 3, street 5, detailed 6.
int _accuracyLevel(LocationAccuracy accuracy) => switch (accuracy) {
  LocationAccuracy.lowest => 1,
  LocationAccuracy.low || LocationAccuracy.reduced => 3,
  LocationAccuracy.medium => 5,
  LocationAccuracy.high ||
  LocationAccuracy.best ||
  LocationAccuracy.bestForNavigation => 6,
};

// Sends a GeoClue position, if it has a latitude and longitude.
void _send(StreamController<Position> positions, List<DBusValue> values) {
  final fields = values[0].asInt32();
  if (fields & _latitudeField == 0 || fields & _longitudeField == 0) {
    return;
  }
  final seconds = values[1].asInt32();
  final accuracy = values[5].asStruct();
  final hasAltitude = fields & _altitudeField != 0;
  positions.add(
    Position(
      latitude: values[2].asDouble(),
      longitude: values[3].asDouble(),
      timestamp: seconds > 0
          ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true)
          : DateTime.now().toUtc(),
      accuracy: accuracy[1].asDouble(),
      altitude: hasAltitude ? values[4].asDouble() : 0,
      altitudeAccuracy: hasAltitude ? accuracy[2].asDouble() : 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    ),
  );
}

// `enabled` in the [location] group of location.conf.
bool _locationEnabled(String settings) {
  String? group;
  for (final raw in const LineSplitter().convert(settings)) {
    final line = raw.trim();
    if (line.startsWith('[') && line.endsWith(']')) {
      group = line;
      continue;
    }
    final equals = line.indexOf('=');
    if (group == '[location]' &&
        equals > 0 &&
        line.substring(0, equals).trim() == 'enabled') {
      return line.substring(equals + 1).trim() == 'true';
    }
  }
  return false;
}
