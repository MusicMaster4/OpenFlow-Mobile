import 'transcript_entry.dart';

class UsageStats {
  const UsageStats({
    this.activeDays = const [],
    this.totalTranscriptions = 0,
    this.totalWords = 0,
    this.totalAudioMs = 0,
    this.totalTranscriptionMs = 0,
    this.totalCostUsd = 0,
    this.dailyWords = const {},
  });

  final List<String> activeDays;
  final int totalTranscriptions;
  final int totalWords;
  final int totalAudioMs;
  final int totalTranscriptionMs;
  final double totalCostUsd;
  final Map<String, int> dailyWords;

  int get totalDays => activeDays.length;

  double get averageWpm => totalAudioMs > 0
      ? totalWords * Duration.millisecondsPerMinute / totalAudioMs
      : 0;

  double get averageTranscriptionMs =>
      totalTranscriptions > 0 ? totalTranscriptionMs / totalTranscriptions : 0;

  int get streakDays {
    if (activeDays.isEmpty) return 0;
    var streak = 1;
    for (var index = activeDays.length - 1; index > 0; index--) {
      final previous = DateTime.tryParse(activeDays[index - 1]);
      final next = DateTime.tryParse(activeDays[index]);
      if (previous == null ||
          next == null ||
          next.difference(previous).inDays != 1) {
        break;
      }
      streak++;
    }
    return streak;
  }

  int get estimatedTimeSavedMs {
    if (totalWords == 0) return 0;
    const typingWordsPerMinute = 40;
    final typingMs =
        totalWords * Duration.millisecondsPerMinute ~/ typingWordsPerMinute;
    return (typingMs - totalAudioMs).clamp(0, 1 << 62);
  }

  UsageStats add(TranscriptEntry entry) {
    final day = dayKey(entry.createdAt);
    final words = countWords(entry.text);
    final days = {...activeDays, day}.toList()..sort();
    final wordsByDay = Map<String, int>.from(dailyWords);
    wordsByDay[day] = (wordsByDay[day] ?? 0) + words;
    return UsageStats(
      activeDays: List.unmodifiable(days),
      totalTranscriptions: totalTranscriptions + 1,
      totalWords: totalWords + words,
      totalAudioMs: totalAudioMs + entry.durationMs,
      totalTranscriptionMs: totalTranscriptionMs + entry.transcriptionMs,
      totalCostUsd: totalCostUsd + entry.costUsd,
      dailyWords: Map.unmodifiable(wordsByDay),
    );
  }

  Map<String, Object> toJson() => {
    'activeDays': activeDays,
    'totalTranscriptions': totalTranscriptions,
    'totalWords': totalWords,
    'totalAudioMs': totalAudioMs,
    'totalTranscriptionMs': totalTranscriptionMs,
    'totalCostUsd': totalCostUsd,
    'dailyWords': dailyWords,
  };

  factory UsageStats.fromJson(Map<String, dynamic> json) {
    final days =
        (json['activeDays'] as List?)
            ?.whereType<String>()
            .where((value) => DateTime.tryParse(value) != null)
            .toSet()
            .toList() ??
        <String>[];
    days.sort();
    final dailyWords = <String, int>{};
    final rawDailyWords = json['dailyWords'];
    if (rawDailyWords is Map) {
      for (final entry in rawDailyWords.entries) {
        final value = entry.value;
        if (value is num && DateTime.tryParse(entry.key.toString()) != null) {
          dailyWords[entry.key.toString()] = value.round().clamp(0, 1 << 31);
        }
      }
    }
    return UsageStats(
      activeDays: List.unmodifiable(days),
      totalTranscriptions:
          (json['totalTranscriptions'] as num?)?.round().clamp(0, 1 << 31) ?? 0,
      totalWords: (json['totalWords'] as num?)?.round().clamp(0, 1 << 31) ?? 0,
      totalAudioMs:
          (json['totalAudioMs'] as num?)?.round().clamp(0, 1 << 62) ?? 0,
      totalTranscriptionMs:
          (json['totalTranscriptionMs'] as num?)?.round().clamp(0, 1 << 62) ??
          0,
      totalCostUsd: (json['totalCostUsd'] as num?)?.toDouble() ?? 0,
      dailyWords: Map.unmodifiable(dailyWords),
    );
  }

  factory UsageStats.fromHistory(Iterable<TranscriptEntry> entries) {
    var result = const UsageStats();
    for (final entry in entries.toList().reversed) {
      result = result.add(entry);
    }
    return result;
  }

  static int countWords(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return 0;
    return normalized.split(RegExp(r'\s+')).length;
  }

  static String dayKey(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
