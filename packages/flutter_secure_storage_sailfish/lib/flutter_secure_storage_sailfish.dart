/// Sailfish OS implementation of flutter_secure_storage.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:path_provider_sailfish/path_provider_sailfish.dart';

/// flutter_secure_storage for Sailfish OS: a private file, not a keyring.
///
/// Values are kept as JSON in `flutter_secure_storage.json` in the app's
/// Sailjail data folder (`~/.local/share/<org>/<app>`), readable only by the
/// user (mode 0600). Sailjail hides that folder from other sandboxed apps, but
/// the values aren't encrypted beyond the phone's own storage encryption, and
/// programs running outside the sandbox as the user, or as root, can read
/// them.
class FlutterSecureStorageSailfish extends FlutterSecureStoragePlatform {
  FlutterSecureStorageSailfish()
    : this.inFolder(() => SailfishAppDirs.current().data);

  /// Keeps the file in [folder] instead of the app's data folder.
  @visibleForTesting
  FlutterSecureStorageSailfish.inFolder(String Function() folder)
    : _folder = folder;

  /// Registers this as the flutter_secure_storage implementation.
  static void registerWith() {
    FlutterSecureStoragePlatform.instance = FlutterSecureStorageSailfish();
  }

  final String Function() _folder;

  // Found on first use, so registering reads no files.
  late final File _file = File('${_folder()}/flutter_secure_storage.json');

  Map<String, String>? _values;

  Future<void> _previous = Future<void>.value();

  // Runs [action] after the previous call has finished, so read-modify-write
  // calls can't lose each other's changes.
  Future<T> _inTurn<T>(Future<T> Function() action) {
    final result = _previous.then((_) => action());
    _previous = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Map<String, String>> _load() async {
    if (_values case final values?) {
      return values;
    }
    if (!_file.existsSync()) {
      return _values = <String, String>{};
    }
    final decoded = jsonDecode(await _file.readAsString());
    return _values = Map<String, String>.from(decoded as Map);
  }

  // Writes a 0600 file next to the old one, then renames it over, so the
  // values are never readable by others or half written.
  Future<void> _save(Map<String, String> values) async {
    await _file.parent.create(recursive: true);
    final temp = File('${_file.path}.tmp');
    await temp.writeAsString('');
    _chmod(temp.path, 0x180); // 0600
    await temp.writeAsString(jsonEncode(values), flush: true);
    await temp.rename(_file.path);
    _values = values;
  }

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) => _inTurn(() async => _save({...await _load(), key: value}));

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => _inTurn(() async => (await _load())[key]);

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => _inTurn(() async => (await _load()).containsKey(key));

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) => _inTurn(() async => _save({...await _load()}..remove(key)));

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      _inTurn(() async => {...await _load()});

  @override
  Future<void> deleteAll({required Map<String, String> options}) =>
      _inTurn(() => _save(<String, String>{}));
}

// dart:io can't set a file's mode, so call libc's chmod.
final int Function(Pointer<Utf8>, int) _chmodC = DynamicLibrary.process()
    .lookupFunction<
      Int32 Function(Pointer<Utf8>, Uint32),
      int Function(Pointer<Utf8>, int)
    >('chmod');

void _chmod(String path, int mode) {
  final nativePath = path.toNativeUtf8();
  try {
    if (_chmodC(nativePath, mode) != 0) {
      throw FileSystemException('Cannot set the file mode', path);
    }
  } finally {
    malloc.free(nativePath);
  }
}
