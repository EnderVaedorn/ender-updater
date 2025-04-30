#!/bin/bash
CONFIG_FILE=".vs-config"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Config file not found. Run vs-update first."
  exit 1
fi
INSTALL_DIR=$(cat "$CONFIG_FILE")
LOG_DIR="$INSTALL_DIR/.vs-logs"
SUMMARY_LOG="$LOG_DIR/vs-server-updater.log"
echo "1) View summary log"
echo "2) View deletion log by date"
read -rp "Choice: " CHOICE
if [ "$CHOICE" = "1" ]; then
  tail -n 30 "$SUMMARY_LOG"
elif [ "$CHOICE" = "2" ]; then
  ls "$LOG_DIR"/vs-server-deletion-*.log 2>/dev/null | sed "s|$LOG_DIR/||"
  read -rp "Enter date (YYYY-MM-DD): " DATE
  less "$LOG_DIR/vs-server-deletion-$DATE.log"
else
  echo "Invalid choice"
fi
