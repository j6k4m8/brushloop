#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p deploy/data deploy/web

echo "[1/2] Building Flutter web bundle in Docker..."
docker compose run --rm web-build

echo "[2/2] Starting API + edge services..."
docker compose up -d --build api edge

echo "Deployment started."
