import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxora/src/controller/voxora_controller.dart';
import 'package:voxora/src/screens/home_screen.dart';
import 'package:voxora/src/services/floating_overlay_service.dart';
import 'package:voxora/src/services/local_storage_service.dart';
import 'package:voxora/src/services/openrouter_service.dart';
import 'package:voxora/src/services/recording_service.dart';
import 'package:voxora/src/theme.dart';

void main() {
  testWidgets(
    'OpenFlow home keeps recorder and transcripts in one split view',
    (tester) async {
      const recordChannel = MethodChannel('com.llfbandit.record/messages');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(recordChannel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(recordChannel, null),
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(412, 915);
      addTearDown(tester.view.reset);

      final controller = VoxoraController(
        storage: LocalStorageService(),
        openRouter: OpenRouterService(),
        recording: RecordingService(),
        floatingOverlay: FloatingOverlayService(),
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: VoxoraTheme.dark,
          home: HomeScreen(controller: controller),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('OpenFlow'), findsOneWidget);
      expect(find.text('Toque para gravar'), findsOneWidget);
      expect(find.text('Transcrições'), findsOneWidget);
      await expectLater(
        find.byType(HomeScreen),
        matchesGoldenFile('goldens/openflow_home.png'),
      );

      await tester.tap(find.byTooltip('Estatísticas'));
      await tester.pumpAndSettle();
      expect(find.text('Seu ritmo no OpenFlow'), findsOneWidget);
      expect(find.text('ÚLTIMOS 7 DIAS'), findsOneWidget);
      expect(find.text('VISÃO GERAL'), findsOneWidget);

      await tester.pageBack();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byTooltip('Configurações'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Configurações'), findsOneWidget);
      for (var step = 0; step < 2; step++) {
        await tester.dragFrom(const Offset(206, 700), const Offset(0, -600));
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(find.text('SOBRE E ATUALIZAÇÕES'), findsOneWidget);
      expect(find.text('OpenFlow Mobile'), findsOneWidget);
      expect(find.text('STABLE'), findsOneWidget);
      expect(find.text('Verificar atualizações'), findsOneWidget);
    },
  );
}
