import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:voxora/src/models/transcript_entry.dart';
import 'package:voxora/src/models/usage_stats.dart';
import 'package:voxora/src/services/openrouter_service.dart';

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
