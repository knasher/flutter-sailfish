import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_secure_storage_sailfish/flutter_secure_storage_sailfish.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late File file;
  late FlutterSecureStorageSailfish storage;
  const options = <String, String>{};

  setUp(() {
    temp = Directory.systemTemp.createTempSync(
      'flutter_secure_storage_sailfish',
    );
    file = File('${temp.path}/data/flutter_secure_storage.json');
    storage = FlutterSecureStorageSailfish.inFolder(() => '${temp.path}/data');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test('registers itself', () {
    FlutterSecureStorageSailfish.registerWith();
    expect(
      FlutterSecureStoragePlatform.instance,
      isA<FlutterSecureStorageSailfish>(),
    );
  });

  test('writes, reads and deletes values', () async {
    expect(await storage.read(key: 'token', options: options), isNull);
    await storage.write(key: 'token', value: 'abc', options: options);
    await storage.write(key: 'refresh', value: 'def', options: options);
    expect(await storage.read(key: 'token', options: options), 'abc');
    expect(await storage.containsKey(key: 'refresh', options: options), isTrue);
    expect(await storage.readAll(options: options), {
      'token': 'abc',
      'refresh': 'def',
    });

    await storage.delete(key: 'token', options: options);
    expect(await storage.readAll(options: options), {'refresh': 'def'});
    await storage.deleteAll(options: options);
    expect(await storage.readAll(options: options), isEmpty);
  });

  test('keeps values in a private file across instances', () async {
    await storage.write(key: 'token', value: 'abc', options: options);
    expect(jsonDecode(file.readAsStringSync()), {'token': 'abc'});
    expect(file.statSync().mode & 0x1ff, 0x180); // 0600
    expect(File('${file.path}.tmp').existsSync(), isFalse);

    final again = FlutterSecureStorageSailfish.inFolder(
      () => '${temp.path}/data',
    );
    expect(await again.read(key: 'token', options: options), 'abc');
  });

  test('keeps every one of many overlapping writes', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++)
        storage.write(key: 'key$i', value: '$i', options: options),
    ]);
    final saved = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    expect(saved.length, 20);
  });
}
