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

class OpenRouterException implements Exception {
  const OpenRouterException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OpenRouterService {
  OpenRouterService({http.Client? client}) : _client = client ?? http.Client();

  static const model = 'microsoft/mai-transcribe-1.5';
  static final endpoint = Uri.parse(
    'https://openrouter.ai/api/v1/audio/transcriptions',
  );

  final http.Client _client;

  Future<TranscriptionResult> transcribe({
    required File file,
    required String apiKey,
    required String format,
    String languageHint = 'auto',
  }) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const OpenRouterException('O arquivo de áudio está vazio.');
    }

    final body = <String, Object>{
      'model': model,
      'input_audio': <String, String>{
        'data': base64Encode(bytes),
        'format': format,
      },
      'temperature': 0,
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
    );
  }

  static TranscriptionResult decodeResponse(
    http.Response response, {
    required int elapsedMs,
  }) {
    Map<String, dynamic> payload = const {};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A friendly HTTP-specific message is produced below.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final apiMessage = _errorMessageFrom(payload);
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
      model: payload['model'] as String? ?? model,
      transcriptionMs: elapsedMs,
      audioDurationMs: (seconds * 1000).round(),
      costUsd: (usage['cost'] as num?)?.toDouble() ?? 0,
    );
  }

  static String? _errorMessageFrom(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is Map && error['message'] is String) {
      return (error['message'] as String).trim();
    }
    if (payload['message'] is String) {
      return (payload['message'] as String).trim();
    }
    return null;
  }

  void dispose() => _client.close();
}
