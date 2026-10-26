import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_sailfish/path_provider_sailfish.dart';

void main() {
  late Directory temp;

  setUp(
    () => temp = Directory.systemTemp.createTempSync('path_provider_sailfish'),
  );
  tearDown(() => temp.deleteSync(recursive: true));

  String desktopDir(String name, String contents) {
    final dir = Directory('${temp.path}/$name')..createSync();
    File('${dir.path}/kudos.desktop').writeAsStringSync(contents);
    return dir.path;
  }

  group('sailjailName', () {
    test('reads the [X-Sailjail] names', () {
      expect(
        SailfishAppDirs.sailjailName('''
[Desktop Entry]
Name=KU
Exec=kudos

# Sandbox
[X-Sailjail]
Permissions=Internet
 OrganizationName = uk.co.kubar
ApplicationName=kudos
'''),
        'uk.co.kubar/kudos',
      );
    });

    test('ignores the names in other sections', () {
      expect(
        SailfishAppDirs.sailjailName('''
[Desktop Entry]
OrganizationName=uk.co.kubar
ApplicationName=kudos
'''),
        isNull,
      );
    });

    test('needs both names', () {
      expect(
        SailfishAppDirs.sailjailName(
          '[X-Sailjail]\nOrganizationName=uk.co.kubar\n',
        ),
        isNull,
      );
      expect(
        SailfishAppDirs.sailjailName(
          '[X-Sailjail]\nOrganizationName=\nApplicationName=kudos\n',
        ),
        isNull,
      );
    });
  });

  group('resolve', () {
    test('uses the desktop file in the first folder that has it', () {
      final dirs = SailfishAppDirs.resolve(
        home: '/home/defaultuser',
        binaryName: 'kudos',
        desktopDirs: [
          '${temp.path}/missing',
          desktopDir(
            'etc',
            '[X-Sailjail]\nOrganizationName=uk.co.kubar\nApplicationName=kudos\n',
          ),
        ],
      );
      expect(dirs.name, 'uk.co.kubar/kudos');
      expect(dirs.data, '/home/defaultuser/.local/share/uk.co.kubar/kudos');
      expect(dirs.config, '/home/defaultuser/.config/uk.co.kubar/kudos');
      expect(dirs.cache, '/home/defaultuser/.cache/uk.co.kubar/kudos');
    });

    test('falls back to the binary name', () {
      final dirs = SailfishAppDirs.resolve(
        home: '/home/defaultuser',
        binaryName: 'kudos',
        desktopDirs: [desktopDir('usr', '[Desktop Entry]\nExec=kudos\n')],
      );
      expect(dirs.data, '/home/defaultuser/.local/share/kudos');
    });
  });

  test('registers itself and creates the folders it returns', () async {
    PathProviderSailfish.registerWith();
    expect(PathProviderPlatform.instance, isA<PathProviderSailfish>());

    final home = temp.path;
    final provider = PathProviderSailfish.withDirs(
      () => SailfishAppDirs(home: home, name: 'uk.co.kubar/kudos'),
    );
    final data = '$home/.local/share/uk.co.kubar/kudos';
    final cache = '$home/.cache/uk.co.kubar/kudos';
    expect(await provider.getApplicationSupportPath(), data);
    expect(await provider.getApplicationDocumentsPath(), data);
    expect(await provider.getApplicationCachePath(), cache);
    expect(await provider.getTemporaryPath(), cache);
    expect(await provider.getDownloadsPath(), '$home/Downloads');
    expect(Directory(data).existsSync(), isTrue);
    expect(Directory(cache).existsSync(), isTrue);
  });
}
