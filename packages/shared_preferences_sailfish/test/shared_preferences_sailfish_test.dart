import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_sailfish/path_provider_sailfish.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:shared_preferences_sailfish/shared_preferences_sailfish.dart';

void main() {
  late Directory temp;

  setUp(
    () => temp = Directory.systemTemp.createTempSync(
      'shared_preferences_sailfish',
    ),
  );
  tearDown(() => temp.deleteSync(recursive: true));

  test('keeps preferences in the app data folder', () async {
    SharedPreferencesSailfish.registerWithPaths(
      PathProviderSailfish.withDirs(
        () => SailfishAppDirs(home: temp.path, name: 'uk.co.kubar/kudos'),
      ),
    );
    final file = File(
      '${temp.path}/.local/share/uk.co.kubar/kudos/shared_preferences.json',
    );
    Map<String, dynamic> saved() =>
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    await SharedPreferencesStorePlatform.instance.setValue(
      'String',
      'flutter.theme',
      'dark',
    );
    expect(saved(), {'flutter.theme': 'dark'});

    await SharedPreferencesAsyncPlatform.instance!.setBool(
      'welcomed',
      true,
      const SharedPreferencesOptions(),
    );
    expect(saved()['welcomed'], true);
  });
}
