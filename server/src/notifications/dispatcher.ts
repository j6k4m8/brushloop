import type { BrushloopDatabase } from "../db/database.ts";
import type { NotificationAdapter } from "./adapter.ts";

/**
 * Background dispatcher that drains pending notifications from SQLite.
 */
export class NotificationDispatcher {
  private timer: NodeJS.Timeout | null = null;
  private running = false;
  private readonly db: BrushloopDatabase;
  private readonly adapter: NotificationAdapter;
  private readonly intervalMs: number;

  constructor(db: BrushloopDatabase, adapter: NotificationAdapter, intervalMs: number) {
    this.db = db;
    this.adapter = adapter;
    this.intervalMs = intervalMs;
  }

  start(): void {
    if (this.timer) {
      return;
    }

    this.timer = setInterval(() => {
      void this.tick();
    }, this.intervalMs);
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
      const pending = this.db.listPendingNotifications(100);
      for (const notification of pending) {
        await this.adapter.dispatch(notification);
        this.db.markNotificationDelivered(notification.id);
      }
    } catch (error) {
      console.error("notification dispatch failed:", error);
    } finally {
      this.running = false;
    }
  }
}
