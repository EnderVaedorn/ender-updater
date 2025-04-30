#!/bin/bash
CONFIG_FILE=".vs-config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "No config found. Run vs-update first."
  exit 1
fi
INSTALL_DIR=$(cat "$CONFIG_FILE")
BACKUP="$INSTALL_DIR/.vs-backups/server.sh.backup"
if [ -f "$BACKUP" ]; then
  cp "$BACKUP" "$INSTALL_DIR/server.sh"
  echo "server.sh restored to $INSTALL_DIR"
else
  echo "Backup not found."
fi
