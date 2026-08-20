import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/transcript_entry.dart';
import '../models/usage_stats.dart';
import '../services/app_update_service.dart';
import '../services/floating_overlay_service.dart';
import '../services/local_storage_service.dart';
import '../services/openrouter_service.dart';
import '../services/recording_service.dart';

enum VoxoraActivity { idle, recording, transcribing }

class VoxoraController extends ChangeNotifier {
  VoxoraController({
    required LocalStorageService storage,
    required OpenRouterService openRouter,
    required RecordingService recording,
    required FloatingOverlayService floatingOverlay,
    AppUpdateService? updates,
  }) : _storage = storage,
       _openRouter = openRouter,
       _recording = recording,
       _floatingOverlay = floatingOverlay,
       updates = updates ?? AppUpdateService();

  final LocalStorageService _storage;
  final OpenRouterService _openRouter;
  final RecordingService _recording;
  final FloatingOverlayService _floatingOverlay;
  final AppUpdateService updates;

  final List<TranscriptEntry> _history = [];
  String? _apiKey;
  RecordingStart? _activeRecording;
  Timer? _recordingTimer;
  StreamSubscription<AudioVisualizationFrame>? _visualizationSubscription;
  DateTime? _recordingStartedAt;
  bool _pendingOverlayEnable = false;
  bool _recordingFromOverlay = false;
  UsageStats _usageStats = const UsageStats();
  final List<TranscriptionModel> _transcriptionModels = [];

  VoxoraActivity activity = VoxoraActivity.idle;
  bool autoCopy = true;
  bool autoPaste = false;
  bool floatingOverlayEnabled = false;
  bool overlayPermissionGranted = false;
  bool accessibilityEnabled = false;
  bool notificationPolicyAccessGranted = false;
  bool soundEffectsEnabled = true;
  bool silenceWhileRecording = true;
  String languageHint = 'auto';
  String transcriptionModel = OpenRouterService.defaultModel;
  bool isLoadingTranscriptionModels = false;
  String? transcriptionModelsError;
  int recordingDurationMs = 0;
  double amplitude = 0;
  List<double> audioBands = List<double>.filled(11, 0);
  String activeSource = '';
  String? feedback;
  bool feedbackIsError = false;
  int feedbackSerial = 0;

  List<TranscriptEntry> get history => List.unmodifiable(_history);
  List<TranscriptionModel> get transcriptionModels =>
      List.unmodifiable(_transcriptionModels);
  UsageStats get usageStats => _usageStats;
  TranscriptEntry? get latest => _history.isEmpty ? null : _history.first;
  bool get hasApiKey => _apiKey?.isNotEmpty ?? false;
  bool get isRecording => activity == VoxoraActivity.recording;
  bool get isTranscribing => activity == VoxoraActivity.transcribing;
  bool get isBusy => activity != VoxoraActivity.idle;
  String get transcriptionModelLabel {
    for (final model in _transcriptionModels) {
      if (model.id == transcriptionModel) return model.name;
    }
    return transcriptionModel;
  }

  Future<void> initialize() async {
    await _floatingOverlay.initialize(_handleOverlayAction);
    await updates.initialize();
    final values = await Future.wait<Object?>([
      _storage.loadHistory(),
      _storage.loadAutoCopy(),
      _storage.loadLanguageHint(),
      _storage.readApiKey(),
      _storage.loadFloatingOverlay(),
      _storage.loadAutoPaste(),
      _storage.loadSoundEffects(),
      _storage.loadSilenceWhileRecording(),
      _storage.loadUsageStats(),
      _storage.loadTranscriptionModel(),
    ]);
    _history
      ..clear()
      ..addAll(values[0] as List<TranscriptEntry>);
    autoCopy = values[1] as bool;
    languageHint = values[2] as String;
    _apiKey = (values[3] as String?)?.trim();
    autoPaste = values[5] as bool;
    soundEffectsEnabled = values[6] as bool;
    silenceWhileRecording = values[7] as bool;
    _usageStats = values[8] as UsageStats? ?? UsageStats.fromHistory(_history);
    transcriptionModel = values[9] as String;
    if (values[8] == null && _history.isNotEmpty) {
      await _storage.saveUsageStats(_usageStats);
    }
    overlayPermissionGranted = await _floatingOverlay.canDrawOverlays();
    accessibilityEnabled = await _floatingOverlay.isAccessibilityEnabled();
    notificationPolicyAccessGranted = await _floatingOverlay
        .hasNotificationPolicyAccess();

    final shouldRunOverlay = values[4] as bool;
    if (shouldRunOverlay && overlayPermissionGranted) {
      floatingOverlayEnabled = await _floatingOverlay.start();
      if (floatingOverlayEnabled) await _syncOverlay();
    } else if (shouldRunOverlay) {
      await _storage.saveFloatingOverlay(false);
    }
  }

  Future<bool> saveApiKey(String value) async {
    final normalized = value.trim();
    if (normalized.length < 20) {
      _setFeedback('Cole uma chave válida da OpenRouter.', isError: true);
      return false;
    }
    try {
      await _storage.saveApiKey(normalized);
      _apiKey = normalized;
      _setFeedback('Chave salva com segurança.');
      return true;
    } catch (_) {
      _setFeedback(
        'Não foi possível salvar a chave neste aparelho.',
        isError: true,
      );
      return false;
    }
  }

  Future<void> deleteApiKey() async {
    if (isBusy) return;
    if (floatingOverlayEnabled) {
      await _floatingOverlay.stop();
      floatingOverlayEnabled = false;
      await _storage.saveFloatingOverlay(false);
    }
    await _storage.deleteApiKey();
    _apiKey = null;
    _setFeedback('Chave removida.');
  }

  Future<void> setAutoCopy(bool value) async {
    autoCopy = value;
    notifyListeners();
    await _storage.saveAutoCopy(value);
  }

  Future<void> setLanguageHint(String value) async {
    languageHint = value;
    notifyListeners();
    await _storage.saveLanguageHint(value);
  }

  Future<void> setTranscriptionModel(String value) async {
    final normalized = value.trim();
    if (normalized.isEmpty || isBusy) return;
    transcriptionModel = normalized;
    transcriptionModelsError = null;
    notifyListeners();
    await _storage.saveTranscriptionModel(normalized);
    _setFeedback('Modelo de transcrição atualizado.');
  }

  Future<void> loadTranscriptionModels({bool force = false}) async {
    if (isLoadingTranscriptionModels ||
        (!force && _transcriptionModels.isNotEmpty)) {
      return;
    }
    isLoadingTranscriptionModels = true;
    transcriptionModelsError = null;
    notifyListeners();
    try {
      final models = await _openRouter.listTranscriptionModels(apiKey: _apiKey);
      _transcriptionModels
        ..clear()
        ..addAll(models);
      if (models.isEmpty) {
        transcriptionModelsError =
            'Nenhum modelo de transcrição está disponível agora.';
      }
    } catch (error) {
      transcriptionModelsError = _cleanError(error);
    } finally {
      isLoadingTranscriptionModels = false;
      notifyListeners();
    }
  }

  Future<void> setFloatingOverlayEnabled(bool value) async {
    if (value) {
      if (!_ensureApiKey()) return;
      final microphoneAllowed = await _recording.requestPermission();
      if (!microphoneAllowed) {
        _setFeedback(
          'Autorize o microfone antes de ativar o círculo flutuante.',
          isError: true,
        );
        return;
      }
      overlayPermissionGranted = await _floatingOverlay.canDrawOverlays();
      if (!overlayPermissionGranted) {
        _pendingOverlayEnable = true;
        await _floatingOverlay.requestOverlayPermission();
        _setFeedback('Autorize “exibir sobre outros apps” para o OpenFlow.');
        return;
      }
      floatingOverlayEnabled = await _floatingOverlay.start();
      await _storage.saveFloatingOverlay(floatingOverlayEnabled);
      if (floatingOverlayEnabled) {
        await _syncOverlay();
        _setFeedback('Círculo flutuante ativado.');
      }
    } else {
      _pendingOverlayEnable = false;
      await _floatingOverlay.stop();
      floatingOverlayEnabled = false;
      await _storage.saveFloatingOverlay(false);
      _setFeedback('Círculo flutuante desativado.');
    }
    notifyListeners();
  }

  Future<void> setAutoPaste(bool value) async {
    autoPaste = value;
    await _storage.saveAutoPaste(value);
    if (value) {
      accessibilityEnabled = await _floatingOverlay.isAccessibilityEnabled();
      if (!accessibilityEnabled) {
        _setFeedback('Conclua os dois passos exibidos para liberar a colagem.');
      }
    }
    notifyListeners();
  }

  Future<void> openAppDetailsSettings() =>
      _floatingOverlay.openAppDetailsSettings();

  Future<void> openAccessibilitySettings() =>
      _floatingOverlay.openAccessibilitySettings();

  Future<void> openNotificationPolicySettings() =>
      _floatingOverlay.openNotificationPolicySettings();

  Future<void> setSoundEffectsEnabled(bool value) async {
    soundEffectsEnabled = value;
    notifyListeners();
    await _storage.saveSoundEffects(value);
    if (value) await _floatingOverlay.playFeedback('loaded');
  }

  Future<void> setSilenceWhileRecording(bool value) async {
    silenceWhileRecording = value;
    notifyListeners();
    await _storage.saveSilenceWhileRecording(value);
    if (isRecording) {
      await _floatingOverlay.setRecordingActive(
        active: true,
        silence: silenceWhileRecording,
      );
    }
  }

  Future<void> refreshSystemIntegrations() async {
    overlayPermissionGranted = await _floatingOverlay.canDrawOverlays();
    accessibilityEnabled = await _floatingOverlay.isAccessibilityEnabled();
    notificationPolicyAccessGranted = await _floatingOverlay
        .hasNotificationPolicyAccess();
    if (_pendingOverlayEnable && overlayPermissionGranted) {
      _pendingOverlayEnable = false;
      floatingOverlayEnabled = await _floatingOverlay.start();
      await _storage.saveFloatingOverlay(floatingOverlayEnabled);
      if (floatingOverlayEnabled) {
        await _syncOverlay();
        _setFeedback('Círculo flutuante ativado.');
      }
    } else {
      floatingOverlayEnabled = await _floatingOverlay.isRunning();
      final shouldRunOverlay = await _storage.loadFloatingOverlay();
      if (shouldRunOverlay &&
          overlayPermissionGranted &&
          !floatingOverlayEnabled) {
        floatingOverlayEnabled = await _floatingOverlay.start();
        if (floatingOverlayEnabled) await _syncOverlay();
      }
    }
    await updates.onAppResumed();
    notifyListeners();
  }

  Future<void> startRecording({bool fromOverlay = false}) async {
    if (isBusy) return;
    if (!_ensureApiKey()) {
      if (fromOverlay) await _floatingOverlay.showError();
      return;
    }

    try {
      final allowed = fromOverlay
          ? await _floatingOverlay.hasRecordAudioPermission()
          : await _recording.requestPermission();
      if (!allowed) {
        _setFeedback(
          'Autorize o acesso ao microfone para começar a gravar.',
          isError: true,
        );
        if (fromOverlay) await _floatingOverlay.showError();
        return;
      }

      _activeRecording = await _recording.start();
      _recordingStartedAt = DateTime.now();
      recordingDurationMs = 0;
      amplitude = 0;
      audioBands = List<double>.filled(11, 0);
      activity = VoxoraActivity.recording;
      activeSource = 'Gravação';
      _recordingFromOverlay = fromOverlay;
      if (soundEffectsEnabled) {
        await _floatingOverlay.playFeedback('start');
      }
      await _floatingOverlay.setRecordingActive(
        active: true,
        silence: silenceWhileRecording,
      );
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final startedAt = _recordingStartedAt;
        if (startedAt == null) return;
        recordingDurationMs = DateTime.now()
            .difference(startedAt)
            .inMilliseconds;
        notifyListeners();
      });
      await _visualizationSubscription?.cancel();
      _visualizationSubscription = _recording.visualizationStream.listen((
        frame,
      ) {
        amplitude = frame.level;
        audioBands = frame.bands;
        unawaited(_syncOverlay());
        notifyListeners();
      });
      await _syncOverlay();
      notifyListeners();
    } catch (error) {
      await _floatingOverlay.setRecordingActive(active: false, silence: false);
      _resetRecordingState();
      if (fromOverlay) await _floatingOverlay.showError();
      _setFeedback(
        'Não foi possível iniciar a gravação: ${_cleanError(error)}',
        isError: true,
      );
    }
  }

  Future<void> stopAndTranscribe() async {
    if (!isRecording) return;
    final active = _activeRecording;
    final capturedDuration = recordingDurationMs;
    String? temporaryPath = active?.path;

    try {
      final stoppedPath = await _recording.stop();
      await _floatingOverlay.setRecordingActive(active: false, silence: false);
      if (soundEffectsEnabled) {
        await _floatingOverlay.playFeedback('close');
      }
      await _stopRecordingSignals();
      activity = VoxoraActivity.transcribing;
      activeSource = 'Gravação';
      amplitude = 0;
      audioBands = List<double>.filled(11, 0);
      await _syncOverlay();
      notifyListeners();

      final path = stoppedPath ?? active?.path;
      if (path == null) {
        throw const OpenRouterException(
          'A gravação não gerou um arquivo de áudio.',
        );
      }
      temporaryPath = path;
      await _transcribeFile(
        File(path),
        source: 'Gravação',
        format: active?.format ?? _formatFromPath(path),
        recordedDurationMs: capturedDuration,
      );
    } catch (error) {
      if (_recordingFromOverlay) await _floatingOverlay.showError();
      _setFeedback(_cleanError(error), isError: true);
    } finally {
      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {
          // Temporary recording cleanup is best effort.
        }
      }
      _resetRecordingState();
      _recordingFromOverlay = false;
      await _floatingOverlay.setRecordingActive(active: false, silence: false);
      await _syncOverlay();
      notifyListeners();
    }
  }

  Future<void> cancelRecording() async {
    if (!isRecording) return;
    try {
      await _floatingOverlay.setRecordingActive(active: false, silence: false);
      if (soundEffectsEnabled) {
        await _floatingOverlay.playFeedback('cancel');
      }
      await _recording.cancel();
      _setFeedback('Gravação cancelada.');
    } catch (_) {
      _setFeedback('A gravação foi interrompida.', isError: true);
    } finally {
      await _stopRecordingSignals();
      _resetRecordingState();
      _recordingFromOverlay = false;
      await _floatingOverlay.setRecordingActive(active: false, silence: false);
      await _syncOverlay();
      notifyListeners();
    }
  }

  Future<void> pickAndTranscribeAudio() async {
    if (isBusy) return;
    if (!_ensureApiKey()) return;

    try {
      final selected = await FilePicker.pickFile(type: FileType.audio);
      if (selected == null) return;
      final path = selected.path;
      if (path == null || path.isEmpty) {
        throw const OpenRouterException(
          'Não foi possível acessar esse arquivo.',
        );
      }

      final format = _formatFromPath(selected.name);
      activity = VoxoraActivity.transcribing;
      activeSource = selected.name;
      await _syncOverlay();
      notifyListeners();
      await _transcribeFile(File(path), source: selected.name, format: format);
    } catch (error) {
      _setFeedback(_cleanError(error), isError: true);
    } finally {
      activity = VoxoraActivity.idle;
      activeSource = '';
      await _syncOverlay();
      notifyListeners();
    }
  }

  Future<void> _transcribeFile(
    File file, {
    required String source,
    required String format,
    int recordedDurationMs = 0,
  }) async {
    final apiKey = _apiKey;
    if (apiKey == null) {
      throw const OpenRouterException('Configure sua chave da OpenRouter.');
    }

    final result = await _openRouter.transcribe(
      file: file,
      apiKey: apiKey,
      format: format,
      languageHint: languageHint,
      modelId: transcriptionModel,
      expectedDurationMs: recordedDurationMs,
    );
    final entry = TranscriptEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: result.text,
      createdAt: DateTime.now(),
      source: source,
      model: result.model,
      durationMs: recordedDurationMs > 0
          ? recordedDurationMs
          : result.audioDurationMs,
      transcriptionMs: result.transcriptionMs,
      costUsd: result.costUsd,
    );
    _history.insert(0, entry);
    if (_history.length > 100) _history.removeRange(100, _history.length);
    await _storage.saveHistory(_history);
    _usageStats = _usageStats.add(entry);
    await _storage.saveUsageStats(_usageStats);

    var copied = autoCopy;
    if (copied && _recordingFromOverlay) {
      copied = await _floatingOverlay.copyText(entry.text);
    } else if (copied) {
      await Clipboard.setData(ClipboardData(text: entry.text));
    }

    var pasted = false;
    if (_recordingFromOverlay && autoPaste) {
      accessibilityEnabled = await _floatingOverlay.isAccessibilityEnabled();
      if (accessibilityEnabled) {
        pasted = await _floatingOverlay.pasteText(
          entry.text,
          keepInClipboard: autoCopy,
        );
      }
    }
    _setFeedback(
      pasted
          ? 'Transcrição pronta e colada.'
          : copied
          ? 'Transcrição pronta e copiada.'
          : 'Transcrição pronta.',
    );
    if (soundEffectsEnabled && !pasted) {
      await _floatingOverlay.playFeedback('loaded');
    }
  }

  Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _setFeedback('Texto copiado.');
  }

  Future<void> deleteEntry(String id) async {
    _history.removeWhere((entry) => entry.id == id);
    notifyListeners();
    await _storage.saveHistory(_history);
  }

  Future<void> clearHistory() async {
    _history.clear();
    notifyListeners();
    await _storage.saveHistory(_history);
  }

  Future<void> resetUsageStats() async {
    _usageStats = const UsageStats();
    notifyListeners();
    await _storage.saveUsageStats(_usageStats);
    _setFeedback('Estatísticas zeradas.');
  }

  bool _ensureApiKey() {
    if (hasApiKey) return true;
    _setFeedback(
      'Adicione sua chave da OpenRouter nas configurações.',
      isError: true,
    );
    return false;
  }

  Future<void> _stopRecordingSignals() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    await _visualizationSubscription?.cancel();
    _visualizationSubscription = null;
  }

  void _resetRecordingState() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _recordingStartedAt = null;
    _activeRecording = null;
    recordingDurationMs = 0;
    amplitude = 0;
    audioBands = List<double>.filled(11, 0);
    activeSource = '';
    activity = VoxoraActivity.idle;
  }

  Future<void> _handleOverlayAction(String action) async {
    switch (action) {
      case 'toggle':
        if (isRecording) {
          await stopAndTranscribe();
        } else if (!isBusy) {
          await startRecording(fromOverlay: true);
        }
      case 'cancel':
        if (isRecording) await cancelRecording();
      case 'dismiss':
        floatingOverlayEnabled = false;
        // Keep the saved preference enabled: dragging to the target only hides
        // this service instance, so the overlay returns when the app is opened.
        notifyListeners();
    }
  }

  Future<void> _syncOverlay() => _floatingOverlay.update(
    state: switch (activity) {
      VoxoraActivity.idle => 'idle',
      VoxoraActivity.recording => 'recording',
      VoxoraActivity.transcribing => 'transcribing',
    },
    level: amplitude,
    bands: audioBands,
  );

  void _setFeedback(String message, {bool isError = false}) {
    feedback = message;
    feedbackIsError = isError;
    feedbackSerial += 1;
    notifyListeners();
  }

  static String _formatFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      throw const OpenRouterException(
        'Escolha um áudio WAV, MP3, M4A, AAC, FLAC, OGG ou WebM.',
      );
    }
    final extension = path.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'wav' ||
      'mp3' ||
      'flac' ||
      'm4a' ||
      'ogg' ||
      'webm' ||
      'aac' => extension,
      'mpeg' => 'mp3',
      'mp4' => 'm4a',
      'opus' || 'oga' => 'ogg',
      _ => throw const OpenRouterException(
        'Formato não compatível. Use WAV, MP3, M4A, AAC, FLAC, OGG ou WebM.',
      ),
    };
  }

  static String _cleanError(Object error) {
    if (error is OpenRouterException) return error.message;
    final value = error.toString().replaceFirst(
      RegExp(r'^(Exception|FileSystemException):\s*'),
      '',
    );
    return value.isEmpty ? 'Algo deu errado. Tente novamente.' : value;
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    unawaited(_visualizationSubscription?.cancel());
    unawaited(_recording.dispose());
    _openRouter.dispose();
    super.dispose();
  }
}
