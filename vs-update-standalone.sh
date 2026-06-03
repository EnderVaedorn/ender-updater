#!/bin/bash

set -u

SCRIPT_NAME=$(basename "$0")
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEFAULT_USERNAME="vintagestory"
DEFAULT_VSPATH="/home/vintagestory/server"
DEFAULT_DATAPATH="/home/vintagestory/data"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/vs-updater"
CONFIG_FILE="${VS_UPDATER_CONFIG_FILE:-$CONFIG_HOME/install-dir}"
LEGACY_CONFIG_FILE=".vs-config"

INSTALL_DIR=""
URL=""
TARGET_USERNAME="$DEFAULT_USERNAME"
TARGET_VSPATH="$DEFAULT_VSPATH"
TARGET_DATAPATH="$DEFAULT_DATAPATH"
ASSUME_YES=false
ALLOW_RUNNING=false
FORCE_NEW_INSTALL=false
MIGRATE_NESTED_DATA=false
STAGING_DIR=""
SNAPSHOT_DIR=""
NEED_SNAPSHOT=false
PRESERVED_DATA_RELATIVE=""
NESTED_DATA_ACTION="keep"
MIGRATION_DATA_PATH=""
CREATED_MIGRATION_DATA_PATH=false
TRASH_DIR=""
TRASH_PAYLOAD_DIR=""
REVIEW_PATH_RESULT=""
RESOLVED_SERVER_DATA_PATH=""

usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [options]

Interactively install or update a Vintage Story dedicated server.

Options:
  --install-dir PATH   Server installation directory
  --url URL            Vintage Story server package URL (.tar.gz)
  --username NAME      Dedicated server username for a new install
  --data-path PATH     Server data directory for a new install
  --new-install        Treat the selected directory as a new install
  --migrate-nested-data
                       Move an existing nested DATAPATH beside the server directory
  --allow-running      Continue if a running server process is detected
  --yes                Accept confirmation prompts (requires --url)
  -h, --help           Show this help text
EOF
}

cleanup() {
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    rm -rf -- "$STAGING_DIR"
  fi
}

trap cleanup EXIT

show_error() {
  local message="$1"
  printf 'Error: %s\n' "$message" >&2
  if [ -t 1 ] && command -v whiptail >/dev/null 2>&1; then
    whiptail --title "Vintage Story Updater" --msgbox "$message" 10 76
  fi
}

die() {
  show_error "$1"
  exit 1
}

log_summary() {
  printf '[%s] %s\n' "$(date)" "$1" >> "$SUMMARY_LOG"
}

confirm() {
  local message="$1"
  local yes_label="${2:-Continue}"
  local no_label="${3:-Cancel}"

  if [ "$ASSUME_YES" = true ]; then
    return 0
  fi

  whiptail --title "Vintage Story Updater" \
    --yes-button "$yes_label" --no-button "$no_label" \
    --yesno "$message" 16 78
}

prompt_value() {
  local message="$1"
  local default_value="${2:-}"
  local value

  value=$(whiptail --title "Vintage Story Updater" \
    --inputbox "$message" 14 80 "$default_value" 3>&1 1>&2 2>&3) || return 1
  printf '%s' "$value"
}

require_commands() {
  local command
  for command in curl tar realpath mktemp find grep cp rm mkdir mv sed; do
    command -v "$command" >/dev/null 2>&1 || die "Required command not found: $command"
  done

  if [ "$ASSUME_YES" = false ]; then
    command -v whiptail >/dev/null 2>&1 || die "Required command not found: whiptail"
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --install-dir)
        [ "$#" -ge 2 ] || die "--install-dir requires a path."
        INSTALL_DIR="$2"
        shift 2
        ;;
      --url)
        [ "$#" -ge 2 ] || die "--url requires a URL."
        URL="$2"
        shift 2
        ;;
      --username)
        [ "$#" -ge 2 ] || die "--username requires a name."
        TARGET_USERNAME="$2"
        shift 2
        ;;
      --data-path)
        [ "$#" -ge 2 ] || die "--data-path requires a path."
        TARGET_DATAPATH="$2"
        shift 2
        ;;
      --new-install)
        FORCE_NEW_INSTALL=true
        shift
        ;;
      --migrate-nested-data)
        MIGRATE_NESTED_DATA=true
        shift
        ;;
      --allow-running)
        ALLOW_RUNNING=true
        shift
        ;;
      --yes)
        ASSUME_YES=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown option: $1"
        ;;
    esac
  done
}

validate_install_dir() {
  local candidate="$1"
  local normalized
  local user_home

  [ -n "$candidate" ] || die "The install directory cannot be empty."
  [[ "$candidate" = /* ]] || die "The install directory must be an absolute path."

  normalized=$(realpath -m -- "$candidate") || die "Could not normalize install directory: $candidate"
  case "$normalized" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      die "Refusing to use protected directory as the install directory: $normalized"
      ;;
  esac

  if [ "$normalized" = "$HOME" ]; then
    die "Refusing to replace your home directory directly: $normalized. Choose a dedicated child directory, such as /home/vintagestory/server."
  fi

  if command -v getent >/dev/null 2>&1; then
    while IFS=: read -r _ _ _ _ _ user_home _; do
      [ -n "$user_home" ] || continue
      if [ "$normalized" = "$user_home" ]; then
        die "Refusing to replace an account home directory directly: $normalized. Choose a dedicated child directory, such as $normalized/server."
      fi
    done < <(getent passwd)
  fi

  INSTALL_DIR="$normalized"
}

validate_new_install_settings() {
  [[ "$TARGET_USERNAME" =~ ^[a-z_][a-z0-9_-]*\$?$ ]] ||
    die "Dedicated username contains unsupported characters: $TARGET_USERNAME"

  [[ "$TARGET_DATAPATH" = /* ]] || die "The server data directory must be an absolute path."
  [[ "$TARGET_DATAPATH" != *"'"* && "$TARGET_DATAPATH" != *$'\n'* ]] ||
    die "The server data directory cannot contain quotes or newlines."
  [[ "$INSTALL_DIR" != *"'"* && "$INSTALL_DIR" != *$'\n'* ]] ||
    die "The server install directory cannot contain quotes or newlines."

  case "$(realpath -m -- "$TARGET_DATAPATH")/" in
    "$INSTALL_DIR/"*)
      die "The server data directory must be outside the replaceable install directory. Use a sibling path such as $(dirname "$INSTALL_DIR")/data."
      ;;
  esac
}

persist_install_dir() {
  mkdir -p -- "$(dirname "$CONFIG_FILE")" || die "Could not create config directory."
  printf '%s\n' "$INSTALL_DIR" > "$CONFIG_FILE" || die "Could not save config file: $CONFIG_FILE"
}

load_install_dir() {
  local configured_dir

  if [ -n "$INSTALL_DIR" ]; then
    validate_install_dir "$INSTALL_DIR"
    persist_install_dir
    return
  fi

  if [ -f "$CONFIG_FILE" ]; then
    IFS= read -r configured_dir < "$CONFIG_FILE"
  elif [ -f "$LEGACY_CONFIG_FILE" ]; then
    IFS= read -r configured_dir < "$LEGACY_CONFIG_FILE"
    printf 'Migrating legacy config from %s to %s\n' "$LEGACY_CONFIG_FILE" "$CONFIG_FILE"
  elif [ "$ASSUME_YES" = true ]; then
    die "--yes requires --install-dir when no saved configuration exists."
  else
    configured_dir=$(prompt_value "Enter the full path to your Vintage Story server install directory:" "$DEFAULT_VSPATH") ||
      die "Setup cancelled."
  fi

  validate_install_dir "$configured_dir"
  persist_install_dir
}

configure_paths() {
  BACKUP_DIR="$INSTALL_DIR/.vs-backups"
  TRASH_DIR="$INSTALL_DIR/.vs-updater-trash"
  LOG_DIR="$INSTALL_DIR/.vs-logs"
  SUMMARY_LOG="$LOG_DIR/vs-server-updater.log"
  TODAY=$(date +%F)
  DEPLOYMENT_LOG="$LOG_DIR/vs-server-deployment-$TODAY.log"

  mkdir -p -- "$INSTALL_DIR" "$BACKUP_DIR" "$TRASH_DIR" "$LOG_DIR" ||
    die "Could not create updater directories beneath: $INSTALL_DIR"
}

has_existing_install() {
  [ -f "$INSTALL_DIR/server.sh" ] ||
    [ -f "$INSTALL_DIR/VintagestoryServer" ] ||
    [ -d "$INSTALL_DIR/assets" ]
}

directory_has_payload() {
  [ -d "$INSTALL_DIR" ] || return 1
  find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 \
    ! -name '.vs-backups' ! -name '.vs-logs' ! -name '.vs-updater-trash' \
    -print -quit | grep -q .
}

prompt_new_install_settings() {
  local username_choice
  local vspath_choice
  local datapath_choice

  if [ "$ASSUME_YES" = false ]; then
    vspath_choice=$(prompt_value "Server install directory (VSPATH):" "$INSTALL_DIR") ||
      die "New install cancelled."
    datapath_choice=$(prompt_value "Server data directory (DATAPATH):" "$TARGET_DATAPATH") ||
      die "New install cancelled."
    username_choice=$(prompt_value "Dedicated server username (USERNAME):" "$TARGET_USERNAME") ||
      die "New install cancelled."

    INSTALL_DIR="${vspath_choice:-$INSTALL_DIR}"
    TARGET_DATAPATH="${datapath_choice:-$TARGET_DATAPATH}"
    TARGET_USERNAME="${username_choice:-$TARGET_USERNAME}"
  fi

  validate_install_dir "$INSTALL_DIR"
  TARGET_VSPATH="$INSTALL_DIR"
  validate_new_install_settings
  persist_install_dir
  configure_paths
}

warn_if_missing_dedicated_user() {
  if ! id -u "$TARGET_USERNAME" >/dev/null 2>&1; then
    confirm "Dedicated user '$TARGET_USERNAME' does not exist on this system.

The installed server.sh will reference this account. Create the user before starting the server, or edit server.sh manually.

Continue with the installation?" "Continue" "Quit" ||
      die "Installation cancelled because the dedicated user does not exist."
  fi
}

server_appears_running() {
  command -v pgrep >/dev/null 2>&1 || return 1
  pgrep -f "$INSTALL_DIR/VintagestoryServer" >/dev/null 2>&1 ||
    pgrep -x VintagestoryServer >/dev/null 2>&1
}

warn_if_server_running() {
  if server_appears_running && [ "$ALLOW_RUNNING" = false ]; then
    if [ "$ASSUME_YES" = true ]; then
      die "A Vintage Story server process appears to be running. Stop it first or pass --allow-running."
    fi

    confirm "A Vintage Story server process appears to be running.

Updating live server files can produce a broken or inconsistent installation. Stop the server first.

Continue anyway?" "Continue Anyway" "Cancel" ||
      die "Update cancelled while the server is running."
  fi
}

read_server_assignment() {
  local name="$1"
  local line
  local value=""

  [ -f "$INSTALL_DIR/server.sh" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      ''|[[:space:]]'#'*|'#'*)
        continue
        ;;
    esac
    if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?${name}[[:space:]]*=(.*)$ ]]; then
      value="${BASH_REMATCH[2]}"
      break
    fi
  done < "$INSTALL_DIR/server.sh"

  [ -n "$value" ] || return 1
  value=$(printf '%s' "$value" | sed -e 's/[[:space:]]#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$value" in
    \"*\")
      value="${value#\"}"
      value="${value%\"}"
      ;;
    \'*\')
      value="${value#\'}"
      value="${value%\'}"
      ;;
  esac

  [ -n "$value" ] || return 1
  printf '%s' "$value"
}

reject_unsafe_server_path_value() {
  local name="$1"
  local value="$2"

  case "$value" in
    *\$'('*|*'`'*|*\$'['*|*';'*|*'|'*|*'&'*|*$'\n'*)
      die "Could not safely parse $name in server.sh. Use a plain path assignment before updating."
      ;;
  esac
}

resolve_existing_server_data_path() {
  local configured_data_path
  local configured_vspath
  local resolved_vspath="$INSTALL_DIR"
  local resolved_data_path

  if configured_vspath=$(read_server_assignment VSPATH); then
    reject_unsafe_server_path_value VSPATH "$configured_vspath"
    case "$configured_vspath" in
      *'$'*)
        die "Could not safely parse VSPATH in server.sh. Use a plain path assignment before updating."
        ;;
      /*)
        resolved_vspath=$(realpath -m -- "$configured_vspath") ||
          die "Could not normalize the existing server install directory: $configured_vspath"
        ;;
      *)
        resolved_vspath=$(realpath -m -- "$INSTALL_DIR/$configured_vspath") ||
          die "Could not normalize the existing server install directory: $configured_vspath"
        ;;
    esac
  fi

  configured_data_path=$(read_server_assignment DATAPATH) || return 1
  reject_unsafe_server_path_value DATAPATH "$configured_data_path"
  configured_data_path="${configured_data_path//\$\{VSPATH\}/$resolved_vspath}"
  configured_data_path="${configured_data_path//\$VSPATH/$resolved_vspath}"

  case "$configured_data_path" in
    *'$'*)
      die "Could not safely parse DATAPATH in server.sh. Use a plain path assignment or only reference VSPATH."
      ;;
    /*)
      resolved_data_path="$configured_data_path"
      ;;
    *)
      resolved_data_path="$resolved_vspath/$configured_data_path"
      ;;
  esac

  RESOLVED_SERVER_DATA_PATH=$(realpath -m -- "$resolved_data_path") ||
    die "Could not normalize the existing server data directory: $resolved_data_path"
}

detect_nested_existing_data_path() {
  local normalized_data_path

  [ -f "$INSTALL_DIR/server.sh" ] || return
  resolve_existing_server_data_path || return
  normalized_data_path="$RESOLVED_SERVER_DATA_PATH"

  if [ "$normalized_data_path" = "$INSTALL_DIR" ]; then
    die "The existing server.sh uses the entire install directory as DATAPATH. Move persistent data to a dedicated directory before updating."
  fi

  case "$normalized_data_path/" in
    "$INSTALL_DIR/"*)
      PRESERVED_DATA_RELATIVE="${normalized_data_path#"$INSTALL_DIR"/}"
      ;;
  esac
}

guard_unhandled_nested_data_directory() {
  [ -d "$INSTALL_DIR/data" ] || return 0
  [ -n "$PRESERVED_DATA_RELATIVE" ] && return 0

  die "A data directory exists inside the replaceable install directory, but the updater could not prove it is safe to move or restore automatically: $INSTALL_DIR/data. Move persistent data outside the install directory or edit server.sh to use a plain DATAPATH before updating."
}

choose_nested_data_action() {
  [ -n "$PRESERVED_DATA_RELATIVE" ] || return 0
  MIGRATION_DATA_PATH="$(dirname "$INSTALL_DIR")/data"

  if [ "$MIGRATE_NESTED_DATA" = true ]; then
    NESTED_DATA_ACTION="migrate"
  elif [ "$ASSUME_YES" = true ]; then
    printf 'Keeping legacy nested DATAPATH: %s/%s\n' "$INSTALL_DIR" "$PRESERVED_DATA_RELATIVE"
    printf 'Run again with --migrate-nested-data to move it to: %s\n' "$MIGRATION_DATA_PATH"
    return
  elif confirm "This installation stores persistent server data inside the replaceable server directory:

$INSTALL_DIR/$PRESERVED_DATA_RELATIVE

The recommended layout keeps data beside the server files:

$MIGRATION_DATA_PATH

Migrate the persistent data during this update?" "Migrate Data" "Keep Legacy"; then
    NESTED_DATA_ACTION="migrate"
  fi

  if [ "$NESTED_DATA_ACTION" = "migrate" ] && [ -e "$MIGRATION_DATA_PATH" ]; then
    die "Cannot migrate automatically because the suggested data directory already exists: $MIGRATION_DATA_PATH. Review its contents and move the data manually."
  fi
}

get_url() {
  if [ -z "$URL" ]; then
    [ "$ASSUME_YES" = false ] || die "--yes requires --url."
    URL=$(prompt_value "Enter the URL for the Vintage Story server package (.tar.gz):") ||
      die "Download cancelled."
  fi

  case "$URL" in
    https://*|http://*|file://*) ;;
    *) die "URL must use https://, http://, or file://." ;;
  esac
}

archive_is_safe() {
  local entry
  local normalized_entry

  tar -tzf "$STAGING_DIR/server.tar.gz" > "$STAGING_DIR/archive-entries.txt" || return 1
  while IFS= read -r entry; do
    normalized_entry="${entry#./}"
    [ -n "$normalized_entry" ] || continue
    case "/$normalized_entry/" in
      *"/../"*|//*)
        return 1
        ;;
    esac
    case "$normalized_entry" in
      .vs-backups|.vs-backups/*|.vs-logs|.vs-logs/*)
        return 1
        ;;
    esac
    [[ "$normalized_entry" != /* ]] || return 1
  done < "$STAGING_DIR/archive-entries.txt"
}

prepare_staged_package() {
  STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vs-updater.XXXXXX") ||
    die "Could not create a temporary staging directory."
  mkdir -p -- "$STAGING_DIR/extracted" || die "Could not create extraction directory."

  printf 'Downloading server package...\n'
  curl --fail --show-error --location \
    --proto '=https,http,file' --proto-redir '=https,http,file' \
    --output "$STAGING_DIR/server.tar.gz" "$URL" ||
    die "Download failed. The current installation has not been changed."

  archive_is_safe ||
    die "The downloaded archive is invalid or contains unsafe paths. The current installation has not been changed."

  tar -xzf "$STAGING_DIR/server.tar.gz" -C "$STAGING_DIR/extracted" ||
    die "Could not extract the downloaded archive. The current installation has not been changed."

  if [ ! -f "$STAGING_DIR/extracted/server.sh" ] &&
    [ ! -f "$STAGING_DIR/extracted/VintagestoryServer" ] &&
    [ ! -d "$STAGING_DIR/extracted/assets" ]; then
    die "The archive does not look like a Vintage Story server package. The current installation has not been changed."
  fi
}

copy_live_payload() {
  local destination="$1"
  local item

  while IFS= read -r -d '' item; do
    cp -a -- "$item" "$destination/" || return 1
  done < <(
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 \
      ! -name '.vs-backups' ! -name '.vs-logs' ! -name '.vs-updater-trash' \
      -print0
  )
}

write_trash_readme() {
  [ -n "$TRASH_DIR" ] || return 0
  [ -f "$TRASH_DIR/README-DO-NOT-DELETE-UNTIL-VERIFIED.txt" ] && return 0

  cat > "$TRASH_DIR/README-DO-NOT-DELETE-UNTIL-VERIFIED.txt" <<EOF
Vintage Story Updater review area

The updater moves old or displaced files here instead of deleting them.
Do not remove these folders until you have started the server and verified
worlds, mods, configuration, and player access after the update.

After testing, review the timestamped folders manually and delete only the
contents you are certain are no longer needed.
EOF
}

create_review_dir() {
  local prefix="$1"
  local candidate="$TRASH_DIR/$prefix-$TIMESTAMP"
  local counter=1

  write_trash_readme
  while [ -e "$candidate" ]; do
    counter=$((counter + 1))
    candidate="$TRASH_DIR/$prefix-$TIMESTAMP-$counter"
  done
  mkdir -p -- "$candidate" || return 1
  REVIEW_PATH_RESULT="$candidate"
}

move_payload_to_review_dir() {
  local destination="$1"
  local item

  while IFS= read -r -d '' item; do
    mv -- "$item" "$destination/" || return 1
  done < <(
    find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 \
      ! -name '.vs-backups' ! -name '.vs-logs' ! -name '.vs-updater-trash' \
      -print0
  )
}

quarantine_live_payload() {
  directory_has_payload || return 0
  create_review_dir "server-payload" || return 1
  TRASH_PAYLOAD_DIR="$REVIEW_PATH_RESULT"
  move_payload_to_review_dir "$TRASH_PAYLOAD_DIR" || return 1
  log_summary "Moved previous live payload to review trash: $TRASH_PAYLOAD_DIR"
}

quarantine_current_payload_for_review() {
  local prefix="$1"

  directory_has_payload || return 0
  create_review_dir "$prefix" || return 1
  move_payload_to_review_dir "$REVIEW_PATH_RESULT" || return 1
  log_summary "Moved current live payload to review trash: $REVIEW_PATH_RESULT"
}

quarantine_path_for_review() {
  local path="$1"
  local prefix="$2"
  local item_name

  [ -e "$path" ] || return 0
  create_review_dir "$prefix" || return 1
  item_name=$(basename "$path")
  mv -- "$path" "$REVIEW_PATH_RESULT/$item_name" || return 1
  log_summary "Moved displaced path to review trash: $REVIEW_PATH_RESULT/$item_name"
}

restore_payload_from_review_trash() {
  local item

  [ -n "$TRASH_PAYLOAD_DIR" ] && [ -d "$TRASH_PAYLOAD_DIR" ] || return 1
  quarantine_current_payload_for_review "failed-deployment-payload" || return 1
  while IFS= read -r -d '' item; do
    mv -- "$item" "$INSTALL_DIR/" || return 1
  done < <(find "$TRASH_PAYLOAD_DIR" -mindepth 1 -maxdepth 1 -print0)
  log_summary "Restored previous payload from review trash after a failed deployment: $TRASH_PAYLOAD_DIR"
}

create_snapshot() {
  SNAPSHOT_DIR="$BACKUP_DIR/server-backup-$TIMESTAMP"
  mkdir -p -- "$SNAPSHOT_DIR" || die "Could not create rollback snapshot: $SNAPSHOT_DIR"

  copy_live_payload "$SNAPSHOT_DIR" ||
    die "Could not create a complete rollback snapshot. The current installation has not been changed."
  log_summary "Created rollback snapshot: $SNAPSHOT_DIR"
}

rollback_snapshot() {
  [ -n "$SNAPSHOT_DIR" ] && [ -d "$SNAPSHOT_DIR" ] || return 1
  printf 'Deployment failed. Restoring the previous installation...\n' >&2
  cleanup_migrated_data_path
  if ! restore_payload_from_review_trash; then
    quarantine_current_payload_for_review "failed-deployment-payload" || return 1
    cp -a -- "$SNAPSHOT_DIR/." "$INSTALL_DIR/" || return 1
  fi
  log_summary "Restored rollback snapshot after a failed deployment: $SNAPSHOT_DIR"
}

cleanup_migrated_data_path() {
  if [ "$CREATED_MIGRATION_DATA_PATH" = true ] && [ -n "$MIGRATION_DATA_PATH" ]; then
    quarantine_path_for_review "$MIGRATION_DATA_PATH" "rolled-back-migrated-data" || return 1
    CREATED_MIGRATION_DATA_PATH=false
  fi
}

update_server_sh_data_path() {
  local data_path="$1"
  local escaped_datapath

  [ -f "$INSTALL_DIR/server.sh" ] || return 1
  escaped_datapath=$(printf '%s' "$data_path" | sed 's/[\\&|]/\\&/g')
  sed -i -e "s|^DATAPATH=.*|DATAPATH='$escaped_datapath'|" "$INSTALL_DIR/server.sh"
}

restore_nested_existing_data() {
  local snapshot_data_path
  local live_data_path

  [ -n "$PRESERVED_DATA_RELATIVE" ] || return 0
  snapshot_data_path="$SNAPSHOT_DIR/$PRESERVED_DATA_RELATIVE"
  live_data_path="$INSTALL_DIR/$PRESERVED_DATA_RELATIVE"

  if [ "$NESTED_DATA_ACTION" = "migrate" ]; then
    [ ! -e "$MIGRATION_DATA_PATH" ] || return 1
    mkdir -p -- "$MIGRATION_DATA_PATH" || return 1
    CREATED_MIGRATION_DATA_PATH=true
    if [ -e "$snapshot_data_path" ]; then
      cp -a -- "$snapshot_data_path/." "$MIGRATION_DATA_PATH/" || return 1
    fi
    quarantine_path_for_review "$live_data_path" "replaced-nested-data-path" || return 1
    update_server_sh_data_path "$MIGRATION_DATA_PATH" || return 1
    log_summary "Migrated nested persistent data directory: $live_data_path -> $MIGRATION_DATA_PATH"
    return 0
  fi

  [ -e "$snapshot_data_path" ] || return 0

  quarantine_path_for_review "$live_data_path" "replaced-nested-data-path" || return 1
  mkdir -p -- "$live_data_path" || return 1
  cp -a -- "$snapshot_data_path/." "$live_data_path/" || return 1
  log_summary "Restored nested persistent data directory after deployment: $live_data_path"
}

deploy_staged_package() {
  if ! quarantine_live_payload; then
    if [ "$NEED_SNAPSHOT" = true ]; then
      rollback_snapshot ||
        die "Could not move the old payload into review trash cleanly and automatic rollback failed. Restore manually from: $SNAPSHOT_DIR"
    fi
    die "Could not move the old server payload into review trash. The previous installation was restored."
  fi

  if ! cp -a -- "$STAGING_DIR/extracted/." "$INSTALL_DIR/"; then
    if [ "$NEED_SNAPSHOT" = true ]; then
      rollback_snapshot ||
        die "Deployment and automatic rollback both failed. Restore manually from: $SNAPSHOT_DIR"
      die "Deployment failed. The previous installation was restored."
    fi
    quarantine_current_payload_for_review "failed-new-install-payload" ||
      die "Deployment failed and partial files could not be moved to review trash from: $INSTALL_DIR"
    die "Deployment failed. Partial files were moved to review trash."
  fi

  if [ "$EXISTING_INSTALL" = true ] && [ -f "$SNAPSHOT_DIR/server.sh" ]; then
    if ! cp -a -- "$SNAPSHOT_DIR/server.sh" "$INSTALL_DIR/server.sh"; then
      rollback_snapshot ||
        die "Could not restore server.sh and automatic rollback failed. Restore manually from: $SNAPSHOT_DIR"
      die "Could not restore server.sh. The previous installation was restored."
    fi
  fi

  if ! restore_nested_existing_data; then
    rollback_snapshot ||
      die "Could not restore nested persistent data and automatic rollback failed. Restore manually from: $SNAPSHOT_DIR"
    die "Could not restore nested persistent data. The previous installation was restored."
  fi
}

update_server_sh_defaults() {
  local server_script="$INSTALL_DIR/server.sh"
  local escaped_vspath
  local escaped_datapath

  [ -f "$server_script" ] || return
  escaped_vspath=$(printf '%s' "$TARGET_VSPATH" | sed 's/[\\&|]/\\&/g')
  escaped_datapath=$(printf '%s' "$TARGET_DATAPATH" | sed 's/[\\&|]/\\&/g')
  sed -i \
    -e "s|^USERNAME=.*|USERNAME='$TARGET_USERNAME'|" \
    -e "s|^VSPATH=.*|VSPATH='$escaped_vspath'|" \
    -e "s|^DATAPATH=.*|DATAPATH='$escaped_datapath'|" \
    "$server_script" || return 1

  log_summary "Updated server.sh defaults: USERNAME=$TARGET_USERNAME VSPATH=$TARGET_VSPATH DATAPATH=$TARGET_DATAPATH"
}

confirm_deployment() {
  local action="install"
  local snapshot_note=""

  if [ "$EXISTING_INSTALL" = true ]; then
    action="update"
    snapshot_note="

A complete rollback snapshot will be created before files are replaced.
Your existing server.sh will be preserved."
  elif [ "$NEED_SNAPSHOT" = true ]; then
    snapshot_note="

A complete rollback snapshot will be created before files are replaced."
  fi

  confirm "Ready to $action Vintage Story Server.

Install directory:
$INSTALL_DIR

Package:
$URL$snapshot_note

Proceed?" "Proceed" "Cancel" ||
    die "No files were changed. Operation cancelled."
}

main() {
  parse_args "$@"
  require_commands
  load_install_dir
  get_url

  EXISTING_INSTALL=false
  if has_existing_install && [ "$FORCE_NEW_INSTALL" = false ]; then
    EXISTING_INSTALL=true
  elif directory_has_payload && [ "$FORCE_NEW_INSTALL" = false ]; then
    confirm "The selected directory contains files, but no recognized Vintage Story server installation.

Treat it as an existing installation and preserve a rollback snapshot?" "Treat As Existing" "Install New" &&
      EXISTING_INSTALL=true
  fi

  if [ "$EXISTING_INSTALL" = false ]; then
    prompt_new_install_settings
    warn_if_missing_dedicated_user
  else
    configure_paths
    detect_nested_existing_data_path
    guard_unhandled_nested_data_directory
    choose_nested_data_action
    warn_if_server_running
  fi

  if directory_has_payload; then
    NEED_SNAPSHOT=true
  fi

  prepare_staged_package
  confirm_deployment

  if [ "$NEED_SNAPSHOT" = true ]; then
    create_snapshot
  fi

  printf '\n=== Deployment Log for %s ===\n' "$TODAY" >> "$DEPLOYMENT_LOG"
  deploy_staged_package

  if [ "$EXISTING_INSTALL" = false ]; then
    if ! update_server_sh_defaults; then
      if [ "$NEED_SNAPSHOT" = true ]; then
        rollback_snapshot ||
          die "Could not configure server.sh and automatic rollback failed. Restore manually from: $SNAPSHOT_DIR"
        die "Could not configure server.sh. The previous installation was restored."
      fi
      quarantine_current_payload_for_review "failed-new-install-payload" ||
        die "Could not configure server.sh and partial files could not be moved to review trash from: $INSTALL_DIR"
      die "Could not configure server.sh. Partial files were moved to review trash."
    fi
  fi

  log_summary "Deployment successful. Source: $URL | Install Dir: $INSTALL_DIR"
  printf 'Vintage Story server deployment completed successfully.\n'
  if [ "$NEED_SNAPSHOT" = true ]; then
    printf 'Rollback snapshot: %s\n' "$SNAPSHOT_DIR"
  fi
  if [ -n "$TRASH_PAYLOAD_DIR" ]; then
    printf 'Previous payload moved to review trash: %s\n' "$TRASH_PAYLOAD_DIR"
    printf 'Review this folder after testing the updated server, then delete it manually when you are certain it is no longer needed.\n'
  fi

  if [ "$ASSUME_YES" = false ]; then
    whiptail --title "Vintage Story Updater" \
      --msgbox "Vintage Story server deployment completed successfully." 8 62
  fi
}

main "$@"
