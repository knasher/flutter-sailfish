import 'dart:async';
import 'dart:io';

import 'package:async/async.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:geolocator_sailfish/geolocator_sailfish.dart';

// A GeoClue position: fields, timestamp, latitude, longitude, altitude and
// (level, horizontal, vertical) accuracy.
List<DBusValue> _fix(double latitude, double longitude, {double? altitude}) => [
  DBusInt32(altitude == null ? 3 : 7),
  const DBusInt32(1761555600),
  DBusDouble(latitude),
  DBusDouble(longitude),
  DBusDouble(altitude ?? double.nan),
  DBusStruct([const DBusInt32(6), const DBusDouble(12), const DBusDouble(20)]),
];

final _noFix = [
  const DBusInt32(0),
  const DBusInt32(0),
  const DBusDouble(double.nan),
  const DBusDouble(double.nan),
  const DBusDouble(double.nan),
  DBusStruct([const DBusInt32(0), const DBusDouble(0), const DBusDouble(0)]),
];

// A GeoClue master client. Until a provider can give positions (null),
// GetPosition fails with notAvailable, as GeoClue's does.
class _Client extends DBusObject {
  _Client(String path) : super(DBusObjectPath(path));

  int? level;
  var started = false;
  var references = 0;
  List<DBusValue>? position;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    switch ((call.interface, call.name)) {
      case ('org.freedesktop.Geoclue.MasterClient', 'SetRequirements'):
        level = call.values[0].asInt32();
      case ('org.freedesktop.Geoclue.MasterClient', 'PositionStart'):
        started = true;
      case ('org.freedesktop.Geoclue', 'AddReference'):
        references++;
      case ('org.freedesktop.Geoclue', 'RemoveReference'):
        references--;
      case ('org.freedesktop.Geoclue.Position', 'GetPosition'):
        final now = position;
        return now == null
            ? DBusMethodErrorResponse(
                'org.freedesktop.Geoclue.Error.notAvailable',
                [
                  const DBusString(
                    'Geoclue master client has no usable Position providers',
                  ),
                ],
              )
            : DBusMethodSuccessResponse(now);
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }
}

// The GeoClue master, which makes a client for each Create.
class _Master extends DBusObject {
  _Master(this.bus) : super(DBusObjectPath('/org/freedesktop/Geoclue/Master'));

  final DBusClient bus;
  final clients = <_Client>[];
  List<DBusValue>? position;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.interface != 'org.freedesktop.Geoclue.Master' ||
        call.name != 'Create') {
      return DBusMethodErrorResponse.unknownMethod();
    }
    final client = _Client('${path.value}/client${clients.length}')
      ..position = position;
    clients.add(client);
    await bus.registerObject(client);
    return DBusMethodSuccessResponse([client.path]);
  }
}

void main() {
  late Directory temp;
  late File settings;
  late DBusServer server;
  late DBusAddress address;
  late DBusClient geoclueBus;
  late _Master master;
  late GeolocatorSailfish geolocator;

  // The server doesn't check the uid, and dbus can't look it up on macOS.
  DBusClient connect() =>
      DBusClient(address, authClient: DBusAuthClient(uid: '0'));

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue);
  }

  // Sends a position from the newest client, once it's listening.
  Future<void> send(List<DBusValue> position) async {
    await until(() => master.clients.lastOrNull?.references == 1);
    await geoclueBus.emitSignal(
      path: master.clients.last.path,
      interface: 'org.freedesktop.Geoclue.Position',
      name: 'PositionChanged',
      values: position,
    );
  }

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('geolocator_sailfish');
    settings = File('${temp.path}/location.conf')
      ..writeAsStringSync('''
[location]
agreement_accepted=true
enabled=true
gps\\enabled=true
''');
    server = DBusServer();
    address = await server.listenAddress(
      DBusAddress.unix(dir: Directory.systemTemp),
    );
    geoclueBus = connect();
    master = _Master(geoclueBus);
    await geoclueBus.requestName('org.freedesktop.Geoclue.Master');
    await geoclueBus.registerObject(master);
    geolocator = GeolocatorSailfish.withBus(connect, settings: settings.path);
  });
  tearDown(() async {
    await geoclueBus.close();
    await server.close();
    temp.deleteSync(recursive: true);
  });

  test('registers itself', () {
    GeolocatorSailfish.registerWith();
    expect(GeolocatorPlatform.instance, isA<GeolocatorSailfish>());
  });

  test('has permission when Sailjail shows the settings', () async {
    expect(await geolocator.checkPermission(), LocationPermission.whileInUse);
    expect(await geolocator.requestPermission(), LocationPermission.whileInUse);

    settings.deleteSync();
    expect(
      await geolocator.checkPermission(),
      LocationPermission.deniedForever,
    );
    expect(
      await geolocator.requestPermission(),
      LocationPermission.deniedForever,
    );
  });

  test('reads the location switch', () async {
    expect(await geolocator.isLocationServiceEnabled(), isTrue);

    settings.writeAsStringSync('[location]\nenabled=false\n');
    expect(await geolocator.isLocationServiceEnabled(), isFalse);

    // Unreadable without the permission, so left to checkPermission.
    settings.deleteSync();
    expect(await geolocator.isLocationServiceEnabled(), isTrue);
  });

  test('gives the position GeoClue has now', () async {
    master.position = _fix(51.5072, -0.1276, altitude: 35);
    final position = await geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
      ),
    );
    expect(position.latitude, 51.5072);
    expect(position.longitude, -0.1276);
    expect(position.altitude, 35);
    expect(position.accuracy, 12);
    expect(position.altitudeAccuracy, 20);
    expect(position.timestamp, DateTime.utc(2025, 10, 27, 9));

    final client = master.clients.single;
    expect(client.level, 5);
    expect(client.started, isTrue);
    await until(() => client.references == 0);
  });

  test('waits for a position with a latitude and longitude', () async {
    final position = geolocator.getCurrentPosition();
    await send(_noFix);
    await send(_fix(53.4808, -2.2426));
    expect((await position).latitude, 53.4808);
    expect((await position).altitude, 0);
    expect(master.clients.single.level, 6);
    await until(() => master.clients.single.references == 0);
  });

  test('waits when GeoClue has a provider but no fix yet', () async {
    master.position = _noFix;
    final position = geolocator.getCurrentPosition();
    await send(_fix(53.4808, -2.2426));
    expect((await position).longitude, -2.2426);
  });

  test('gives up after the time limit and stops GeoClue', () async {
    await expectLater(
      geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(milliseconds: 200),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
    await until(() => master.clients.single.references == 0);
  });

  test('refuses when location is off or not permitted', () async {
    settings.writeAsStringSync('[location]\nenabled=false\n');
    await expectLater(
      geolocator.getCurrentPosition(),
      throwsA(isA<LocationServiceDisabledException>()),
    );

    settings.deleteSync();
    await expectLater(
      geolocator.getCurrentPosition(),
      throwsA(isA<PermissionDeniedException>()),
    );
    expect(master.clients, isEmpty);
  });

  test('streams positions beyond the distance filter', () async {
    final positions = StreamQueue(
      geolocator.getPositionStream(
        locationSettings: const LocationSettings(distanceFilter: 100),
      ),
    );
    final first = positions.next;
    await send(_fix(51.5072, -0.1276));
    expect((await first).latitude, 51.5072);

    await send(_fix(51.5073, -0.1276)); // about 11 m: filtered out
    await send(_fix(51.5172, -0.1276)); // about 1.1 km
    expect((await positions.next).latitude, 51.5172);

    await positions.cancel();
    await until(() => master.clients.single.references == 0);
  });
}
