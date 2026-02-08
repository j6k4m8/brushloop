import type {
  PutMediaObjectInput,
  RetrievedMediaObject,
  StorageAdapter,
  StoredMediaObject
} from "./adapter.ts";

/**
 * Placeholder S3 adapter contract.
 * This keeps storage configurable while local disk remains the active MVP driver.
 */
export class S3StorageAdapter implements StorageAdapter {
  private readonly bucket: string;
  private readonly region: string;

  constructor(bucket: string, region: string) {
    this.bucket = bucket;
    this.region = region;
  }

  async putMediaObject(_input: PutMediaObjectInput): Promise<StoredMediaObject> {
    throw new Error(
      `S3 storage is not wired in this MVP runtime (bucket=${this.bucket}, region=${this.region}).`
    );
  }

  async getMediaObject(_storageKey: string): Promise<RetrievedMediaObject> {
    throw new Error(
      `S3 storage is not wired in this MVP runtime (bucket=${this.bucket}, region=${this.region}).`
    );
  }
}
