import 'dart:async';

/// Prompt content shown when the user tries to leave with unsynced changes.
class ArtworkExitPrompt {
  /// Creates an exit prompt payload.
  const ArtworkExitPrompt({required this.title, required this.message});

  /// Dialog title.
  final String title;

  /// Dialog body.
  final String message;
}

/// Resolves whether the editor may close while local operations are still pending.
Future<bool> resolveArtworkExit({
  required FutureOr<void> Function() finalizePendingStroke,
  required bool Function() hasPendingOperations,
  required int Function() pendingCount,
  required bool Function() collaborationReady,
  required Future<void> Function() waitForSync,
  required Future<bool> Function(ArtworkExitPrompt prompt) confirmDiscard,
}) async {
  await finalizePendingStroke();
  if (!hasPendingOperations()) {
    return true;
  }

  final wasReady = collaborationReady();
  if (wasReady) {
    try {
      await waitForSync();
    } catch (_) {
      // Falling back to explicit confirmation is safer than allowing a silent loss.
    }

    if (!hasPendingOperations()) {
      return true;
    }
  }

  return confirmDiscard(
    buildArtworkExitPrompt(
      pendingCount: pendingCount(),
      collaborationReady: wasReady,
    ),
  );
}

/// Builds a user-facing confirmation prompt for unsynced local changes.
ArtworkExitPrompt buildArtworkExitPrompt({
  required int pendingCount,
  required bool collaborationReady,
}) {
  final changeLabel = pendingCount == 1 ? 'change' : 'changes';
  if (collaborationReady) {
    return ArtworkExitPrompt(
      title: 'Discard Unsynced Changes?',
      message:
          'BrushLoop is still saving $pendingCount local $changeLabel. Leaving now will discard them on this device.',
    );
  }

  return ArtworkExitPrompt(
    title: 'Offline Changes Not Saved',
    message:
        'BrushLoop is offline and still has $pendingCount local $changeLabel waiting to upload. Leaving now will discard them on this device.',
  );
}
