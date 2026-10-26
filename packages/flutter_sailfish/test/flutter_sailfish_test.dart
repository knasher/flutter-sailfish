import 'dart:ui' as ui;

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
}
