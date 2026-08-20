import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxora/src/controller/voxora_controller.dart';
import 'package:voxora/src/screens/home_screen.dart';
import 'package:voxora/src/services/floating_overlay_service.dart';
import 'package:voxora/src/services/app_update_service.dart';
import 'package:voxora/src/services/local_storage_service.dart';
import 'package:voxora/src/services/openrouter_service.dart';
import 'package:voxora/src/services/recording_service.dart';
import 'package:voxora/src/theme.dart';

class _FakeAppUpdateService extends AppUpdateService {
  @override
  bool get isSupported => true;

  @override
  Future<void> check() async {
    phase = AppUpdatePhase.checking;
    notifyListeners();
  }

  void finishCheck() {
    available = AvailableAppUpdate(
      versionName: '2.1.0',
      versionCode: build.versionCode + 1,
      channel: build.channel,
      apkUrl: 'https://example.com/openflow.apk',
      sha256: List.filled(64, 'a').join(),
    );
    phase = AppUpdatePhase.available;
    notifyListeners();
  }

  @override
  Future<void> downloadAndInstall() async {
    phase = AppUpdatePhase.downloading;
    progress = 0.42;
    notifyListeners();
  }
}

class _FakeOpenRouterService extends OpenRouterService {
  @override
  Future<List<TranscriptionModel>> listTranscriptionModels({
    String? apiKey,
  }) async {
    return const [
      TranscriptionModel(
        id: 'openai/gpt-4o-mini-transcribe',
        name: 'OpenAI: GPT-4o Mini Transcribe',
      ),
    ];
  }
}

void main() {
  testWidgets('transcribing state shows the selected transcription model', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final controller = VoxoraController(
      storage: LocalStorageService(),
      openRouter: _FakeOpenRouterService(),
      recording: RecordingService(),
      floatingOverlay: FloatingOverlayService(),
    );
    controller.transcriptionModel = 'openai/gpt-4o-mini-transcribe';
    controller.activity = VoxoraActivity.transcribing;

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: VoxoraTheme.dark,
        home: HomeScreen(controller: controller),
      ),
    );

    expect(find.text('openai/gpt-4o-mini-transcribe'), findsOneWidget);
    expect(find.text('MAI-Transcribe 1.5'), findsNothing);

    await controller.loadTranscriptionModels();
    await tester.pump();

    expect(find.text('OpenAI: GPT-4o Mini Transcribe'), findsOneWidget);
    expect(find.text('MAI-Transcribe 1.5'), findsNothing);
  });

  testWidgets('settings shows update check and download feedback immediately', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 915);
    addTearDown(tester.view.reset);

    final updates = _FakeAppUpdateService();
    addTearDown(updates.dispose);
    final controller = VoxoraController(
      storage: LocalStorageService(),
      openRouter: OpenRouterService(),
      recording: RecordingService(),
      floatingOverlay: FloatingOverlayService(),
      updates: updates,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: VoxoraTheme.dark,
        home: HomeScreen(controller: controller),
      ),
    );
    await tester.tap(find.byTooltip('Configurações'));
    await tester.pump(const Duration(seconds: 1));
    for (var step = 0; step < 3; step++) {
      await tester.dragFrom(const Offset(206, 700), const Offset(0, -600));
      await tester.pump(const Duration(milliseconds: 250));
    }
    final checkButton = find.text('Verificar atualizações');
    await tester.ensureVisible(checkButton);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(checkButton);
    await tester.pump();
    expect(find.text('Verificando…'), findsOneWidget);
    expect(find.text('Consultando o canal stable…'), findsOneWidget);

    updates.finishCheck();
    await tester.pump();
    expect(find.text('Baixar e instalar'), findsOneWidget);
    expect(
      find.text('OpenFlow 2.1.0 está disponível para este canal.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Baixar e instalar'));
    await tester.pump();
    expect(find.text('Baixando…'), findsOneWidget);
    expect(find.text('Baixando e verificando o APK… 42%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

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
