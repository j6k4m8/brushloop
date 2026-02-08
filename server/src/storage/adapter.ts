import type { Id } from "../../../packages/shared/src/index.ts";

/**
 * Input payload for storing a media object.
 */
export interface PutMediaObjectInput {
  ownerUserId: Id;
  originalFilename: string;
  mimeType: string;
  bytes: Buffer;
}

/**
 * Metadata returned after storing a media object.
 */
export interface StoredMediaObject {
  storageKey: string;
  originalFilename: string;
  mimeType: string;
  byteSize: number;
}

/**
 * Binary object retrieved from storage.
 */
export interface RetrievedMediaObject {
  bytes: Buffer;
  mimeType: string;
}

/**
 * Storage adapter abstraction to support local disk now and S3 later.
 */
export interface StorageAdapter {
  putMediaObject(input: PutMediaObjectInput): Promise<StoredMediaObject>;
  getMediaObject(storageKey: string): Promise<RetrievedMediaObject>;
}
