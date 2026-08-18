import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transcript_entry.dart';

class LocalStorageService {
  static const _historyKey = 'voxora.history.v1';
  static const _autoCopyKey = 'voxora.autoCopy';
  static const _languageKey = 'voxora.languageHint';
  static const _floatingOverlayKey = 'openflow.floatingOverlay';
  static const _autoPasteKey = 'openflow.autoPaste';
  static const _apiKeyKey = 'openrouter.apiKey';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  Future<List<TranscriptEntry>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => TranscriptEntry.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((entry) => entry.text.trim().isNotEmpty)
          .take(100)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveHistory(List<TranscriptEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    final limited = entries
        .take(100)
        .map((entry) => entry.toJson())
        .toList(growable: false);
    await prefs.setString(_historyKey, jsonEncode(limited));
  }

  Future<bool> loadAutoCopy() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoCopyKey) ?? true;
  }

  Future<void> saveAutoCopy(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoCopyKey, value);
  }

  Future<String> loadLanguageHint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_languageKey) ?? 'auto';
  }

  Future<void> saveLanguageHint(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, value);
  }

  Future<bool> loadFloatingOverlay() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_floatingOverlayKey) ?? false;
  }

  Future<void> saveFloatingOverlay(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_floatingOverlayKey, value);
  }

  Future<bool> loadAutoPaste() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoPasteKey) ?? false;
  }

  Future<void> saveAutoPaste(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoPasteKey, value);
  }

  Future<String?> readApiKey() async {
    try {
      return await _secureStorage.read(key: _apiKeyKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveApiKey(String apiKey) =>
      _secureStorage.write(key: _apiKeyKey, value: apiKey);

  Future<void> deleteApiKey() => _secureStorage.delete(key: _apiKeyKey);
}
