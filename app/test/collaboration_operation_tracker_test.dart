import 'package:flutter_test/flutter_test.dart';

import 'package:brushloop_app/src/features/artwork/collaboration_operation_tracker.dart';

void main() {
  test('tracker keeps strictly increasing sequences', () {
    final tracker = CollaborationOperationTracker(clientId: 'client-1');

    final first = tracker.nextSequence(nowMicros: 100);
    final second = tracker.nextSequence(nowMicros: 100);
    final third = tracker.nextSequence(nowMicros: 99);

    expect(<int>[first, second, third], <int>[100, 101, 102]);
  });

  test('tracker acknowledges only matching client operations', () {
    final tracker = CollaborationOperationTracker(clientId: 'client-1');

    tracker.queue(<String, dynamic>{
      'sequence': 42,
      'clientId': 'client-1',
      'type': 'stroke.add',
    });

    expect(tracker.hasPendingOperations, isTrue);
    expect(
      tracker.acknowledgeServerOperation(<String, dynamic>{
        'sequence': 42,
        'clientId': 'other-client',
      }),
      isFalse,
    );
    expect(tracker.hasPendingOperations, isTrue);

    expect(
      tracker.acknowledgeServerOperation(<String, dynamic>{
        'sequence': 42,
        'clientId': 'client-1',
      }),
      isTrue,
    );
    expect(tracker.hasPendingOperations, isFalse);
  });
}
