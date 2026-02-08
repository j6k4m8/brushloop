import type { ServerConfig } from "../config.ts";
import type { StorageAdapter } from "./adapter.ts";
import { LocalStorageAdapter } from "./local-storage.ts";
import { S3StorageAdapter } from "./s3-storage.ts";

/**
 * Build storage adapter from runtime config.
 */
export function createStorageAdapter(config: ServerConfig): StorageAdapter {
  if (config.storageDriver === "local") {
    return new LocalStorageAdapter(config.mediaDirectory);
  }

  return new S3StorageAdapter(config.s3BucketName, config.s3Region);
}
