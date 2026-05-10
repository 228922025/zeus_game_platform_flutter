import 'package:flutter/services.dart';

class WindowsNative {
  static const MethodChannel _channel = MethodChannel('com.example.app/windows');

  static Future<Map<String, String?>> getMotherboard() async {
    final result = await _channel.invokeMethod('getMotherboard');
    return Map<String, String?>.from(result);
  }
}