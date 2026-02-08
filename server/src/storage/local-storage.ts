import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

import type {
  PutMediaObjectInput,
  RetrievedMediaObject,
  StorageAdapter,
  StoredMediaObject
} from "./adapter.ts";

/**
 * Local filesystem storage adapter.
 */
export class LocalStorageAdapter implements StorageAdapter {
  private readonly mediaRootDirectory: string;

  constructor(mediaRootDirectory: string) {
    this.mediaRootDirectory = mediaRootDirectory;
  }

  async putMediaObject(input: PutMediaObjectInput): Promise<StoredMediaObject> {
    const extension = inferExtension(input.originalFilename, input.mimeType);
    const today = new Date().toISOString().slice(0, 10);
    const storageKey = `${today}/${randomUUID()}${extension}`;
    const fullPath = this.resolvePath(storageKey);

    await fs.mkdir(path.dirname(fullPath), { recursive: true });
    await fs.writeFile(fullPath, input.bytes);

    return {
      storageKey,
      originalFilename: input.originalFilename,
      mimeType: input.mimeType,
      byteSize: input.bytes.length
    };
  }

  async getMediaObject(storageKey: string): Promise<RetrievedMediaObject> {
    const fullPath = this.resolvePath(storageKey);
    const bytes = await fs.readFile(fullPath);
    return {
      bytes,
      mimeType: inferMimeType(fullPath)
    };
  }

  private resolvePath(storageKey: string): string {
    const normalized = path.posix.normalize(storageKey).replace(/^\/+/, "");
    const fullPath = path.resolve(this.mediaRootDirectory, normalized);
    const rootPath = path.resolve(this.mediaRootDirectory);

    if (!fullPath.startsWith(rootPath)) {
      throw new Error("invalid storage key path");
    }

    return fullPath;
  }
}

function inferExtension(originalFilename: string, mimeType: string): string {
  const ext = path.extname(originalFilename).toLowerCase();
  if ([".jpg", ".jpeg", ".png", ".webp", ".gif", ".heic"].includes(ext)) {
    return ext;
  }

  switch (mimeType.toLowerCase()) {
    case "image/png":
      return ".png";
    case "image/webp":
      return ".webp";
    case "image/gif":
      return ".gif";
    case "image/heic":
      return ".heic";
    default:
      return ".jpg";
  }
}

function inferMimeType(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case ".png":
      return "image/png";
    case ".webp":
      return "image/webp";
    case ".gif":
      return "image/gif";
    case ".heic":
      return "image/heic";
    default:
      return "image/jpeg";
  }
}
