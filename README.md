# BrushLoop Monorepo

BrushLoop is a collaborative drawing MVP with a Flutter client and a Node.js backend.

## Repository Layout

- `app/`: Flutter client (iOS, Android, web, macOS).
- `server/`: Node.js + TypeScript backend using SQLite and local disk storage.
- `packages/shared/`: Shared TypeScript domain contracts and protocol definitions.
- `docs/`: Architecture, deployment, and operational docs.

## Prerequisites

- Node.js 20+ (tested with Node 25.1.0).
- Flutter 3.38+.

## Quick Start

1. Install dependencies where needed:
   - Root: `npm install`
   - Flutter app: `cd app && flutter pub get`
2. Start backend:
   - `npm run start -w @brushloop/server`
3. Run Flutter app:
   - `cd app && flutter run`

For compile-time API base URL override in Flutter:

```bash
flutter run --dart-define=BRUSHLOOP_API_BASE_URL=http://127.0.0.1:8787
```

## Quality Commands

- `npm run format`
- `npm run lint`
- `npm run test`

## Documentation

- `docs/architecture.md`
- `docs/deployment.md`
- `docs/api.md`
