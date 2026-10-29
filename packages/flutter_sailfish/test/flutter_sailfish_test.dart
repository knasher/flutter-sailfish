import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sailfish/flutter_sailfish.dart';
import 'package:flutter_sailfish/src/cover.dart' show debugRenderCover;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('draws a cover off-screen at the tile size', (tester) async {
    const dpr = 2.25;
    final cover = Container(color: const Color(0xffff0000));
    for (final (width, height) in [(446, 714), (284, 454)]) {
      final image = await tester.runAsync(
        () => debugRenderCover(cover, Size(width / dpr, height / dpr), dpr),
      );
      expect(image!.width, width);
      expect(image.height, height);
      final bytes = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      expect(bytes!.lengthInBytes, width * height * 4);
      expect(bytes.getUint8(0), 255); // red
      expect(bytes.getUint8(2), 0); // no blue
    }
  });

  test('keeps one cover tree, drawn once per change', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // The runtime's side: the frames it's sent, and its cover state.
    final frames = <(int, int)>[];
    messenger.setMockMessageHandler('flutter-sfos/cover', (_) async => null);
    messenger.setMockMessageHandler('flutter-sfos/cover_frame', (data) async {
      frames.add((
        data!.getUint32(0, Endian.little),
        data.getUint32(4, Endian.little),
      ));
      return null;
    });
    Future<void> tile(int width, int height) => messenger.handlePlatformMessage(
      'flutter-sfos/cover',
      const JSONMessageCodec().encodeMessage({
        'version': 1,
        'available': true,
        'visible': true,
        'width': width,
        'height': height,
      }),
      (_) {},
    );
    // Drawing takes real time (toImage).
    Future<void> drawn() =>
        Future<void>.delayed(const Duration(milliseconds: 300));

    final log = <String>[];
    final count = ValueNotifier(0);
    SailfishCover.set(_TestCover(log, count));
    await tile(446, 714);
    await drawn();
    expect(frames, [(446, 714)]);

    count.value++;
    await drawn();
    expect(frames, hasLength(2));

    // A new tile size redraws the same cover, state and all.
    await tile(284, 454);
    await drawn();
    expect(frames.skip(2), [(284, 454)]);
    expect(log, ['init']);

    // A new cover replaces it, and the old one is disposed, so it no longer
    // listens to the app's state.
    SailfishCover.set(const SizedBox());
    await drawn();
    expect(frames, hasLength(4));
    expect(log, ['init', 'dispose']);
    count.value++;
    await drawn();
    expect(frames, hasLength(4));
  });

  testWidgets('applies the cut-out padding from the runtime', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: SailfishCutouts.builder,
        home: Builder(
          builder: (context) => Text('${MediaQuery.paddingOf(context).top}'),
        ),
      ),
    );
    final message = const JSONMessageCodec().encodeMessage({
      'version': 1,
      'padding': {'top': 66, 'right': 0, 'bottom': 0, 'left': 0},
      'cutouts': [],
    });
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter-sfos/display_cutouts',
      message,
      (_) {},
    );
    await tester.pump();
    final dpr = tester.view.devicePixelRatio;
    expect(find.text('${66 / dpr}'), findsOneWidget);
  });

  testWidgets('adds nothing when the runtime reports the padding', (
    tester,
  ) async {
    // The runtime puts the cut-out in the window metrics (view padding).
    tester.view.padding = const FakeViewPadding(top: 66);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(
      MaterialApp(
        builder: SailfishCutouts.builder,
        home: Builder(
          builder: (context) => Text('${MediaQuery.paddingOf(context).top}'),
        ),
      ),
    );
    final message = const JSONMessageCodec().encodeMessage({
      'version': 1,
      'padding': {'top': 66, 'right': 0, 'bottom': 0, 'left': 0},
      'in_metrics': true,
      'cutouts': [],
    });
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter-sfos/display_cutouts',
      message,
      (_) {},
    );
    await tester.pump();
    final dpr = tester.view.devicePixelRatio;
    expect(find.text('${66 / dpr}'), findsOneWidget);
    expect(SailfishCutouts.padding.value.top, 66);
  });
}

// A cover that logs its state's life, and shows [count].
class _TestCover extends StatefulWidget {
  const _TestCover(this.log, this.count);

  final List<String> log;
  final ValueListenable<int> count;

  @override
  State<_TestCover> createState() => _TestCoverState();
}

class _TestCoverState extends State<_TestCover> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: widget.count,
    builder: (context, count, _) => Text('$count'),
  );
}
