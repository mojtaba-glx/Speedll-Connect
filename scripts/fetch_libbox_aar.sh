#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="1.14.4"
AAR_NAME="libbox.aar"
DEST_DIR="$ROOT_DIR/app/android/app/libs"
DEST="$DEST_DIR/$AAR_NAME"
URL="https://github.com/singbox-android/libbox/releases/download/$VERSION/$AAR_NAME"
SHA256="d2685924a657705beda44e94c6dc499e781df1ad20d65474e3591ec2f8b96465"

mkdir -p "$DEST_DIR"

if [[ -f "$DEST" ]] && echo "$SHA256  $DEST" | sha256sum -c - >/dev/null 2>&1; then
    echo "libbox $VERSION already present: $DEST"
    exit 0
fi

TMP="$DEST.download"
rm -f "$TMP"
echo "Downloading libbox $VERSION..."
curl -L --fail --retry 3 -C - -o "$TMP" "$URL"
echo "$SHA256  $TMP" | sha256sum -c -
mv "$TMP" "$DEST"
echo "libbox $VERSION ready: $DEST"
