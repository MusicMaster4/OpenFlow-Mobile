import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller/voxora_controller.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

class VoxoraApp extends StatelessWidget {
  const VoxoraApp({super.key, required this.controller});

  final VoxoraController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenFlow',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: VoxoraTheme.dark,
      theme: VoxoraTheme.dark,
      builder: (context, child) {
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: VoxoraColors.background,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
          child: child!,
        );
      },
      home: HomeScreen(controller: controller),
    );
  }
}
