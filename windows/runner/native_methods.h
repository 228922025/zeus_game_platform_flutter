#pragma once
#include <flutter/flutter_engine.h>


// 注册所有 native methods，在 FlutterWindow 的 OnCreate 中调用
void RegisterNativeMethods(flutter::FlutterEngine* engine);