#!/usr/bin/env bash
set -euo pipefail

if [[ -f "app/pubspec.yaml" ]] && command -v flutter >/dev/null 2>&1; then
  (cd app && flutter analyze)
else
  echo "Skipping Flutter lint (flutter not installed or app/pubspec.yaml missing)."
fi
