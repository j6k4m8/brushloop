/// Tracks locally-created collaboration operations until the server echoes them
/// back as persisted.
class CollaborationOperationTracker {
  /// Creates a tracker for a single websocket client id.
  CollaborationOperationTracker({required this.clientId});

  /// Stable websocket client id used for dedupe and submit guards.
  final String clientId;

  final Map<int, Map<String, dynamic>> _pendingOperations =
      <int, Map<String, dynamic>>{};
  int _lastSequence = 0;
  int? _latestTrackedSequence;

  /// Number of locally-created operations still waiting for server echo.
  int get pendingCount => _pendingOperations.length;

  /// True when at least one local operation is not durably persisted yet.
  bool get hasPendingOperations => _pendingOperations.isNotEmpty;

  /// Highest local sequence seen for this tracker.
  int? get latestTrackedSequence => _latestTrackedSequence;

  /// Returns a strictly monotonic sequence number for this client session.
  int nextSequence({int? nowMicros}) {
    final candidate = nowMicros ?? DateTime.now().microsecondsSinceEpoch;
    if (candidate <= _lastSequence) {
      _lastSequence += 1;
    } else {
      _lastSequence = candidate;
    }
    return _lastSequence;
  }

  /// Queues a locally-created operation until it is acknowledged by the server.
  void queue(Map<String, dynamic> operation) {
    final rawSequence = operation['sequence'];
    if (rawSequence is! int) {
      throw ArgumentError.value(
        rawSequence,
        'operation.sequence',
        'must be an integer',
      );
    }

    _pendingOperations[rawSequence] = Map<String, dynamic>.from(operation);
    final latestTrackedSequence = _latestTrackedSequence;
    if (latestTrackedSequence == null || rawSequence > latestTrackedSequence) {
      _latestTrackedSequence = rawSequence;
    }
  }

  /// Removes a persisted operation from the pending set when the server echoes it.
  bool acknowledgeServerOperation(Map<String, dynamic> operation) {
    final operationClientId = operation['clientId'];
    final rawSequence = operation['sequence'];
    if (operationClientId != clientId || rawSequence is! num) {
      return false;
    }

    return _pendingOperations.remove(rawSequence.toInt()) != null;
  }

  /// Snapshot of operations still waiting to be delivered or acknowledged.
  List<Map<String, dynamic>> pendingOperationsSnapshot() {
    return _pendingOperations.values
        .map((operation) => Map<String, dynamic>.from(operation))
        .toList(growable: false);
  }
}
