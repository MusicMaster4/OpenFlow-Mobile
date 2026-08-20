import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class RecordingStart {
  const RecordingStart({required this.path, required this.format});
  final String path;
  final String format;
}

class AudioVisualizationFrame {
  const AudioVisualizationFrame({required this.level, required this.bands});

  final double level;
  final List<double> bands;
}

class RecordingService {
  static const _sampleRate = 16000;
  static const _bandWeights = <double>[
    0.58,
    0.72,
    0.86,
    0.96,
    1.0,
    0.94,
    0.88,
    0.80,
    0.72,
    0.64,
    0.56,
  ];

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<AudioVisualizationFrame> _visualization =
      StreamController<AudioVisualizationFrame>.broadcast(sync: true);

  StreamSubscription<Amplitude>? _amplitudeSubscription;

  Stream<AudioVisualizationFrame> get visualizationStream =>
      _visualization.stream;

  Future<bool> requestPermission() => _recorder.hasPermission();

  Future<RecordingStart> start() async {
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // MAI-Transcribe 1.5 accepts WAV, MP3, or FLAC. Android's native AAC
    // recorder writes an M4A container, which Azure rejects with HTTP 400.
    // PCM/WAV is supported natively by the record package and also gives the
    // transcription provider the least ambiguous input possible.
    const encoder = AudioEncoder.wav;
    const format = 'wav';
    final path = '${temp.path}${Platform.pathSeparator}openflow_$stamp.$format';
    await _recorder.start(debugRecordConfig(encoder), path: path);
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen(
          (value) => _visualization.add(frameFromDecibels(value.current)),
        );
    return RecordingStart(path: path, format: format);
  }

  @visibleForTesting
  static RecordConfig debugRecordConfig(AudioEncoder encoder) => RecordConfig(
    encoder: encoder,
    sampleRate: _sampleRate,
    numChannels: 1,
    bitRate: 128000,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    // The app's silencer deliberately takes exclusive audio focus shortly
    // after capture starts. The package default (`pause`) would therefore
    // pause our own recorder and leave a silent/header-only WAV.
    audioInterruption: AudioInterruptionMode.none,
    streamBufferSize: 2048,
    androidConfig: AndroidRecordConfig(
      useLegacy: false,
      audioSource: AndroidAudioSource.mic,
      service: const AndroidService(
        title: 'OpenFlow está gravando',
        content: 'Toque no círculo para finalizar.',
      ),
    ),
  );

  static AudioVisualizationFrame frameFromDecibels(double decibels) {
    final level = ((decibels + 55) / 55).clamp(0.0, 1.0);
    final visualLevel = math.sqrt(level);
    return AudioVisualizationFrame(
      level: level,
      bands: _bandWeights
          .map((weight) => (visualLevel * weight).clamp(0.0, 1.0))
          .toList(growable: false),
    );
  }

  Future<String?> stop() async {
    final path = await _recorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _emitSilence();
    return path;
  }

  Future<void> cancel() async {
    await _recorder.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    _emitSilence();
  }

  void _emitSilence() {
    if (_visualization.isClosed) return;
    _visualization.add(
      AudioVisualizationFrame(
        level: 0,
        bands: List<double>.filled(_bandWeights.length, 0),
      ),
    );
  }

  Future<void> dispose() async {
    await _amplitudeSubscription?.cancel();
    await _recorder.dispose();
    await _visualization.close();
  }
}
