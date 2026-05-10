
import 'package:flutter/services.dart';

class SystemInfoService {
  // 通过 MethodChannel 调用原生方法
  static const MethodChannel _channel = MethodChannel('com.example.systeminfo');

  static Future<Map<String, String>> getMotherboard() async {
    try {
      //
      final Map<Object?, Object?>? result = await _channel.invokeMethod('getMotherboard');
      if(result != null) {
        return Map<String, String>.from(result as Map);
      }
    } catch (e) {
      print('获取主板信息失败: $e');
    }

    return {};
  }
}