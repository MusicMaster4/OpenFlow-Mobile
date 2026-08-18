import 'dart:io';

import 'package:flutter/services.dart';

typedef OverlayActionHandler = Future<void> Function(String action);

class FloatingOverlayService {
  static const _channel = MethodChannel('openflow/overlay');

  OverlayActionHandler? _actionHandler;

  Future<void> initialize(OverlayActionHandler onAction) async {
    _actionHandler = onAction;
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'overlayAction') return;
      final action = (call.arguments as Map?)?['action'] as String?;
      if (action != null) await _actionHandler?.call(action);
    });
  }

  Future<bool> canDrawOverlays() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isOverlayGranted') ?? false;
  }

  Future<void> requestOverlayPermission() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('requestOverlayPermission');
  }

  Future<bool> start() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('startOverlay') ?? false;
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopOverlay');
  }

  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isOverlayRunning') ?? false;
  }

  Future<bool> hasRecordAudioPermission() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasRecordAudioPermission') ??
        false;
  }

  Future<bool> isAccessibilityEnabled() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
  }

  Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openAccessibilitySettings');
  }

  Future<void> openAppDetailsSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openAppDetailsSettings');
  }

  Future<bool> hasNotificationPolicyAccess() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasNotificationPolicyAccess') ??
        false;
  }

  Future<void> openNotificationPolicySettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openNotificationPolicySettings');
  }

  Future<void> setRecordingActive({
    required bool active,
    required bool silence,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('setRecordingActive', {
      'active': active,
      'silence': silence,
    });
  }

  Future<void> playFeedback(String sound) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('playFeedback', {'sound': sound});
  }

  Future<bool> pasteText(String text) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('pasteText', {'text': text}) ??
        false;
  }

  Future<bool> copyText(String text) async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('copyText', {'text': text}) ??
        false;
  }

  Future<void> update({
    required String state,
    required double level,
    required List<double> bands,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('updateOverlay', {
      'state': state,
      'level': level,
      'bands': bands,
    });
  }

  Future<void> showError() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('showOverlayError');
  }
}
