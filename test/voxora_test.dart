import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:record/record.dart';
import 'package:voxora/src/models/transcript_entry.dart';
import 'package:voxora/src/models/usage_stats.dart';
import 'package:voxora/src/services/openrouter_service.dart';
import 'package:voxora/src/services/recording_service.dart';

void main() {
  test('transcript entry survives local JSON round-trip', () {
    final original = TranscriptEntry(
      id: '42',
      text: 'Uma ideia importante.',
      createdAt: DateTime.utc(2026, 8, 18, 12, 30),
      source: 'Gravação',
      model: OpenRouterService.model,
      durationMs: 4200,
      transcriptionMs: 730,
      costUsd: 0.001,
    );

    final restored = TranscriptEntry.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.text, original.text);
    expect(restored.createdAt, original.createdAt);
    expect(restored.durationMs, 4200);
    expect(restored.costUsd, 0.001);
  });

  test('OpenRouter response parser keeps text and usage metadata', () {
    final response = http.Response(
      '{"text":"Texto pronto.","model":"microsoft/mai-transcribe-1.5",'
      '"usage":{"seconds":12.5,"cost":0.00125}}',
      200,
    );

    final result = OpenRouterService.decodeResponse(response, elapsedMs: 840);

    expect(result.text, 'Texto pronto.');
    expect(result.audioDurationMs, 12500);
    expect(result.transcriptionMs, 840);
    expect(result.costUsd, 0.00125);
  });

  test('OpenRouter parser translates authentication failures', () {
    final response = http.Response('{"error":{"message":"Unauthorized"}}', 401);

    expect(
      () => OpenRouterService.decodeResponse(response, elapsedMs: 10),
      throwsA(
        isA<OpenRouterException>().having(
          (error) => error.message,
          'message',
          contains('inválida'),
        ),
      ),
    );
  });

  test('OpenRouter explains a generic provider format failure', () {
    final response = http.Response(
      '{"error":{"message":"Provider returned 400"}}',
      400,
    );

    expect(
      () => OpenRouterService.decodeResponse(response, elapsedMs: 10),
      throwsA(
        isA<OpenRouterException>().having(
          (error) => error.message,
          'message',
          allOf(contains('recusou o áudio'), contains('WAV')),
        ),
      ),
    );
  });

  test(
    'OpenRouter receives a valid WAV request without optional noise',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response('{"text":"Funcionou.","model":"test-model"}', 200);
      });
      final directory = await Directory.systemTemp.createTemp('openflow_wav_');
      final file = File('${directory.path}${Platform.pathSeparator}speech.wav');
      await file.writeAsBytes(_wavWithOneSample());
      final service = OpenRouterService(client: client);
      addTearDown(() async {
        service.dispose();
        await directory.delete(recursive: true);
      });

      final result = await service.transcribe(
        file: file,
        apiKey: 'test-key',
        format: 'wav',
        modelId: 'openai/gpt-4o-mini-transcribe',
      );
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      final inputAudio = body['input_audio'] as Map<String, dynamic>;

      expect(captured.url, OpenRouterService.endpoint);
      expect(captured.headers['authorization'], 'Bearer test-key');
      expect(body['model'], 'openai/gpt-4o-mini-transcribe');
      expect(body, isNot(contains('language')));
      expect(body, isNot(contains('temperature')));
      expect(inputAudio['format'], 'wav');
      expect(inputAudio['data'], isNot(startsWith('data:')));
      expect(result.text, 'Funcionou.');
    },
  );

  test('OpenRouter lists and sorts transcription models', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        '{"data":['
        '{"id":"microsoft/mai-transcribe-1.5","name":"Microsoft: MAI Transcribe"},'
        '{"id":"openai/gpt-4o-mini-transcribe","name":"OpenAI: GPT-4o Mini Transcribe"}'
        ']}',
        200,
      );
    });
    final service = OpenRouterService(client: client);
    addTearDown(service.dispose);

    final models = await service.listTranscriptionModels(apiKey: 'test-key');

    expect(captured.url, OpenRouterService.modelsEndpoint);
    expect(captured.headers['authorization'], 'Bearer test-key');
    expect(models, hasLength(2));
    expect(models.first.id, 'microsoft/mai-transcribe-1.5');
    expect(models.last.id, 'openai/gpt-4o-mini-transcribe');
  });

  test('recording ignores the app silencer audio-focus interruption', () {
    final config = RecordingService.debugRecordConfig(AudioEncoder.wav);

    expect(config.audioInterruption, AudioInterruptionMode.none);
  });

  test('header-only audio is rejected before reaching OpenRouter', () async {
    final directory = await Directory.systemTemp.createTemp('openflow_test_');
    final file = File('${directory.path}${Platform.pathSeparator}empty.wav');
    await file.writeAsBytes(List<int>.filled(44, 0));
    final service = OpenRouterService();
    addTearDown(() async {
      service.dispose();
      await directory.delete(recursive: true);
    });

    await expectLater(
      service.transcribe(file: file, apiKey: 'unused', format: 'wav'),
      throwsA(
        isA<OpenRouterException>().having(
          (error) => error.message,
          'message',
          contains('não capturou áudio'),
        ),
      ),
    );
  });

  test('silent PCM audio is rejected before reaching OpenRouter', () async {
    final directory = await Directory.systemTemp.createTemp('openflow_silent_');
    final file = File('${directory.path}${Platform.pathSeparator}silent.wav');
    await file.writeAsBytes(_wavWithSamples(List<int>.filled(1600, 0)));
    final service = OpenRouterService();
    addTearDown(() async {
      service.dispose();
      await directory.delete(recursive: true);
    });

    await expectLater(
      service.transcribe(file: file, apiKey: 'unused', format: 'wav'),
      throwsA(isA<OpenRouterException>()),
    );
  });

  test('truncated recording is rejected using its expected duration', () async {
    final directory = await Directory.systemTemp.createTemp('openflow_short_');
    final file = File('${directory.path}${Platform.pathSeparator}short.wav');
    await file.writeAsBytes(_wavWithSamples(List<int>.filled(3200, 12)));
    final service = OpenRouterService();
    addTearDown(() async {
      service.dispose();
      await directory.delete(recursive: true);
    });

    await expectLater(
      service.transcribe(
        file: file,
        apiKey: 'unused',
        format: 'wav',
        expectedDurationMs: 5000,
      ),
      throwsA(isA<OpenRouterException>()),
    );
  });

  test('native microphone amplitude produces visible recorder bands', () {
    final silence = RecordingService.frameFromDecibels(-160);
    final speech = RecordingService.frameFromDecibels(-18);

    expect(silence.level, 0);
    expect(silence.bands, everyElement(0));
    expect(speech.level, greaterThan(0));
    expect(speech.bands, hasLength(11));
    expect(speech.bands, everyElement(greaterThan(0)));
  });

  test('usage stats preserve desktop metrics and daily totals', () {
    final entries = [
      TranscriptEntry(
        id: '1',
        text: 'um dois três quatro',
        createdAt: DateTime(2026, 8, 17, 10),
        source: 'Gravação',
        model: OpenRouterService.model,
        durationMs: 2000,
        transcriptionMs: 500,
        costUsd: 0.001,
      ),
      TranscriptEntry(
        id: '2',
        text: 'cinco seis',
        createdAt: DateTime(2026, 8, 18, 10),
        source: 'Gravação',
        model: OpenRouterService.model,
        durationMs: 1000,
        transcriptionMs: 700,
        costUsd: 0.002,
      ),
    ];

    final stats = UsageStats.fromHistory(entries);
    final restored = UsageStats.fromJson(stats.toJson());

    expect(restored.totalTranscriptions, 2);
    expect(restored.totalWords, 6);
    expect(restored.totalDays, 2);
    expect(restored.streakDays, 2);
    expect(restored.averageWpm, 120);
    expect(restored.averageTranscriptionMs, 600);
    expect(restored.totalCostUsd, closeTo(0.003, 0.000001));
    expect(restored.dailyWords['2026-08-18'], 2);
  });
}

List<int> _wavWithOneSample() {
  return _wavWithSamples(<int>[16, 0, ...List<int>.filled(20, 0)]);
}

List<int> _wavWithSamples(List<int> samples) {
  final bytes = List<int>.filled(44 + samples.length, 0);
  void ascii(int offset, String value) {
    bytes.setRange(offset, offset + value.length, value.codeUnits);
  }

  void littleEndian(int offset, int value, int length) {
    for (var index = 0; index < length; index += 1) {
      bytes[offset + index] = (value >> (index * 8)) & 0xff;
    }
  }

  ascii(0, 'RIFF');
  littleEndian(4, bytes.length - 8, 4);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  littleEndian(16, 16, 4);
  littleEndian(20, 1, 2);
  littleEndian(22, 1, 2);
  littleEndian(24, 16000, 4);
  littleEndian(28, 32000, 4);
  littleEndian(32, 2, 2);
  littleEndian(34, 16, 2);
  ascii(36, 'data');
  littleEndian(40, samples.length, 4);
  bytes.setRange(44, bytes.length, samples);
  return bytes;
}
