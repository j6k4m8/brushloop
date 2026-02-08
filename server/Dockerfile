FROM node:25-bookworm-slim

WORKDIR /app

ENV NODE_ENV=production \
    BRUSHLOOP_HOST=0.0.0.0 \
    BRUSHLOOP_PORT=8787 \
    BRUSHLOOP_DATA_DIR=/data \
    BRUSHLOOP_SQLITE_PATH=/data/brushloop.sqlite \
    BRUSHLOOP_STORAGE_DRIVER=local \
    BRUSHLOOP_MEDIA_DIR=/data/media \
    BRUSHLOOP_NOTIFICATION_LOG_PATH=/data/notifications.log

# Copy only runtime source required by the TypeScript strip-types entrypoint.
COPY server/package.json ./server/package.json
COPY server/src ./server/src
COPY packages/shared/package.json ./packages/shared/package.json
COPY packages/shared/src ./packages/shared/src

EXPOSE 8787
VOLUME ["/data"]

CMD ["node", "--experimental-strip-types", "server/src/index.ts"]
