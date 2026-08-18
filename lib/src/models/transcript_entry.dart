class TranscriptEntry {
  const TranscriptEntry({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.source,
    required this.model,
    this.durationMs = 0,
    this.transcriptionMs = 0,
    this.costUsd = 0,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final String source;
  final String model;
  final int durationMs;
  final int transcriptionMs;
  final double costUsd;

  Map<String, Object> toJson() => {
    'id': id,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'source': source,
    'model': model,
    'durationMs': durationMs,
    'transcriptionMs': transcriptionMs,
    'costUsd': costUsd,
  };

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) {
    return TranscriptEntry(
      id: json['id'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      source: json['source'] as String? ?? 'Áudio',
      model: json['model'] as String? ?? 'microsoft/mai-transcribe-1.5',
      durationMs: (json['durationMs'] as num?)?.round() ?? 0,
      transcriptionMs: (json['transcriptionMs'] as num?)?.round() ?? 0,
      costUsd: (json['costUsd'] as num?)?.toDouble() ?? 0,
    );
  }
}
