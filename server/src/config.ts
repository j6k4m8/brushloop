import path from "node:path";

/**
 * Runtime configuration for the BrushLoop backend process.
 */
export interface ServerConfig {
  host: string;
  port: number;
  dataDirectory: string;
  sqlitePath: string;
  sessionTtlHours: number;
  snapshotEveryTurns: number;
}

/**
 * Build process config from environment with safe defaults.
 */
export function loadConfig(cwd: string = process.cwd()): ServerConfig {
  const dataDirectory = process.env.BRUSHLOOP_DATA_DIR ?? path.join(cwd, "data");

  return {
    host: process.env.BRUSHLOOP_HOST ?? "127.0.0.1",
    port: Number(process.env.BRUSHLOOP_PORT ?? 8787),
    dataDirectory,
    sqlitePath: process.env.BRUSHLOOP_SQLITE_PATH ?? path.join(dataDirectory, "brushloop.sqlite"),
    sessionTtlHours: Number(process.env.BRUSHLOOP_SESSION_TTL_HOURS ?? 24 * 30),
    snapshotEveryTurns: Number(process.env.BRUSHLOOP_SNAPSHOT_EVERY_TURNS ?? 5)
  };
}
