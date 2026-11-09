import 'dart:io';
import 'package:flutter/services.dart';

/// The system owns recognition, text selection, copy and its Translate menu.
abstract final class ReaderImageText {
  static const _channel = MethodChannel('venera/method_channel');
  static Future<bool> available() async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('imageTextAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> open(Uint8List bytes) =>
      _channel.invokeMethod<void>('analyzeImageText', bytes);
}
