import 'package:flutter/foundation.dart' show kIsWeb;

/// Runtime app configuration resolved from compile-time environment values.
abstract final class AppConfig {
  static const String _configuredApiBaseUrl = String.fromEnvironment(
    'BRUSHLOOP_API_BASE_URL',
    defaultValue: '',
  );
  static const String _defaultApiBaseUrl = String.fromEnvironment(
    'BRUSHLOOP_DEFAULT_API_BASE_URL',
    defaultValue: 'https://api.brushloop.jordan.matelsky.com',
  );

  static const Set<String> _localWebHosts = {'localhost', '127.0.0.1'};

  /// REST API base URL.
  static String get apiBaseUrl {
    if (_configuredApiBaseUrl.isNotEmpty) {
      return _configuredApiBaseUrl;
    }

    if (kIsWeb) {
      final base = Uri.base;
      final scheme = base.scheme == 'https' ? 'https' : 'http';
      final portSegment = _nonDefaultPortSegment(base, scheme);

      if (_localWebHosts.contains(base.host)) {
        return 'http://127.0.0.1:8787';
      }

      if (base.host.startsWith('api.')) {
        return '$scheme://${base.host}$portSegment';
      }

      return '$scheme://api.${base.host}$portSegment';
    }

    return _defaultApiBaseUrl;
  }

  static String _nonDefaultPortSegment(Uri uri, String scheme) {
    if (!uri.hasPort) {
      return '';
    }
    if (scheme == 'https' && uri.port == 443) {
      return '';
    }
    if (scheme == 'http' && uri.port == 80) {
      return '';
    }
    return ':${uri.port}';
  }

  /// WebSocket collaboration endpoint URL.
  static String get wsUrl {
    final uri = Uri.parse(apiBaseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws').toString();
  }
}
