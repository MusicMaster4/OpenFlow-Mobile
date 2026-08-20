import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class TranscriptionResult {
  const TranscriptionResult({
    required this.text,
    required this.model,
    required this.transcriptionMs,
    this.audioDurationMs = 0,
    this.costUsd = 0,
  });

  final String text;
  final String model;
  final int transcriptionMs;
  final int audioDurationMs;
  final double costUsd;
}

class TranscriptionModel {
  const TranscriptionModel({
    required this.id,
    required this.name,
    this.description = '',
  });

  final String id;
  final String name;
  final String description;

  String get provider => id.contains('/') ? id.split('/').first : '';

  factory TranscriptionModel.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] as String? ?? '').trim();
    final rawName = (json['name'] as String? ?? '').trim();
    return TranscriptionModel(
      id: id,
      name: rawName.isEmpty ? id : rawName,
      description: (json['description'] as String? ?? '').trim(),
    );
  }
}

class OpenRouterException implements Exception {
  const OpenRouterException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OpenRouterService {
  OpenRouterService({http.Client? client}) : _client = client ?? http.Client();

  static const model = 'microsoft/mai-transcribe-1.5';
  static const defaultModel = model;
  static final endpoint = Uri.parse(
    'https://openrouter.ai/api/v1/audio/transcriptions',
  );
  static final modelsEndpoint = Uri.parse(
    'https://openrouter.ai/api/v1/models?output_modalities=transcription',
  );

  final http.Client _client;

  Future<TranscriptionResult> transcribe({
    required File file,
    required String apiKey,
    required String format,
    String languageHint = 'auto',
    String modelId = defaultModel,
    int expectedDurationMs = 0,
  }) async {
    final bytes = await file.readAsBytes();
    if (!_hasAudioPayload(bytes, format, expectedDurationMs)) {
      throw const OpenRouterException(
        'O microfone não capturou áudio suficiente. Verifique se outro app está usando o microfone e tente novamente.',
      );
    }

    final body = <String, Object>{
      'model': modelId,
      'input_audio': <String, String>{
        'data': base64Encode(bytes),
        'format': format,
      },
    };
    if (languageHint != 'auto') body['language'] = languageHint;

    final startedAt = DateTime.now();
    late http.Response response;
    try {
      response = await _client
          .post(
            endpoint,
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-OpenRouter-Title': 'OpenFlow Mobile',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(minutes: 8));
    } on SocketException {
      throw const OpenRouterException(
        'Sem conexão. Verifique sua internet e tente novamente.',
      );
    } on HttpException {
      throw const OpenRouterException(
        'Não foi possível falar com a OpenRouter.',
      );
    } on TimeoutException {
      throw const OpenRouterException(
        'A transcrição demorou demais. Tente novamente.',
      );
    } on http.ClientException {
      throw const OpenRouterException(
        'Falha de conexão com a OpenRouter. Tente novamente.',
      );
    }

    return decodeResponse(
      response,
      elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
      fallbackModel: modelId,
    );
  }

  Future<List<TranscriptionModel>> listTranscriptionModels({
    String? apiKey,
  }) async {
    late http.Response response;
    try {
      response = await _client
          .get(
            modelsEndpoint,
            headers: {
              'Accept': 'application/json',
              'X-OpenRouter-Title': 'OpenFlow Mobile',
              if (apiKey != null && apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${apiKey.trim()}',
            },
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const OpenRouterException(
        'A lista de modelos demorou demais para carregar.',
      );
    } on SocketException {
      throw const OpenRouterException(
        'Sem conexão para carregar os modelos da OpenRouter.',
      );
    } on http.ClientException {
      throw const OpenRouterException(
        'Não foi possível carregar os modelos da OpenRouter.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw OpenRouterException(
        response.statusCode == 401
            ? 'A chave da OpenRouter não permitiu consultar os modelos.'
            : 'Não foi possível carregar os modelos (HTTP ${response.statusCode}).',
      );
    }

    try {
      final payload = jsonDecode(response.body);
      if (payload is! Map || payload['data'] is! List) {
        throw const FormatException();
      }
      final models = (payload['data'] as List)
          .whereType<Map>()
          .map(
            (item) =>
                TranscriptionModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty)
          .toList();
      models.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return models;
    } on FormatException {
      throw const OpenRouterException(
        'A OpenRouter retornou uma lista de modelos inválida.',
      );
    }
  }

  static TranscriptionResult decodeResponse(
    http.Response response, {
    required int elapsedMs,
    String fallbackModel = defaultModel,
  }) {
    Map<String, dynamic> payload = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A friendly HTTP-specific message is produced below.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final apiMessage = _errorMessageFrom(
        payload,
        statusCode: response.statusCode,
      );
      final friendly = switch (response.statusCode) {
        401 => 'Chave da OpenRouter inválida ou expirada.',
        402 => 'Saldo insuficiente na OpenRouter.',
        413 => 'Esse arquivo é grande demais para a OpenRouter.',
        429 => 'Muitas solicitações. Aguarde um pouco e tente novamente.',
        >= 500 => 'A OpenRouter está indisponível no momento. Tente novamente.',
        _ =>
          apiMessage ?? 'A transcrição falhou (HTTP ${response.statusCode}).',
      };
      throw OpenRouterException(friendly);
    }

    final text = (payload['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      throw const OpenRouterException(
        'A OpenRouter retornou uma transcrição vazia.',
      );
    }

    final usage = payload['usage'] is Map
        ? Map<String, dynamic>.from(payload['usage'] as Map)
        : const <String, dynamic>{};
    final seconds = (usage['seconds'] as num?)?.toDouble() ?? 0;

    return TranscriptionResult(
      text: text,
      model: payload['model'] as String? ?? fallbackModel,
      transcriptionMs: elapsedMs,
      audioDurationMs: (seconds * 1000).round(),
      costUsd: (usage['cost'] as num?)?.toDouble() ?? 0,
    );
  }

  static bool _hasAudioPayload(
    List<int> bytes,
    String format,
    int expectedDurationMs,
  ) {
    if (bytes.length < 64) return false;
    if (format.toLowerCase() != 'wav') return true;

    if (_ascii(bytes, 0, 4) != 'RIFF' || _ascii(bytes, 8, 4) != 'WAVE') {
      return false;
    }

    var byteRate = 0;
    var audioFormat = 0;
    var bitsPerSample = 0;
    for (var index = 12; index + 8 <= bytes.length;) {
      final chunk = _ascii(bytes, index, 4);
      final length = _littleEndian32(bytes, index + 4);
      final dataStart = index + 8;
      final dataEnd = dataStart + length;
      if (length < 0 || dataEnd > bytes.length) return false;

      if (chunk == 'fmt ' && length >= 16) {
        audioFormat = _littleEndian16(bytes, dataStart);
        byteRate = _littleEndian32(bytes, dataStart + 8);
        bitsPerSample = _littleEndian16(bytes, dataStart + 14);
      } else if (chunk == 'data') {
        if (length <= 0) return false;

        // A file much shorter than the duration shown in the UI means Android
        // interrupted/paused capture; sending it only produces empty text.
        if (expectedDurationMs >= 1000 && byteRate > 0) {
          final actualDurationMs = (length * 1000) ~/ byteRate;
          if (actualDurationMs + 500 < expectedDurationMs ~/ 2) return false;
        }

        // This recorder writes 16-bit PCM. Exact zero samples mean that no
        // microphone input reached the encoder (normal room noise is non-zero).
        if (audioFormat == 1 && bitsPerSample == 16) {
          for (var sample = dataStart; sample + 1 < dataEnd; sample += 2) {
            if (bytes[sample] != 0 || bytes[sample + 1] != 0) return true;
          }
          return false;
        }
        return true;
      }
      index += 8 + length + (length.isOdd ? 1 : 0);
    }
    return false;
  }

  static String _ascii(List<int> bytes, int offset, int length) =>
      String.fromCharCodes(bytes.sublist(offset, offset + length));

  static int _littleEndian16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  static int _littleEndian32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  static String? _errorMessageFrom(
    Map<String, dynamic> payload, {
    required int statusCode,
  }) {
    final error = payload['error'];
    if (error is Map && error['message'] is String) {
      final message = (error['message'] as String).trim();
      if (statusCode == 400 &&
          RegExp(
            r'^provider returned(?: an error| 400)?$',
            caseSensitive: false,
          ).hasMatch(message)) {
        return 'O provedor recusou o áudio. Use WAV, MP3 ou FLAC e tente novamente.';
      }
      return message;
    }
    if (payload['message'] is String) {
      return (payload['message'] as String).trim();
    }
    return null;
  }

  void dispose() => _client.close();
}
