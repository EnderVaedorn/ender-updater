#!/bin/bash

CONFIG_FILE=".vs-config"
ARCHIVE_FILE="vs.tar.gz"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_USERNAME="vintagestory"
DEFAULT_VSPATH="/home/vintagestory/server"
DEFAULT_DATAPATH="/home/vintagestory/data"

TARGET_USERNAME="$DEFAULT_USERNAME"
TARGET_VSPATH="$DEFAULT_VSPATH"
TARGET_DATAPATH="$DEFAULT_DATAPATH"

load_install_dir() {
  if [ ! -f "$CONFIG_FILE" ]; then
    INSTALL_DIR=$(whiptail --inputbox "Enter full path to your Vintage Story server install directory:" 10 70 "$DEFAULT_VSPATH" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ] || [ -z "$INSTALL_DIR" ]; then
      echo "Setup cancelled."
      exit 1
    fi
    echo "$INSTALL_DIR" > "$CONFIG_FILE"
  else
    INSTALL_DIR=$(cat "$CONFIG_FILE")
  fi
}

configure_paths() {
  BACKUP_DIR="$INSTALL_DIR/.vs-backups"
  TEMP_BACKUP="$INSTALL_DIR/.vs-temp/server.sh.temp"
  LOG_DIR="$INSTALL_DIR/.vs-logs"
  SUMMARY_LOG="$LOG_DIR/vs-server-updater.log"
  TODAY=$(date +%F)
  DELETION_LOG="$LOG_DIR/vs-server-deletion-$TODAY.log"
  mkdir -p "$BACKUP_DIR" "$LOG_DIR" "$INSTALL_DIR/.vs-temp"
}

has_existing_install() {
  [ -f "$INSTALL_DIR/server.sh" ] || [ -f "$INSTALL_DIR/VintagestoryServer" ] || [ -d "$INSTALL_DIR/assets" ]
}

prompt_install_history() {
  whiptail --yesno "Has Vintage Story Server ever been installed in this directory?\n\nDirectory:\n$INSTALL_DIR" 12 70
}

prompt_new_install_settings() {
  local username_choice
  local vspath_choice
  local datapath_choice

  vspath_choice=$(whiptail --inputbox "Default server install directory (VSPATH):\n$DEFAULT_VSPATH\n\nPress ENTER to keep this path, or type a full path to override:" 14 80 "$DEFAULT_VSPATH" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "New install cancelled."
    exit 1
  fi

  datapath_choice=$(whiptail --inputbox "Default server data directory (DATAPATH):\n$DEFAULT_DATAPATH\n\nPress ENTER to keep this path, or type a full path to override:" 14 80 "$DEFAULT_DATAPATH" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "New install cancelled."
    exit 1
  fi

  username_choice=$(whiptail --inputbox "Default dedicated username (USERNAME):\n$DEFAULT_USERNAME\n\nPress ENTER to keep this username, or type a different one:" 14 80 "$DEFAULT_USERNAME" 3>&1 1>&2 2>&3)
  if [ $? -ne 0 ]; then
    echo "New install cancelled."
    exit 1
  fi

  TARGET_VSPATH="${vspath_choice:-$DEFAULT_VSPATH}"
  TARGET_DATAPATH="${datapath_choice:-$DEFAULT_DATAPATH}"
  TARGET_USERNAME="${username_choice:-$DEFAULT_USERNAME}"
}

warn_if_missing_dedicated_user() {
  if ! id -u "$TARGET_USERNAME" >/dev/null 2>&1; then
    whiptail --title "Dedicated User Not Found" --yes-button "Continue" --no-button "Quit" \
      --yesno "User '$TARGET_USERNAME' does not exist on this system.\n\nThe extracted server.sh expects this dedicated user for USERNAME.\n\nPlease create this user, or be sure to update server.sh USERNAME manually before running it.\n\nContinue anyway?" 16 78
    if [ $? -ne 0 ]; then
      echo "Missing dedicated user and user chose to quit."
      exit 1
    fi
  fi
}

handle_missing_install() {
  whiptail --yes-button "Install New" --no-button "Quit" \
    --yesno "No Vintage Story Server install detected in given directory.\n\nWould you like to install the server in a new directory, or quit the updater?" 12 75
  if [ $? -ne 0 ]; then
    echo "No install detected and user chose to quit."
    exit 0
  fi

  prompt_new_install_settings

  INSTALL_DIR="$TARGET_VSPATH"
  echo "$INSTALL_DIR" > "$CONFIG_FILE"
  configure_paths
  warn_if_missing_dedicated_user
}

update_server_sh_defaults() {
  local server_script="$INSTALL_DIR/server.sh"

  [ -f "$server_script" ] || return

  sed -i \
    -e "s|^USERNAME=.*|USERNAME='$TARGET_USERNAME'|" \
    -e "s|^VSPATH=.*|VSPATH='$TARGET_VSPATH'|" \
    -e "s|^DATAPATH=.*|DATAPATH='$TARGET_DATAPATH'|" \
    "$server_script"

  echo "[$(date)] Updated server.sh defaults: USERNAME=$TARGET_USERNAME VSPATH=$TARGET_VSPATH DATAPATH=$TARGET_DATAPATH" >> "$SUMMARY_LOG"
}

declare -A DELETE_ACTION_CACHE

choose_delete_action() {
  local target="$1"
  local key
  key="$(dirname "$target")|$(basename "$target")"

  if [[ -n "${DELETE_ACTION_CACHE[$key]}" ]]; then
    echo "${DELETE_ACTION_CACHE[$key]}"
    return
  fi

  whiptail --yesno "Delete $(basename "$target")?\n\nChoose <Yes> to delete permanently.\nChoose <No> to save a backup variant first, then delete it." 12 75
  if [ $? -eq 0 ]; then
    DELETE_ACTION_CACHE[$key]="delete"
  else
    DELETE_ACTION_CACHE[$key]="backup"
  fi

  echo "${DELETE_ACTION_CACHE[$key]}"
}

backup_then_delete() {
  local target="$1"
  local item_name
  local backup_target

  item_name=$(basename "$target")
  backup_target="$BACKUP_DIR/${item_name}.backup-$TIMESTAMP"

  cp -a "$target" "$backup_target"
  if [ $? -eq 0 ]; then
    echo "[$(date)] Backed up $target to $backup_target" >> "$SUMMARY_LOG"
    echo "Backed up before deletion: $target -> $backup_target" >> "$DELETION_LOG"
    rm -rf "$target"
  else
    echo "[$(date)] Backup failed for $target; skipped deletion." >> "$SUMMARY_LOG"
    echo "Backup failed, skipped deletion: $target" >> "$DELETION_LOG"
  fi
}

delete_or_backup_item() {
  local item="$1"
  local action

  [ -e "$item" ] || return

  action=$(choose_delete_action "$item")
  if [ "$action" = "backup" ]; then
    backup_then_delete "$item"
  else
    echo "Deleting permanently: $item" >> "$DELETION_LOG"
    rm -rf "$item"
  fi
}

load_install_dir
configure_paths

URL=$(whiptail --inputbox "Enter the URL to download the Vintage Story server package (.tar.gz):" 10 70 3>&1 1>&2 2>&3)
if [ $? -ne 0 ] || [ -z "$URL" ]; then
  echo "Download cancelled."
  exit 1
fi

EXISTING_INSTALL=false
if has_existing_install; then
  EXISTING_INSTALL=true
else
  prompt_install_history
  if [ $? -eq 0 ]; then
    EXISTING_INSTALL=true
  else
    handle_missing_install
    EXISTING_INSTALL=false
  fi
fi

if [ "$EXISTING_INSTALL" = true ]; then
  if [ -f "$INSTALL_DIR/server.sh" ]; then
    cp "$INSTALL_DIR/server.sh" "$BACKUP_DIR/server.sh.backup"
    cp "$INSTALL_DIR/server.sh" "$TEMP_BACKUP"
    echo "[$(date)] Backed up server.sh to $BACKUP_DIR/server.sh.backup" >> "$SUMMARY_LOG"
  fi

  echo -e "\n=== Deletion Log for $TODAY ===" >> "$DELETION_LOG"
  for item in "$INSTALL_DIR"/*; do
    delete_or_backup_item "$item"
  done

  find "$LOG_DIR" -name "vs-server-deletion-*.log" -type f -mtime +30 -print0 | while IFS= read -r -d '' old_log; do
    delete_or_backup_item "$old_log"
  done
else
  echo "[$(date)] New install path selected: $INSTALL_DIR | DATAPATH: $TARGET_DATAPATH | USERNAME: $TARGET_USERNAME" >> "$SUMMARY_LOG"
fi

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

if [ "$EXISTING_INSTALL" = false ]; then
  update_server_sh_defaults
fi

rm -f "$ARCHIVE_FILE"
if [ -f "$TEMP_BACKUP" ]; then
  cp "$TEMP_BACKUP" "$INSTALL_DIR/server.sh"
  rm "$TEMP_BACKUP"
fi

echo "[$(date)] Update successful. Source: $URL | Install Dir: $INSTALL_DIR" >> "$SUMMARY_LOG"
whiptail --msgbox "Vintage Story server updated successfully!" 8 50
