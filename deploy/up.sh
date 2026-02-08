#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

set -a
source deploy/domains.env
: "${GHCR_NAMESPACE:=j6k4m8}"
: "${BRUSHLOOP_IMAGE_TAG:=main}"
: "${API_IMAGE:=ghcr.io/${GHCR_NAMESPACE}/brushloop-api:${BRUSHLOOP_IMAGE_TAG}}"
: "${EDGE_IMAGE:=ghcr.io/${GHCR_NAMESPACE}/brushloop-edge:${BRUSHLOOP_IMAGE_TAG}}"
set +a

mkdir -p deploy/data

echo "[1/2] Pulling images..."
echo "API_IMAGE=${API_IMAGE}"
echo "EDGE_IMAGE=${EDGE_IMAGE}"
docker compose pull api edge

echo "[2/2] Starting API + edge services..."
docker compose up -d api edge

echo "Deployment started."
