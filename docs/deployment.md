# Single-Node Deployment Guide

## Environment

Optional backend environment variables:

- `BRUSHLOOP_HOST` (default: `127.0.0.1`)
- `BRUSHLOOP_PORT` (default: `8787`)
- `BRUSHLOOP_DATA_DIR` (default: `<repo>/data`)
- `BRUSHLOOP_SQLITE_PATH` (default: `<data>/brushloop.sqlite`)
- `BRUSHLOOP_NOTIFICATION_LOG_PATH` (default: `<data>/notifications.log`)
- `BRUSHLOOP_SESSION_TTL_HOURS` (default: `720`)
- `BRUSHLOOP_SNAPSHOT_EVERY_TURNS` (default: `5`)
- `BRUSHLOOP_NOTIFICATION_INTERVAL_MS` (default: `5000`)
- `BRUSHLOOP_TURN_EXPIRY_INTERVAL_MS` (default: `10000`)

## Start Backend

```bash
npm run start -w @brushloop/server
```

## Docker Compose Deployment

This repo includes:

- `server/Dockerfile` for the Node.js API service.
- `docker-compose.yml` with:
  - `api` service (BrushLoop backend).
  - `edge` service (Caddy TLS + routing).
- `deploy/domains.env` as the single source of truth for:
  - `WEB_DOMAIN`
  - `API_DOMAIN`

Persistent state is mounted at `./deploy/data`:

- `brushloop.sqlite`
- media files
- notification log

Bring the stack up:

```bash
docker compose up -d --build
```

Stop the stack:

```bash
docker compose down
```

## Domain Routing

Compose/Caddy routes:

- `WEB_DOMAIN` -> Flutter web build from `app/build/web`
- `API_DOMAIN` -> BrushLoop API (`/ws` included)

DNS requirements:

- Create `A`/`AAAA` records for both hostnames to the VM/public host running Docker.
- Ensure inbound `80` and `443` are open for Caddy certificate issuance and HTTPS traffic.

## Run Flutter Client

```bash
cd app
flutter pub get
flutter run --dart-define=BRUSHLOOP_API_BASE_URL=http://127.0.0.1:8787
```

Platform examples:

- Web: `flutter run -d chrome`
- macOS: `flutter run -d macos`
- iOS/Android: `flutter run -d <device-id>`

## Production Notes

- Keep the `data/` directory on persistent storage.
- Back up both `brushloop.sqlite` and media files referenced by DB paths.
- Place backend behind a reverse proxy if exposing beyond localhost.
- If using HTTPS, proxy `/ws` with websocket upgrade support.
- Build web app using `API_DOMAIN` from `deploy/domains.env`:

```bash
source deploy/domains.env
cd app
flutter build web --release --dart-define=BRUSHLOOP_API_BASE_URL=https://$API_DOMAIN
cd ..
```

## Verification Checklist

- `npm run format`
- `npm run lint`
- `npm run test`
- Manually register two users, accept contact invite, create artwork, and verify:
  - real-time operation broadcast
  - turn submission and auto-advance
  - snapshot creation and notification logs
