# BrushLoop Autonomous Build Instructions

## Mission
Build and maintain a complete, working BrushLoop MVP monorepo in this repository with:
- Flutter client app (`app/`) for iOS, Android, Web, macOS.
- Node.js + TypeScript backend (`server/`) using SQLite and local disk storage.
- Shared contracts/types package (`packages/shared/`) for cross-project consistency.

## Mandatory Workflow
1. Keep `TASKS.md` as the single source of truth for active work.
2. For each task:
   - Change `- [ ]` to `- [~]` immediately when starting.
   - Implement the task fully.
   - Change `- [~]` to `- [T]` when implementation is complete.
   - Run tests and lint relevant to the task scope.
   - Commit with a clear message.
   - Change `- [T]` to `- [x]` only after tests/lint/commit are done.
3. Do not leave task states stale; update `TASKS.md` continuously.
4. Avoid escalation-requiring operations.

## Engineering Standards
- Use clear, maintainable architecture and explicit module boundaries.
- Add docstrings/comments for all non-trivial public interfaces and complex logic.
- Prefer deterministic, testable code and small functions.
- Include automated tests for core domain logic, API behavior, and persistence boundaries.
- Ensure lint/test scripts exist and pass.

## Product Constraints
- No Firebase or managed backend services.
- No serverless deployment model.
- Single-node deployment on one machine.
- SQLite for persistence.
- Artwork/media files on local disk.
- CRDT-based collaboration model (vector/stroke operations, not pixel diffs).

## Deliverable Checklist
- Monorepo workspace setup and documentation.
- Flutter app skeleton with key screens and drawing flow wiring.
- Node + TypeScript server with REST + WebSocket collaboration.
- SQLite schema and repositories.
- Turn-based orchestration with timer advancement.
- Notification pipeline abstraction and local adapter.
- Version snapshots and operation log support.
- Deployment/run instructions.
