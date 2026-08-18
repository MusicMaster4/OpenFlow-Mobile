import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum AppUpdatePhase {
  idle,
  checking,
  current,
  available,
  downloading,
  awaitingPermission,
  readyToInstall,
  installing,
  failed,
}

class AppBuildInfo {
  const AppBuildInfo({
    required this.versionName,
    required this.versionCode,
    required this.channel,
  });

  final String versionName;
  final int versionCode;
  final String channel;

  String get channelLabel => channel == 'testing' ? 'beta' : 'stable';

  factory AppBuildInfo.fromMap(Map<Object?, Object?> raw) {
    final channel = raw['channel'] as String? ?? 'stable';
    if (channel != 'stable' && channel != 'testing') {
      throw const FormatException('Canal de atualização desconhecido.');
    }
    return AppBuildInfo(
      versionName: raw['versionName'] as String? ?? '0.0.0',
      versionCode: (raw['versionCode'] as num?)?.toInt() ?? 0,
      channel: channel,
    );
  }
}

class AvailableAppUpdate {
  const AvailableAppUpdate({
    required this.versionName,
    required this.versionCode,
    required this.channel,
    required this.apkUrl,
    required this.sha256,
  });

  final String versionName;
  final int versionCode;
  final String channel;
  final String apkUrl;
  final String sha256;

  factory AvailableAppUpdate.fromMap(
    Map<Object?, Object?> raw, {
    required String expectedChannel,
    required int installedVersionCode,
  }) {
    final channel = raw['channel'] as String?;
    final versionCode = (raw['versionCode'] as num?)?.toInt();
    if (channel != expectedChannel) {
      throw const FormatException(
        'A atualização pertence a outro canal e foi recusada.',
      );
    }
    if (versionCode == null || versionCode <= installedVersionCode) {
      throw const FormatException('A atualização não é mais recente.');
    }
    final sha256 = raw['sha256'] as String? ?? '';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('A assinatura da atualização é inválida.');
    }
    return AvailableAppUpdate(
      versionName: raw['versionName'] as String? ?? '0.0.0',
      versionCode: versionCode,
      channel: channel!,
      apkUrl: raw['apkUrl'] as String? ?? '',
      sha256: sha256,
    );
  }

  Map<String, Object> toMap() => {
    'versionName': versionName,
    'versionCode': versionCode,
    'channel': channel,
    'apkUrl': apkUrl,
    'sha256': sha256,
  };
}

class AppUpdateService extends ChangeNotifier {
  AppUpdateService() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  static const _channel = MethodChannel('openflow/update');
  static const _compiledVersion = String.fromEnvironment(
    'OPENFLOW_VERSION',
    defaultValue: '2.0.0',
  );
  static const _compiledVersionCode = int.fromEnvironment(
    'OPENFLOW_VERSION_CODE',
    defaultValue: 3,
  );
  static const _compiledChannel = String.fromEnvironment(
    'OPENFLOW_CHANNEL',
    defaultValue: 'stable',
  );

  AppBuildInfo build = const AppBuildInfo(
    versionName: _compiledVersion,
    versionCode: _compiledVersionCode,
    channel: _compiledChannel,
  );
  AvailableAppUpdate? available;
  AppUpdatePhase phase = AppUpdatePhase.idle;
  double? progress;
  String? errorMessage;

  bool get isSupported => Platform.isAndroid;
  bool get isBusy =>
      phase == AppUpdatePhase.checking ||
      phase == AppUpdatePhase.downloading ||
      phase == AppUpdatePhase.installing;

  Future<void> initialize() async {
    if (!isSupported) return;
    try {
      final raw = await _channel.invokeMethod<Object?>('getAppInfo');
      if (raw is Map) build = AppBuildInfo.fromMap(raw);
    } catch (_) {
      // Compile-time values keep About useful even if Android is unavailable.
    }
  }

  Future<void> check() async {
    if (!isSupported || isBusy) return;
    phase = AppUpdatePhase.checking;
    errorMessage = null;
    available = null;
    progress = null;
    notifyListeners();
    try {
      final raw = await _channel.invokeMethod<Object?>('checkForUpdate');
      if (raw == null) {
        phase = AppUpdatePhase.current;
      } else if (raw is Map) {
        available = AvailableAppUpdate.fromMap(
          raw,
          expectedChannel: build.channel,
          installedVersionCode: build.versionCode,
        );
        phase = AppUpdatePhase.available;
      } else {
        throw const FormatException('Resposta de atualização inválida.');
      }
    } catch (error) {
      _fail(error);
    }
    notifyListeners();
  }

  Future<void> downloadAndInstall() async {
    final update = available;
    if (!isSupported || update == null || isBusy) return;
    phase = AppUpdatePhase.downloading;
    progress = null;
    errorMessage = null;
    notifyListeners();
    try {
      await _channel.invokeMethod<Object?>('downloadUpdate', update.toMap());
      phase = AppUpdatePhase.installing;
      notifyListeners();
      await _openInstaller();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> continueInstallation() async {
    if (!isSupported ||
        (phase != AppUpdatePhase.awaitingPermission &&
            phase != AppUpdatePhase.readyToInstall)) {
      return;
    }
    phase = AppUpdatePhase.installing;
    errorMessage = null;
    notifyListeners();
    try {
      await _openInstaller();
    } catch (error) {
      _fail(error);
      notifyListeners();
    }
  }

  Future<void> onAppResumed() async {
    if (!isSupported) return;
    if (phase == AppUpdatePhase.installing) {
      phase = AppUpdatePhase.readyToInstall;
      notifyListeners();
      return;
    }
    if (phase != AppUpdatePhase.awaitingPermission) return;
    try {
      final granted =
          await _channel.invokeMethod<bool>('hasInstallPermission') ?? false;
      if (granted) {
        phase = AppUpdatePhase.readyToInstall;
        notifyListeners();
      }
    } catch (_) {
      // The explicit Continue button can retry the permission check.
    }
  }

  Future<void> _openInstaller() async {
    final raw = await _channel.invokeMethod<Object?>('installDownloadedUpdate');
    final permissionRequired = raw is Map && raw['permissionRequired'] == true;
    phase = permissionRequired
        ? AppUpdatePhase.awaitingPermission
        : AppUpdatePhase.installing;
    notifyListeners();
  }

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method != 'downloadProgress') return;
    final raw = call.arguments;
    if (raw is! Map || phase != AppUpdatePhase.downloading) return;
    final received = (raw['received'] as num?)?.toDouble() ?? 0;
    final total = (raw['total'] as num?)?.toDouble() ?? 0;
    progress = total > 0 ? (received / total).clamp(0, 1) : null;
    notifyListeners();
  }

  void _fail(Object error) {
    phase = AppUpdatePhase.failed;
    if (error is PlatformException && error.message?.isNotEmpty == true) {
      errorMessage = error.message;
    } else if (error is FormatException) {
      errorMessage = error.message;
    } else {
      errorMessage = 'Não foi possível concluir a atualização.';
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
