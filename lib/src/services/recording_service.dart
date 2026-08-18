import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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
  static const _bandFrequencies = <double>[
    110,
    170,
    250,
    380,
    570,
    850,
    1280,
    1900,
    2850,
    4250,
    6200,
  ];

  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<AudioVisualizationFrame> _visualization =
      StreamController<AudioVisualizationFrame>.broadcast(sync: true);

  StreamSubscription<Uint8List>? _pcmSubscription;
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  IOSink? _pcmSink;
  Completer<void>? _pcmDone;
  String? _streamPath;
  String? _pcmRawPath;
  int _pcmBytes = 0;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);

  Stream<AudioVisualizationFrame> get visualizationStream =>
      _visualization.stream;

  Future<bool> requestPermission() => _recorder.hasPermission();

  Future<RecordingStart> start() async {
    final temp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final supportsPcm = await _recorder.isEncoderSupported(
      AudioEncoder.pcm16bits,
    );

    if (supportsPcm) {
      final path = '${temp.path}${Platform.pathSeparator}openflow_$stamp.wav';
      await _startPcmStream(path);
      return RecordingStart(path: path, format: 'wav');
    }

    final supportsWav = await _recorder.isEncoderSupported(AudioEncoder.wav);
    final encoder = supportsWav ? AudioEncoder.wav : AudioEncoder.aacLc;
    final format = supportsWav ? 'wav' : 'm4a';
    final path = '${temp.path}${Platform.pathSeparator}openflow_$stamp.$format';
    await _recorder.start(_recordConfig(encoder), path: path);
    _amplitudeSubscription = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 90))
        .listen((value) {
          final level = ((value.current + 55) / 55).clamp(0.0, 1.0);
          _visualization.add(
            AudioVisualizationFrame(
              level: level,
              bands: List<double>.filled(_bandFrequencies.length, level),
            ),
          );
        });
    return RecordingStart(path: path, format: format);
  }

  RecordConfig _recordConfig(AudioEncoder encoder) => RecordConfig(
    encoder: encoder,
    sampleRate: _sampleRate,
    numChannels: 1,
    bitRate: 128000,
    autoGain: true,
    echoCancel: true,
    noiseSuppress: true,
    streamBufferSize: 2048,
    androidConfig: const AndroidRecordConfig(
      service: AndroidService(
        title: 'OpenFlow está gravando',
        content: 'Toque no círculo para finalizar.',
      ),
    ),
  );

  Future<void> _startPcmStream(String path) async {
    final rawFile = File('$path.pcm');
    _pcmSink = rawFile.openWrite();
    _streamPath = path;
    _pcmRawPath = rawFile.path;
    _pcmBytes = 0;
    _pcmDone = Completer<void>();

    try {
      final stream = await _recorder.startStream(
        _recordConfig(AudioEncoder.pcm16bits),
      );
      _pcmSubscription = stream.listen(
        (chunk) {
          _pcmSink?.add(chunk);
          _pcmBytes += chunk.length;
          _analyzePcm(chunk);
        },
        onError: (_) {
          if (!(_pcmDone?.isCompleted ?? true)) _pcmDone!.complete();
        },
        onDone: () {
          if (!(_pcmDone?.isCompleted ?? true)) _pcmDone!.complete();
        },
      );
    } catch (_) {
      await _pcmSink?.close();
      _pcmSink = null;
      _streamPath = null;
      _pcmRawPath = null;
      if (await rawFile.exists()) await rawFile.delete();
      rethrow;
    }
  }

  void _analyzePcm(Uint8List chunk) {
    final now = DateTime.now();
    if (now.difference(_lastAnalysis).inMilliseconds < 55) return;
    _lastAnalysis = now;

    final availableSamples = chunk.length ~/ 2;
    if (availableSamples < 64) return;
    final sampleCount = math.min(512, availableSamples);
    final startByte = chunk.length - sampleCount * 2;
    final data = ByteData.sublistView(chunk, startByte);
    final samples = List<double>.filled(sampleCount, 0);
    var squareSum = 0.0;
    for (var index = 0; index < sampleCount; index++) {
      final sample = data.getInt16(index * 2, Endian.little) / 32768.0;
      final window =
          0.5 - 0.5 * math.cos(2 * math.pi * index / (sampleCount - 1));
      samples[index] = sample * window;
      squareSum += sample * sample;
    }

    final rms = math.sqrt(squareSum / sampleCount);
    final db = 20 * math.log(math.max(rms, 1e-8)) / math.ln10;
    final level = ((db + 55) / 55).clamp(0.0, 1.0);
    final energies = _bandFrequencies
        .map((frequency) => _goertzel(samples, frequency))
        .toList(growable: false);
    final peak = energies.fold<double>(0, math.max);
    final compressedLevel = math.sqrt(level);
    final bands = energies
        .map((energy) {
          if (peak <= 1e-12) return 0.0;
          final relative = math.pow(energy / peak, 0.34).toDouble();
          return (relative * compressedLevel).clamp(0.0, 1.0);
        })
        .toList(growable: false);

    _visualization.add(AudioVisualizationFrame(level: level, bands: bands));
  }

  double _goertzel(List<double> samples, double frequency) {
    final omega = 2 * math.pi * frequency / _sampleRate;
    final coefficient = 2 * math.cos(omega);
    var first = 0.0;
    var second = 0.0;
    for (final sample in samples) {
      final next = sample + coefficient * first - second;
      second = first;
      first = next;
    }
    return math.max(
      0,
      first * first + second * second - coefficient * first * second,
    );
  }

  Future<String?> stop() async {
    final fallbackPath = await _recorder.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (_streamPath == null) return fallbackPath;
    return _finishPcmStream(delete: false);
  }

  Future<void> cancel() async {
    await _recorder.cancel();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (_streamPath != null) await _finishPcmStream(delete: true);
  }

  Future<String?> _finishPcmStream({required bool delete}) async {
    final path = _streamPath;
    final rawPath = _pcmRawPath;
    if (path == null) return null;
    try {
      await _pcmDone?.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      await _pcmSubscription?.cancel();
      await _pcmSink?.flush();
      await _pcmSink?.close();
      if (delete) {
        if (rawPath != null) {
          final rawFile = File(rawPath);
          if (await rawFile.exists()) await rawFile.delete();
        }
        return null;
      }
      if (rawPath == null) return null;
      final output = File(path).openWrite();
      output.add(_wavHeader(_pcmBytes));
      await File(rawPath).openRead().pipe(output);
      await File(rawPath).delete();
      return path;
    } finally {
      _pcmSubscription = null;
      _pcmSink = null;
      _pcmDone = null;
      _streamPath = null;
      _pcmRawPath = null;
      _pcmBytes = 0;
      _visualization.add(
        AudioVisualizationFrame(
          level: 0,
          bands: List<double>.filled(_bandFrequencies.length, 0),
        ),
      );
    }
  }

  Uint8List _wavHeader(int dataLength) {
    final header = ByteData(44);
    void ascii(int offset, String value) {
      for (var index = 0; index < value.length; index++) {
        header.setUint8(offset + index, value.codeUnitAt(index));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, _sampleRate, Endian.little);
    header.setUint32(28, _sampleRate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);
    return header.buffer.asUint8List();
  }

  Future<void> dispose() async {
    await _pcmSubscription?.cancel();
    await _amplitudeSubscription?.cancel();
    await _pcmSink?.close();
    await _recorder.dispose();
    await _visualization.close();
  }
}
