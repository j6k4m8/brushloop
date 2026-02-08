import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

/// Storage abstraction for persisting authenticated session state.
abstract class SessionStorage {
  /// Loads a previously persisted session, or null when absent/invalid.
  Future<SessionState?> readSession();

  /// Persists a session snapshot.
  Future<void> writeSession(SessionState session);

  /// Clears any persisted session snapshot.
  Future<void> clearSession();
}

/// SharedPreferences-backed session storage for all Flutter platforms.
class SharedPreferencesSessionStorage implements SessionStorage {
  static const String _sessionKey = 'brushloop.session.v1';

  @override
  Future<SessionState?> readSession() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await preferences.remove(_sessionKey);
        return null;
      }

      return SessionState.fromJson(decoded);
    } catch (_) {
      await preferences.remove(_sessionKey);
      return null;
    }
  }

  @override
  Future<void> writeSession(SessionState session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  @override
  Future<void> clearSession() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
  }
}
