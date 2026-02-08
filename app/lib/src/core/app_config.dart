/// Runtime app configuration resolved from compile-time environment values.
abstract final class AppConfig {
  /// REST API base URL.
  static const String apiBaseUrl = String.fromEnvironment(
    'BRUSHLOOP_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8787',
  );

  /// WebSocket collaboration endpoint URL.
  static String get wsUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws').toString();
  }
}
