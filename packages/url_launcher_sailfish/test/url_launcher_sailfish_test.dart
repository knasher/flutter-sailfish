import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:url_launcher_sailfish/url_launcher_sailfish.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late Directory system;
  late UrlLauncherSailfish launcher;
  late List<Object?> opened;

  void write(Directory dir, String name, String text) {
    File('${dir.path}/applications/$name')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  // What the runtime's channel answers; null removes it, like an old runtime.
  void runtime(bool? answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          UrlLauncherSailfish.channel,
          answer == null
              ? null
              : (call) async {
                  expect(call.method, 'openUrl');
                  opened.add(call.arguments);
                  return answer;
                },
        );
  }

  setUp(() {
    home = Directory.systemTemp.createTempSync('url_launcher_sailfish_home');
    system = Directory.systemTemp.createTempSync('url_launcher_sailfish');
    write(system, 'mimeinfo.cache', '''
[MIME Cache]
text/html=sailfish-browser.desktop;
x-scheme-handler/http=sailfish-browser.desktop;
x-scheme-handler/https=sailfish-browser.desktop;
x-scheme-handler/mailto=new-mail.desktop;
x-scheme-handler/tel=voicecall-ui.desktop;
x-scheme-handler/geo=
''');
    launcher = UrlLauncherSailfish.withDataDirs([home.path, system.path]);
    opened = [];
    runtime(true);
  });
  tearDown(() {
    runtime(null);
    home.deleteSync(recursive: true);
    system.deleteSync(recursive: true);
  });

  test('registers itself', () {
    UrlLauncherSailfish.registerWith();
    expect(UrlLauncherPlatform.instance, isA<UrlLauncherSailfish>());
  });

  test('can launch schemes an app handles', () async {
    expect(await launcher.canLaunch('https://example.com/a?b=c'), isTrue);
    expect(await launcher.canLaunch('HTTPS://EXAMPLE.COM'), isTrue);
    expect(await launcher.canLaunch('mailto:someone@example.com'), isTrue);
    expect(await launcher.canLaunch('tel:+441234567890'), isTrue);
    expect(await launcher.canLaunch('geo:51.5,-0.1'), isFalse);
    expect(await launcher.canLaunch('madeup:thing'), isFalse);
    expect(await launcher.canLaunch('no scheme'), isFalse);
    expect(opened, isEmpty);
  });

  test('reads mimeapps.list too, but not removed associations', () async {
    write(home, 'mimeapps.list', '''
[Default Applications]
x-scheme-handler/geo=maps.desktop;

[Removed Associations]
x-scheme-handler/sms=jolla-messages.desktop;
''');
    expect(await launcher.canLaunch('geo:51.5,-0.1'), isTrue);
    expect(await launcher.canLaunch('sms:123'), isFalse);
  });

  test('opens links through the runtime', () async {
    const url = 'https://example.com/a?b=c';
    expect(await launcher.launchUrl(url, const LaunchOptions()), isTrue);
    expect(opened, [url]);

    runtime(false);
    expect(await launcher.launchUrl(url, const LaunchOptions()), isFalse);
  });

  test('doesn\'t ask the runtime when no app handles the link', () async {
    expect(
      await launcher.launchUrl('geo:51.5,-0.1', const LaunchOptions()),
      isFalse,
    );
    expect(opened, isEmpty);
  });

  test('leaves web links alone for non-browser apps only', () async {
    const options = LaunchOptions(
      mode: PreferredLaunchMode.externalNonBrowserApplication,
    );
    expect(await launcher.launchUrl('https://example.com', options), isFalse);
    expect(await launcher.launchUrl('mailto:a@example.com', options), isTrue);
    expect(opened, ['mailto:a@example.com']);
  });

  test('explains when the runtime is too old', () async {
    runtime(null);
    await expectLater(
      launcher.launchUrl('https://example.com', const LaunchOptions()),
      throwsA(
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'unsupported')
            .having((e) => e.message, 'message', contains('7.sfos6')),
      ),
    );
  });

  test('supports opening in other apps only', () async {
    expect(
      await launcher.supportsMode(PreferredLaunchMode.platformDefault),
      isTrue,
    );
    expect(
      await launcher.supportsMode(PreferredLaunchMode.externalApplication),
      isTrue,
    );
    expect(
      await launcher.supportsMode(PreferredLaunchMode.inAppWebView),
      isFalse,
    );
    expect(
      await launcher.supportsCloseForMode(PreferredLaunchMode.inAppWebView),
      isFalse,
    );
  });
}
