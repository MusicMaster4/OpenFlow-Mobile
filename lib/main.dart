import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/controller/voxora_controller.dart';
import 'src/services/floating_overlay_service.dart';
import 'src/services/local_storage_service.dart';
import 'src/services/openrouter_service.dart';
import 'src/services/recording_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final controller = VoxoraController(
    storage: LocalStorageService(),
    openRouter: OpenRouterService(),
    recording: RecordingService(),
    floatingOverlay: FloatingOverlayService(),
  );
  await controller.initialize();

  runApp(VoxoraApp(controller: controller));
}
