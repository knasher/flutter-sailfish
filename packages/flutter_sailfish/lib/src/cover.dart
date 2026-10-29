import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// A button on the app's cover. The home screen draws it along the bottom of
/// the cover and calls [onPressed] when it's tapped.
class CoverAction {
  const CoverAction({required this.icon, required this.onPressed});

  /// A Sailfish theme icon name, such as `icon-cover-refresh`, or an image
  /// URL or absolute path.
  final String icon;

  final VoidCallback onPressed;
}

/// The app's cover: what the Sailfish home screen shows in the app's tile
/// while the app is in the background.
///
/// The cover is an ordinary widget, drawn off-screen at the tile's size and
/// shown in a cover window of its own, so opening the app from it is as
/// smooth as for native apps. It is drawn when it is set, and then only while
/// the home screen shows it: again whenever it changes (for example on
/// `setState`), and when the tile changes size.
///
/// The tile is about 446×714 pixels with four or fewer apps open, and about
/// 284×454 with more, so lay the cover out for both (it gets its size through
/// [MediaQuery]). Leave room at the bottom for any [CoverAction]s.
///
/// The cover has its own widget tree, separate from the app's, so give it
/// the app's state through listenables (for example [ValueNotifier]s) rather
/// than inherited widgets. The tree lasts as long as the app: setting the
/// cover again updates it as calling `runApp` again updates the app's tree,
/// and a new tile size lays it out again, so state is kept where it would be
/// in the app, and the rest is disposed.
class SailfishCover {
  SailfishCover._();

  static const _channel = BasicMessageChannel<Object?>(
    'flutter-sfos/cover',
    JSONMessageCodec(),
  );
  static const _frameChannel = 'flutter-sfos/cover_frame';

  /// Whether the home screen is showing the cover.
  static final ValueNotifier<bool> visible = ValueNotifier(false);

  static Widget? _cover;
  static List<CoverAction> _actions = const [];
  static bool _listening = false;
  static bool _available = false;
  static int _width = 0;
  static int _height = 0;
  static bool _drawn = false;
  static _OffscreenCover? _offscreen;
  static bool _rendering = false;
  static bool _dirty = false;

  /// Sets the cover and its buttons. On other platforms, or runtimes without
  /// cover support, this does nothing.
  static void set(Widget cover, {List<CoverAction> actions = const []}) {
    _listen();
    _cover = cover;
    _drawn = false;
    _actions = actions;
    _channel.send({
      'version': 1,
      'actions': [
        for (var i = 0; i < actions.length; i++)
          {'id': i, 'icon': actions[i].icon},
      ],
    });
    _changed();
  }

  static void _listen() {
    if (_listening) {
      return;
    }
    _listening = true;
    _channel.setMessageHandler((message) async {
      if (message is! Map) {
        return null;
      }
      final action = message['action'];
      if (action is int && action >= 0 && action < _actions.length) {
        _actions[action].onPressed();
      }
      if (message.containsKey('available')) {
        _available = message['available'] == true;
        _width = message['width'] as int? ?? 0;
        _height = message['height'] as int? ?? 0;
        visible.value = message['visible'] == true;
        _changed();
      }
      return null;
    });
  }

  // Draws the cover when it's needed: the first time (which creates the cover
  // window) and while it's shown. Changes while it's hidden are drawn when
  // it's next shown.
  static void _changed() {
    if (!_available || _cover == null || _width <= 0 || _height <= 0) {
      return;
    }
    if (_drawn && !visible.value) {
      _dirty = true;
      return;
    }
    if (_rendering) {
      _dirty = true;
      return;
    }
    _rendering = true;
    _dirty = false;
    scheduleMicrotask(_render);
  }

  static Future<void> _render() async {
    try {
      final view = ui.PlatformDispatcher.instance.implicitView!;
      final dpr = view.devicePixelRatio;
      _offscreen ??= _OffscreenCover(view, _changed);
      final image = await _offscreen!.draw(
        _cover!,
        Size(_width / dpr, _height / dpr),
        dpr,
      );
      final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final width = image.width, height = image.height;
      image.dispose();
      if (rgba == null) {
        return;
      }
      // Width and height (little-endian), then the premultiplied RGBA pixels.
      final message = Uint8List(8 + rgba.lengthInBytes);
      ByteData.sublistView(message)
        ..setUint32(0, width, Endian.little)
        ..setUint32(4, height, Endian.little);
      message.setRange(
        8,
        message.length,
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      );
      await ServicesBinding.instance.defaultBinaryMessenger.send(
        _frameChannel,
        ByteData.sublistView(message),
      );
      _drawn = true;
    } finally {
      _rendering = false;
      if (_dirty && visible.value) {
        _changed();
      }
    }
  }
}

/// Draws [cover] off-screen at [size] (logical pixels) once, for tests.
@visibleForTesting
Future<ui.Image> debugRenderCover(
  Widget cover,
  Size size,
  double devicePixelRatio,
) {
  final view = ui.PlatformDispatcher.instance.implicitView!;
  return _OffscreenCover(view, () {}).draw(cover, size, devicePixelRatio);
}

// A widget tree of its own, laid out at the cover's size and painted on
// demand. Its RenderView is never composited into the app's view.
class _OffscreenCover {
  _OffscreenCover(ui.FlutterView view, VoidCallback onChanged) {
    // Changes made while drawing are in that drawing.
    void changed() {
      if (!_drawing) {
        onChanged();
      }
    }

    _renderView = RenderView(view: view, child: _boundary);
    _pipelineOwner = PipelineOwner(onNeedVisualUpdate: changed)
      ..rootNode = _renderView;
    _buildOwner = BuildOwner(
      focusManager: FocusManager(),
      onBuildScheduled: changed,
    );
  }

  final _boundary = RenderRepaintBoundary();
  late final RenderView _renderView;
  late final PipelineOwner _pipelineOwner;
  late final BuildOwner _buildOwner;
  RenderObjectToWidgetElement<RenderBox>? _element;
  Widget? _cover;
  Size? _size;
  double? _dpr;
  bool _drawing = false;

  // Draws [cover] filling [size] (logical pixels). A new cover or size
  // updates the tree.
  Future<ui.Image> draw(Widget cover, Size size, double dpr) {
    _drawing = true;
    try {
      if (!identical(cover, _cover) || size != _size || dpr != _dpr) {
        _cover = cover;
        _size = size;
        _dpr = dpr;
        _renderView.configuration = ViewConfiguration(
          logicalConstraints: BoxConstraints.tight(size),
          physicalConstraints: BoxConstraints.tight(size * dpr),
          devicePixelRatio: dpr,
        );
        if (_element == null) {
          _renderView.prepareInitialFrame();
        }
        _element = RenderObjectToWidgetAdapter<RenderBox>(
          container: _boundary,
          child: MediaQuery(
            data: MediaQueryData(size: size, devicePixelRatio: dpr),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Material(type: MaterialType.transparency, child: cover),
            ),
          ),
        ).attachToRenderTree(_buildOwner, _element);
      }
      _buildOwner.buildScope(_element!);
      _buildOwner.finalizeTree();
      _pipelineOwner.flushLayout();
      _pipelineOwner.flushCompositingBits();
      _pipelineOwner.flushPaint();
    } finally {
      _drawing = false;
    }
    return _boundary.toImage(pixelRatio: dpr);
  }
}
