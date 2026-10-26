import 'dart:io';

import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';
import 'package:package_info_plus_sailfish/package_info_plus_sailfish.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late File binary;

  void write(String path, String text) {
    File('${root.path}$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('package_info_plus_sailfish');
    binary = File('${root.path}/usr/bin/kudos')..createSync(recursive: true);
    Directory('${root.path}/proc/self').createSync(recursive: true);
    Link('${root.path}/proc/self/exe').createSync(binary.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('registers itself', () {
    PackageInfoPlusSailfish.registerWith();
    expect(PackageInfoPlatform.instance, isA<PackageInfoPlusSailfish>());
  });

  test('reads the desktop file and version.json', () async {
    write('/usr/share/applications/kudos.desktop', '''
[Desktop Entry]
Type=Application
Name=KU
Exec=kudos

[Desktop Action scan]
Name=Scan

[X-Sailjail]
Permissions=Internet
OrganizationName=uk.co.kubar
ApplicationName=kudos
''');
    write(
      '/usr/share/kudos/data/flutter_assets/version.json',
      '{"app_name":"kudos","version":"2.0.0","build_number":"1",'
          '"package_name":"kudos"}',
    );

    final info = await PackageInfoPlusSailfish.inRoot(root.path).getAll();
    expect(info.appName, 'KU');
    expect(info.packageName, 'uk.co.kubar.kudos');
    expect(info.version, '2.0.0');
    expect(info.buildNumber, '1');
    expect(info.buildSignature, '');
    expect(info.installTime, binary.statSync().changed);
    expect(info.updateTime, binary.statSync().changed);
  });

  test('reads the desktop file from Sailjail\'s own folder', () async {
    write('/etc/sailjail/applications/kudos.desktop', '''
[Desktop Entry]
Name=KU
''');

    final info = await PackageInfoPlusSailfish.inRoot(root.path).getAll();
    expect(info.appName, 'KU');
    expect(info.packageName, 'kudos');
  });

  test('falls back to the binary name with no desktop file', () async {
    final info = await PackageInfoPlusSailfish.inRoot(root.path).getAll();
    expect(info.appName, 'kudos');
    expect(info.packageName, 'kudos');
    expect(info.version, '');
    expect(info.buildNumber, '');
  });
}
