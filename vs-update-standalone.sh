#!/bin/bash
CONFIG_FILE=".vs-config"
if [ ! -f "$CONFIG_FILE" ]; then
  INSTALL_DIR=$(whiptail --inputbox "Enter full path to your Vintage Story server install directory:" 10 60 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ] || [ -z "$INSTALL_DIR" ]; then
    echo "Setup cancelled."
    exit 1
  fi
  echo "$INSTALL_DIR" > "$CONFIG_FILE"
else
  INSTALL_DIR=$(cat "$CONFIG_FILE")
fi
BACKUP_DIR="$INSTALL_DIR/.vs-backups"
TEMP_BACKUP="$INSTALL_DIR/.vs-temp/server.sh.temp"
LOG_DIR="$INSTALL_DIR/.vs-logs"
SUMMARY_LOG="$LOG_DIR/vs-server-updater.log"
TODAY=$(date +%F)
DELETION_LOG="$LOG_DIR/vs-server-deletion-$TODAY.log"
ARCHIVE_FILE="vs.tar.gz"
mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$INSTALL_DIR/.vs-temp"
URL=$(whiptail --inputbox "Enter the URL to download the Vintage Story server package (.tar.gz):" 10 60 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$URL" ]; then
  echo "Download cancelled."
  exit 1
fi
if [ -f "$INSTALL_DIR/server.sh" ]; then
  cp "$INSTALL_DIR/server.sh" "$BACKUP_DIR/server.sh.backup"
  cp "$INSTALL_DIR/server.sh" "$TEMP_BACKUP"
  echo "[$(date)] Backed up server.sh to $BACKUP_DIR/server.sh.backup" >> "$SUMMARY_LOG"
fi
echo -e "\n=== Deletion Log for $TODAY ===" >> "$DELETION_LOG"
for item in "$INSTALL_DIR"/*; do
  echo "Deleting: $item" >> "$DELETION_LOG"
  rm -rf "$item"
done
find "$LOG_DIR" -name "vs-server-deletion-*.log" -type f -mtime +30 -exec rm {} \;
curl -L -o "$ARCHIVE_FILE" "$URL"
if [ $? -ne 0 ]; then
  whiptail --msgbox "Download failed. Check the URL or connection." 8 50
  exit 1
fi
tar -xzf "$ARCHIVE_FILE" -C "$INSTALL_DIR" --overwrite
if [ $? -ne 0 ]; then
  whiptail --msgbox "Extraction failed." 8 50
  exit 1
fi
rm -f "$ARCHIVE_FILE"
if [ -f "$TEMP_BACKUP" ]; then
  cp "$TEMP_BACKUP" "$INSTALL_DIR/server.sh"
  rm "$TEMP_BACKUP"
fi
echo "[$(date)] Update successful. Source: $URL | Install Dir: $INSTALL_DIR" >> "$SUMMARY_LOG"
whiptail --msgbox "Vintage Story server updated successfully!" 8 50
