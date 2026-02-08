import 'package:flutter/foundation.dart';

/// Runtime app configuration resolved from compile-time environment values.
abstract final class AppConfig {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'BRUSHLOOP_API_BASE_URL',
    defaultValue: '',
  );

  /// REST API base URL.
  static String get apiBaseUrl {
    if (_configuredApiBaseUrl.isNotEmpty) {
      return _configuredApiBaseUrl;
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Android emulator loopback maps host machine to 10.0.2.2.
      return 'http://10.0.2.2:8787';
    }

    return 'http://127.0.0.1:8787';
  }

  /// WebSocket collaboration endpoint URL.
  static String get wsUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws').toString();
  }
}
