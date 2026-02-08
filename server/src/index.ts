import { createAppServer } from "./server.ts";

const app = createAppServer();

await app.start();

const shutdown = async () => {
  try {
    await app.stop();
  } finally {
    process.exit(0);
  }
};

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
