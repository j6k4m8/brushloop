import 'package:flutter_test/flutter_test.dart';

import 'package:brushloop_app/src/features/artwork/artwork_exit_guard.dart';

void main() {
  test('exit resolves immediately when nothing is pending', () async {
    var finalized = false;
    var waited = false;
    var prompted = false;

    final allowed = await resolveArtworkExit(
      finalizePendingStroke: () {
        finalized = true;
      },
      hasPendingOperations: () => false,
      pendingCount: () => 0,
      collaborationReady: () => true,
      waitForSync: () async {
        waited = true;
      },
      confirmDiscard: (prompt) async {
        prompted = true;
        return false;
      },
    );

    expect(allowed, isTrue);
    expect(finalized, isTrue);
    expect(waited, isFalse);
    expect(prompted, isFalse);
  });

  test(
    'exit waits for sync before allowing leave when pending work finishes',
    () async {
      var pending = true;
      var waited = false;

      final allowed = await resolveArtworkExit(
        finalizePendingStroke: () {},
        hasPendingOperations: () => pending,
        pendingCount: () => pending ? 1 : 0,
        collaborationReady: () => true,
        waitForSync: () async {
          waited = true;
          pending = false;
        },
        confirmDiscard: (prompt) async => false,
      );

      expect(allowed, isTrue);
      expect(waited, isTrue);
    },
  );

  test('exit prompts before discarding offline local changes', () async {
    ArtworkExitPrompt? seenPrompt;

    final allowed = await resolveArtworkExit(
      finalizePendingStroke: () {},
      hasPendingOperations: () => true,
      pendingCount: () => 2,
      collaborationReady: () => false,
      waitForSync: () async {},
      confirmDiscard: (prompt) async {
        seenPrompt = prompt;
        return true;
      },
    );

    expect(allowed, isTrue);
    expect(seenPrompt, isNotNull);
    expect(seenPrompt!.title, 'Offline Changes Not Saved');
    expect(seenPrompt!.message, contains('2 local changes'));
  });

  test('exit prompts after sync timeout when work is still pending', () async {
    ArtworkExitPrompt? seenPrompt;

    final allowed = await resolveArtworkExit(
      finalizePendingStroke: () {},
      hasPendingOperations: () => true,
      pendingCount: () => 1,
      collaborationReady: () => true,
      waitForSync: () async {
        throw StateError('still syncing');
      },
      confirmDiscard: (prompt) async {
        seenPrompt = prompt;
        return false;
      },
    );

    expect(allowed, isFalse);
    expect(seenPrompt, isNotNull);
    expect(seenPrompt!.title, 'Discard Unsynced Changes?');
    expect(seenPrompt!.message, contains('1 local change'));
  });
}
