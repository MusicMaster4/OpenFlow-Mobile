import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voxora/src/controller/voxora_controller.dart';
import 'package:voxora/src/models/transcript_entry.dart';
import 'package:voxora/src/models/usage_stats.dart';
import 'package:voxora/src/services/floating_overlay_service.dart';
import 'package:voxora/src/services/local_storage_service.dart';
import 'package:voxora/src/services/openrouter_service.dart';
import 'package:voxora/src/services/recording_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recordChannel = MethodChannel('com.llfbandit.record/messages');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
  });

  for (final scenario in <({bool autoCopy, bool autoPaste})>[
    (autoCopy: false, autoPaste: false),
    (autoCopy: false, autoPaste: true),
    (autoCopy: true, autoPaste: false),
    (autoCopy: true, autoPaste: true),
  ]) {
    test(
      'overlay output respects copy=${scenario.autoCopy} and paste=${scenario.autoPaste}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'openflow_overlay_output_',
        );
        final audio = File(
          '${directory.path}${Platform.pathSeparator}recording.wav',
        );
        await audio.writeAsBytes(List<int>.filled(64, 1));
        addTearDown(() async {
          if (await directory.exists()) await directory.delete(recursive: true);
        });

        final overlay = _FakeOverlay();
        final controller = VoxoraController(
          storage: _MemoryStorage(),
          openRouter: _FakeOpenRouter(),
          recording: _FakeRecording(audio.path),
          floatingOverlay: overlay,
        );
        addTearDown(controller.dispose);

        expect(
          await controller.saveApiKey('test-key-with-enough-characters'),
          isTrue,
        );
        await controller.setAutoCopy(scenario.autoCopy);
        await controller.setAutoPaste(scenario.autoPaste);
        await controller.startRecording(fromOverlay: true);
        await controller.stopAndTranscribe();

        expect(overlay.copiedTexts, hasLength(scenario.autoCopy ? 1 : 0));
        expect(overlay.pastedTexts, hasLength(scenario.autoPaste ? 1 : 0));
        if (scenario.autoPaste) {
          expect(overlay.keepInClipboard.single, scenario.autoCopy);
        }
      },
    );
  }
}

class _MemoryStorage extends LocalStorageService {
  @override
  Future<void> saveApiKey(String apiKey) async {}

  @override
  Future<void> saveAutoCopy(bool value) async {}

  @override
  Future<void> saveAutoPaste(bool value) async {}

  @override
  Future<void> saveHistory(List<TranscriptEntry> entries) async {}

  @override
  Future<void> saveUsageStats(UsageStats stats) async {}
}

class _FakeOpenRouter extends OpenRouterService {
  @override
  Future<TranscriptionResult> transcribe({
    required File file,
    required String apiKey,
    required String format,
    String languageHint = 'auto',
    String modelId = OpenRouterService.defaultModel,
    int expectedDurationMs = 0,
  }) async => const TranscriptionResult(
    text: 'Texto vindo da bolinha.',
    model: 'test-model',
    transcriptionMs: 10,
  );
}

class _FakeRecording extends RecordingService {
  _FakeRecording(this.path);

  final String path;

  @override
  Stream<AudioVisualizationFrame> get visualizationStream =>
      const Stream.empty();

  @override
  Future<RecordingStart> start() async =>
      RecordingStart(path: path, format: 'wav');

  @override
  Future<String?> stop() async => path;

  @override
  Future<void> dispose() async {}
}

class _FakeOverlay extends FloatingOverlayService {
  final List<String> copiedTexts = [];
  final List<String> pastedTexts = [];
  final List<bool> keepInClipboard = [];

  @override
  Future<bool> hasRecordAudioPermission() async => true;

  @override
  Future<bool> isAccessibilityEnabled() async => true;

  @override
  Future<bool> copyText(String text) async {
    copiedTexts.add(text);
    return true;
  }

  @override
  Future<bool> pasteText(String text, {bool keepInClipboard = true}) async {
    pastedTexts.add(text);
    this.keepInClipboard.add(keepInClipboard);
    return true;
  }

  @override
  Future<void> playFeedback(String sound) async {}

  @override
  Future<void> setRecordingActive({
    required bool active,
    required bool silence,
  }) async {}

  @override
  Future<void> update({
    required String state,
    required double level,
    required List<double> bands,
  }) async {}
}
