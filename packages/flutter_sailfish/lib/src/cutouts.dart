import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps content clear of display cut-outs, such as a camera notch.
///
/// Sailfish apps run full screen and are drawn under the cut-out. Runtimes
/// with the view padding patch (flutter-sfos 7.sfos7 and later) report it
/// in [MediaQueryData.padding] themselves, so app bars, [SafeArea] and
/// scroll views keep clear of it in every app, as on phones with a notch
/// elsewhere, and [builder] adds nothing. Older runtimes only send the
/// cut-outs on a channel, and [builder] applies them.
class SailfishCutouts {
  SailfishCutouts._();

  static const _channel = BasicMessageChannel<Object?>(
    'flutter-sfos/display_cutouts',
    JSONMessageCodec(),
  );

  static final _padding = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
  // What [builder] adds: the padding, unless the runtime already reports it.
  static final _extra = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
  static bool _listening = false;

  /// The padding that keeps content clear of the cut-outs, in physical
  /// pixels, for the current orientation.
  static ValueListenable<EdgeInsets> get padding {
    _listen();
    return _padding;
  }

  /// Adds the cut-out padding to [MediaQueryData.padding] and
  /// [MediaQueryData.viewPadding] on runtimes that don't report it
  /// themselves. Use it as the app's builder:
  ///
  /// ```dart
  /// MaterialApp(builder: SailfishCutouts.builder, home: const MyHomePage())
  /// ```
  static Widget builder(BuildContext context, Widget? child) {
    _listen();
    return ValueListenableBuilder<EdgeInsets>(
      valueListenable: _extra,
      builder: (context, padding, _) {
        final mq = MediaQuery.of(context);
        final extra = padding / mq.devicePixelRatio;
        return MediaQuery(
          data: mq.copyWith(
            padding: mq.padding + extra,
            viewPadding: mq.viewPadding + extra,
          ),
          child: child!,
        );
      },
    );
  }

  static void _listen() {
    if (_listening) {
      return;
    }
    _listening = true;
    _channel.setMessageHandler((message) async {
      if (message is Map && message['padding'] is Map) {
        final p = message['padding'] as Map;
        double v(String k) => (p[k] as num? ?? 0).toDouble();
        final padding = EdgeInsets.fromLTRB(
          v('left'),
          v('top'),
          v('right'),
          v('bottom'),
        );
        _padding.value = padding;
        _extra.value = message['in_metrics'] == true
            ? EdgeInsets.zero
            : padding;
      }
      return null;
    });
  }
}
