#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR="$ROOT_DIR/build/deb/vs-updater"
OUTPUT_DIR="$ROOT_DIR/dist"
VERSION="${VERSION:-}"

if [ -z "$VERSION" ]; then
  VERSION=$(sed -n 's/^Version: //p' "$ROOT_DIR/packaging/debian/control")
fi

rm -rf -- "$BUILD_DIR"
mkdir -p \
  "$BUILD_DIR/DEBIAN" \
  "$BUILD_DIR/usr/bin" \
  "$BUILD_DIR/usr/lib/vs-updater/lib" \
  "$BUILD_DIR/usr/share/doc/vs-updater" \
  "$OUTPUT_DIR"

install -m 0755 "$ROOT_DIR/bin/vs-update" "$BUILD_DIR/usr/bin/vs-update"
install -m 0755 "$ROOT_DIR/bin/vs-backup-restore" "$BUILD_DIR/usr/bin/vs-backup-restore"
install -m 0755 "$ROOT_DIR/bin/vs-config-reset" "$BUILD_DIR/usr/bin/vs-config-reset"
install -m 0755 "$ROOT_DIR/bin/vs-log-viewer" "$BUILD_DIR/usr/bin/vs-log-viewer"
install -m 0644 "$ROOT_DIR/lib/instance-config.sh" "$BUILD_DIR/usr/lib/vs-updater/lib/instance-config.sh"
install -m 0644 "$ROOT_DIR/lib/safety.sh" "$BUILD_DIR/usr/lib/vs-updater/lib/safety.sh"
install -m 0644 "$ROOT_DIR/README.md" "$BUILD_DIR/usr/share/doc/vs-updater/README.md"

sed "s/^Version: .*/Version: $VERSION/" "$ROOT_DIR/packaging/debian/control" > "$BUILD_DIR/DEBIAN/control"

dpkg-deb --root-owner-group --build "$BUILD_DIR" "$OUTPUT_DIR/vs-updater_${VERSION}_all.deb"
printf 'Built %s\n' "$OUTPUT_DIR/vs-updater_${VERSION}_all.deb"
