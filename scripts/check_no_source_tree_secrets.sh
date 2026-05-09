#!/bin/sh
set -eu

ROOT="${SRCROOT:-$(pwd)}"
APP_SOURCE_ROOT="$ROOT/Trai"

if [ -f "$APP_SOURCE_ROOT/Core/Services/Secrets.swift" ]; then
  echo "error: Remove Trai/Core/Services/Secrets.swift from the app source tree. Use backend proxy configuration instead."
  exit 1
fi

if /usr/bin/grep -R --include='*.swift' -n 'AIza[0-9A-Za-z_-]\{20,\}' "$APP_SOURCE_ROOT" >/tmp/trai-secret-scan.txt 2>/dev/null; then
  cat /tmp/trai-secret-scan.txt
  echo "error: Possible Google API key literal found under Trai/. Do not ship source-tree secrets."
  exit 1
fi

