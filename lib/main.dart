import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:zeus_game_platform_flutter/common/windows_native.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();


  runApp(const MainApp());
}


class MainApp extends StatelessWidget {
  const MainApp({super.key});


  @override
  Widget build(BuildContext context) {
    // WindowsNative.getMotherboard().then((result) => {
    //   print('$result')
    // });


    return GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(),
    );
  }
}
