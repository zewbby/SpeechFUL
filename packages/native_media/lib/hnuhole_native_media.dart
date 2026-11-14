import 'package:flutter/services.dart';

/// Opaque, short-lived selection. No library paths or metadata cross the bridge.
class IosPickedOriginal {
  IosPickedOriginal._(this._channel, this._id, this.length);
  final MethodChannel _channel;
  final String _id;
  final int length;
  bool _released = false;

  Future<Uint8List> read() async {
    if (_released) throw StateError('Photo selection expired');
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('read', _id);
      if (bytes == null || bytes.length != length) {
        throw const FormatException('Photo selection changed');
      }
      return bytes;
    } finally {
      await release();
    }
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      await _channel.invokeMethod<void>('release', _id);
    } catch (_) {
      // Native selections also expire; cleanup cannot change a save result.
    }
  }
}

class IosNativeMedia {
  const IosNativeMedia({
    this.channel = const MethodChannel('speechful/native_media'),
  });
  final MethodChannel channel;

  Future<List<IosPickedOriginal>> pick(int limit) async {
    if (limit < 1 || limit > 9) throw RangeError.range(limit, 1, 9);
    final values = await channel.invokeListMethod<Object?>('pick', {
      'limit': limit,
    });
    if (values == null || values.length > limit) {
      throw const FormatException('Invalid photo selection');
    }
    return values
        .map((value) {
          if (value is! Map ||
              value['id'] is! String ||
              value['length'] is! int ||
              (value['length'] as int) < 0) {
            throw const FormatException('Invalid photo selection');
          }
          return IosPickedOriginal._(
            channel,
            value['id'] as String,
            value['length'] as int,
          );
        })
        .toList(growable: false);
  }

  Future<bool> hasAccess() async =>
      await channel.invokeMethod<bool>('hasAccess') == true;
  Future<bool> requestAccess() async =>
      await channel.invokeMethod<bool>('requestAccess') == true;
  Future<void> putImage(String path) =>
      channel.invokeMethod<void>('putImage', path);
}
