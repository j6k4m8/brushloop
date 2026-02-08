#!/usr/bin/env bash
set -euo pipefail

if [[ -f "app/pubspec.yaml" ]] && command -v flutter >/dev/null 2>&1; then
  flutter test app
else
  echo "Skipping Flutter tests (flutter not installed or app/pubspec.yaml missing)."
fi
