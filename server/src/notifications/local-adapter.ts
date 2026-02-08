import fs from "node:fs/promises";
import path from "node:path";

import type { NotificationRecord } from "../../../packages/shared/src/index.ts";
import type { NotificationAdapter } from "./adapter.ts";

/**
 * Local notification sink that appends deliveries to a JSONL file.
 */
export class LocalNotificationAdapter implements NotificationAdapter {
  private readonly logFilePath: string;

  constructor(logFilePath: string) {
    this.logFilePath = logFilePath;
  }

  async dispatch(notification: NotificationRecord): Promise<void> {
    const dirPath = path.dirname(this.logFilePath);
    await fs.mkdir(dirPath, { recursive: true });

    const entry = {
      deliveredAt: new Date().toISOString(),
      notification
    };

    await fs.appendFile(this.logFilePath, `${JSON.stringify(entry)}\n`, "utf8");
  }
}
