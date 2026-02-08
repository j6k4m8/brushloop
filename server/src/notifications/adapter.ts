import type { NotificationRecord } from "../../../packages/shared/src/index.ts";

/**
 * Notification adapter contract.
 * MVP uses a local sink that can be swapped for platform-specific push bridges.
 */
export interface NotificationAdapter {
  dispatch(notification: NotificationRecord): Promise<void>;
}
