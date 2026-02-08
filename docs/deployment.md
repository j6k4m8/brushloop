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

## Verification Checklist

- `npm run format`
- `npm run lint`
- `npm run test`
- Manually register two users, accept contact invite, create artwork, and verify:
  - real-time operation broadcast
  - turn submission and auto-advance
  - snapshot creation and notification logs
