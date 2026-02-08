import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket wrapper for real-time collaboration messages.
class CollaborationSocket {
  /// Creates a collaboration socket client.
  CollaborationSocket({required this.url});

  /// Full websocket URL.
  final String url;

  WebSocketChannel? _channel;

  /// Broadcast message stream from the collaboration server.
  Stream<Map<String, dynamic>> get messages async* {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    await for (final dynamic message in channel.stream) {
      if (message is String) {
        final decoded = jsonDecode(message);
        if (decoded is Map<String, dynamic>) {
          yield decoded;
        }
      }
    }
  }

  /// Opens the socket and sends an authentication hello message.
  void connect({required String token}) {
    if (_channel != null) {
      return;
    }

    _channel = WebSocketChannel.connect(Uri.parse(url));
    send(<String, dynamic>{
      'type': 'client.hello',
      'token': token,
      'clientId': _newClientId(),
    });
  }

  /// Closes the underlying websocket channel.
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }

  /// Joins an artwork room.
  void joinArtwork(String artworkId) {
    send(<String, dynamic>{
      'type': 'client.join_artwork',
      'artworkId': artworkId,
      'sinceLamportTs': 0,
    });
  }

  /// Leaves an artwork room.
  void leaveArtwork(String artworkId) {
    send(<String, dynamic>{
      'type': 'client.leave_artwork',
      'artworkId': artworkId,
    });
  }

  /// Sends an arbitrary collaboration message.
  void send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    channel.sink.add(jsonEncode(payload));
  }

  String _newClientId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(1 << 31);
    return 'flutter-$now-$random';
  }
}
