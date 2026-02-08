import { createAppServer } from "./server.ts";

const app = createAppServer();

await app.start();

let shutdownPromise: Promise<void> | null = null;
let forcedExitTimer: NodeJS.Timeout | null = null;

const shutdown = (signal: NodeJS.Signals) => {
  if (shutdownPromise) {
    return shutdownPromise;
  }

  forcedExitTimer = setTimeout(() => {
    console.error(`Force exiting after timeout during ${signal} shutdown.`);
    process.exit(1);
  }, 5000);
  forcedExitTimer.unref();

  shutdownPromise = (async () => {
    try {
      await app.stop();
    } catch (error) {
      console.error("Failed during graceful shutdown:", error);
    } finally {
      if (forcedExitTimer) {
        clearTimeout(forcedExitTimer);
        forcedExitTimer = null;
      }
      process.exit(0);
    }
  })();

  return shutdownPromise;
};

process.once("SIGINT", () => {
  void shutdown("SIGINT");
});

process.once("SIGTERM", () => {
  void shutdown("SIGTERM");
});
