#!/usr/bin/env bash
set -euo pipefail

# Run once from any directory. Generates Flutter host folders for the
# five target OSs while restoring the project's hand-written app files.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd -- "$SCRIPT_DIR/../app" && pwd)"
TMP_DIR="$(mktemp -d)"
restore_and_cleanup() {
  if [[ -d "$TMP_DIR" ]]; then
    for file in pubspec.yaml analysis_options.yaml lib/main.dart test/widget_test.dart; do
      if [[ -f "$TMP_DIR/$file" ]]; then
        mkdir -p "$APP_DIR/$(dirname "$file")"
        cp -f "$TMP_DIR/$file" "$APP_DIR/$file"
      fi
    done
    rm -rf "$TMP_DIR"
  fi
}
trap restore_and_cleanup EXIT

for file in pubspec.yaml analysis_options.yaml lib/main.dart test/widget_test.dart; do
  mkdir -p "$TMP_DIR/$(dirname "$file")"
  cp "$APP_DIR/$file" "$TMP_DIR/$file"
done

cd "$APP_DIR"
flutter create --org ir.speedll --project-name speedll_connect_app \
  --platforms=android,ios,windows,macos,linux .

echo "Flutter host folders generated. Hand-written app files restored. Review git diff."
