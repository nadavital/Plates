#!/bin/sh
set -eu

ROOT="${SRCROOT:-$(pwd)}"
APP_SOURCE_ROOT="$ROOT/Trai"
SECRET_SCAN_OUTPUT="${TMPDIR:-/tmp}/trai-secret-scan.txt"

if [ -f "$APP_SOURCE_ROOT/Core/Services/Secrets.swift" ]; then
  echo "error: Remove Trai/Core/Services/Secrets.swift from the app source tree. Use backend proxy configuration instead."
  exit 1
fi

: > "$SECRET_SCAN_OUTPUT"

if /usr/bin/grep -R --include='*.swift' -n 'AIza[0-9A-Za-z_-]\{20,\}' "$APP_SOURCE_ROOT" >"$SECRET_SCAN_OUTPUT" 2>/dev/null; then
  cat "$SECRET_SCAN_OUTPUT"
  echo "error: Possible Google API key literal found under Trai/. Do not ship source-tree secrets."
  exit 1
fi

if /usr/bin/grep -R --include='*.swift' --include='*.plist' -En 'sk-(proj-)?[0-9A-Za-z_-]{20,}' "$APP_SOURCE_ROOT" >"$SECRET_SCAN_OUTPUT" 2>/dev/null; then
  cat "$SECRET_SCAN_OUTPUT"
  echo "error: Possible OpenAI API key literal found under Trai/. Do not ship source-tree secrets."
  exit 1
fi

if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_sensitive_paths="$(git -C "$ROOT" ls-files -- \
    '.agent/gcloud-config' \
    '.agent/gcloud-config/**' \
    '.agent/**/logs/**' \
    '.agent/**/*.log' \
    '.agent/**/access_tokens*.db' \
    '.agent/**/credentials*.db' \
    '.agent/**/legacy_credentials/**' \
    '.agent/**/adc.json' \
    '.agent/**/.boto' \
    '.agent/**/*.pem' \
    '.agent/**/*.p8' \
    '.agent/**/*.key')"

  if [ -n "$tracked_sensitive_paths" ]; then
    echo "$tracked_sensitive_paths"
    echo "error: Sensitive local agent/cloud credential or log paths are tracked by git."
    exit 1
  fi

  unignored_sensitive_paths="$(git -C "$ROOT" ls-files --others --exclude-standard -- \
    '.agent/gcloud-config' \
    '.agent/gcloud-config/**' \
    '.agent/**/logs/**' \
    '.agent/**/*.log' \
    '.agent/**/access_tokens*.db' \
    '.agent/**/credentials*.db' \
    '.agent/**/legacy_credentials/**' \
    '.agent/**/adc.json' \
    '.agent/**/.boto' \
    '.agent/**/*.pem' \
    '.agent/**/*.p8' \
    '.agent/**/*.key')"

  if [ -n "$unignored_sensitive_paths" ]; then
    echo "$unignored_sensitive_paths"
    echo "error: Sensitive local agent/cloud credential or log paths are not covered by .gitignore."
    exit 1
  fi
fi
