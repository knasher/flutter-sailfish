import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps content clear of display cut-outs, such as a camera notch.
///
/// Sailfish apps run full screen and are drawn under the cut-out, and the
/// Flutter embedder API can't set [MediaQueryData.padding], so the runtime
/// sends the cut-outs on a channel and [builder] applies them. With it, app
/// bars draw their background behind the cut-out and keep their contents
/// below it, and [SafeArea] and scroll views keep clear of it, as on phones
/// with a notch elsewhere.
class SailfishCutouts {
  SailfishCutouts._();

  static const _channel = BasicMessageChannel<Object?>('flutter-sfos/display_cutouts', JSONMessageCodec());

  static final _padding = ValueNotifier<EdgeInsets>(EdgeInsets.zero);
  static bool _listening = false;

  /// The padding that keeps content clear of the cut-outs, in physical
  /// pixels, for the current orientation.
  static ValueListenable<EdgeInsets> get padding {
    _listen();
    return _padding;
  }

  /// Adds the cut-out padding to [MediaQueryData.padding] and
  /// [MediaQueryData.viewPadding]. Use it as the app's builder:
  ///
  /// ```dart
  /// MaterialApp(builder: SailfishCutouts.builder, home: const MyHomePage())
  /// ```
  static Widget builder(BuildContext context, Widget? child) {
    return ValueListenableBuilder<EdgeInsets>(
      valueListenable: padding,
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
        _padding.value = EdgeInsets.fromLTRB(v('left'), v('top'), v('right'), v('bottom'));
      }
      return null;
    });
  }
}
