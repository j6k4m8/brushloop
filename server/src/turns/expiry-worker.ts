import type { Id, TurnState } from "../../../packages/shared/src/index.ts";
import type { BrushloopDatabase } from "../db/database.ts";

interface TurnExpiryWorkerOptions {
  db: BrushloopDatabase;
  intervalMs: number;
  snapshotEveryTurns: number;
  onTurnAdvanced: (turn: TurnState) => void;
}

/**
 * Background worker that auto-advances expired turn-based artworks.
 */
export class TurnExpiryWorker {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private readonly options: TurnExpiryWorkerOptions;

  constructor(options: TurnExpiryWorkerOptions) {
    this.options = options;
  }

  start(): void {
    if (this.timer) {
      return;
    }

    this.timer = setInterval(() => {
      void this.tick();
    }, this.options.intervalMs);
    this.timer.unref();
  }

  stop(): void {
    if (!this.timer) {
      return;
    }

    clearInterval(this.timer);
    this.timer = null;
  }

  private async tick(): Promise<void> {
    if (this.running) {
      return;
    }

    this.running = true;
    try {
      const dueTurns = this.options.db.listDueTurns(new Date().toISOString());
      for (const dueTurn of dueTurns) {
        this.advanceExpiredTurn(dueTurn.artworkId, dueTurn.activeParticipantUserId);
      }
    } catch (error) {
      console.error("turn expiry tick failed:", error);
    } finally {
      this.running = false;
    }
  }

  private advanceExpiredTurn(artworkId: Id, expiredUserId: Id): void {
    try {
      const nextTurn = this.options.db.submitTurn(artworkId, expiredUserId, "expired");

      this.options.db.createSnapshot(artworkId, "turn_submitted", JSON.stringify({}));
      if (this.options.snapshotEveryTurns > 0 && nextTurn.turnNumber % this.options.snapshotEveryTurns === 0) {
        this.options.db.createSnapshot(artworkId, "periodic", JSON.stringify({}));
      }

      this.options.db.createNotification({
        userId: expiredUserId,
        artworkId,
        type: "turn_expired",
        payloadJson: JSON.stringify({ artworkId }),
        channel: "in_app"
      });

      this.options.db.createNotification({
        userId: nextTurn.activeParticipantUserId,
        artworkId,
        type: "turn_started",
        payloadJson: JSON.stringify({ artworkId, turnNumber: nextTurn.turnNumber }),
        channel: "native_push"
      });

      this.options.onTurnAdvanced(nextTurn);
    } catch (error) {
      console.error(`failed to auto-advance turn for artwork ${artworkId}:`, error);
    }
  }
}
