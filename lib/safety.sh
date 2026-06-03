#!/bin/bash

VS_UPDATER_CONFIG_HOME="${VS_UPDATER_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/vs-updater}"
VSU_LOCK_FD=""
VSU_LOCK_FILE=""

vsu_lock_key_for_path() {
  local path="$1"

  if declare -F vsu_realpath_existing_parent >/dev/null 2>&1; then
    path=$(vsu_realpath_existing_parent "$path")
  else
    path=$(realpath -m -- "$path")
  fi
  path="${path#/}"
  path="${path//\//_}"
  printf '%s' "${path:-root}"
}

vsu_acquire_instance_lock() {
  local install_dir="$1"
  local instance_name="${2:-}"
  local lock_dir="$VS_UPDATER_CONFIG_HOME/locks"
  local lock_key

  command -v flock >/dev/null 2>&1 || {
    printf 'Error: Required command not found: flock\n' >&2
    exit 1
  }

  if [ -n "$instance_name" ]; then
    lock_key="instance-$instance_name"
  else
    lock_key="path-$(vsu_lock_key_for_path "$install_dir")"
  fi

  mkdir -p -- "$lock_dir" || {
    printf 'Error: Could not create lock directory: %s\n' "$lock_dir" >&2
    exit 1
  }

  VSU_LOCK_FILE="$lock_dir/$lock_key.lock"
  exec {VSU_LOCK_FD}>"$VSU_LOCK_FILE" || {
    printf 'Error: Could not open lock file: %s\n' "$VSU_LOCK_FILE" >&2
    exit 1
  }

  flock -n "$VSU_LOCK_FD" || {
    printf 'Error: Another updater operation is already running for this instance.\n' >&2
    exit 1
  }

  printf '%s\n' "$$" 1>&"$VSU_LOCK_FD"
}

vsu_write_trash_readme() {
  local trash_dir="$1"

  [ -n "$trash_dir" ] || return 0
  mkdir -p -- "$trash_dir" || return 1
  [ -f "$trash_dir/README-DO-NOT-DELETE-UNTIL-VERIFIED.txt" ] && return 0

  cat > "$trash_dir/README-DO-NOT-DELETE-UNTIL-VERIFIED.txt" <<EOF
Vintage Story Updater review area

The updater moves old or displaced files here instead of deleting them.
Do not remove these folders until you have started the server and verified
worlds, mods, configuration, and player access after the update.

After testing, review the timestamped folders manually and delete only the
contents you are certain are no longer needed.
EOF
}

vsu_path_is_under_dir() {
  local path="$1"
  local parent="$2"

  [ -n "$path" ] && [ -n "$parent" ] || return 1
  if declare -F vsu_realpath_existing_parent >/dev/null 2>&1; then
    path=$(vsu_realpath_existing_parent "$path")
    parent=$(vsu_realpath_existing_parent "$parent")
  else
    path=$(realpath -m -- "$path")
    parent=$(realpath -m -- "$parent")
  fi
  case "$path/" in
    "$parent/"*) return 0 ;;
    *) return 1 ;;
  esac
}

vsu_service_appears_running() {
  local service_name="$1"

  [ -n "$service_name" ] || return 1
  command -v systemctl >/dev/null 2>&1 || return 1
  systemctl is-active --quiet "$service_name" >/dev/null 2>&1
}

vsu_vintagestory_process_matches_instance() {
  local install_dir="$1"
  local data_path="${2:-}"
  local line
  local pid
  local cwd
  local exe

  command -v pgrep >/dev/null 2>&1 || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pid="${line%% *}"

    case "$line" in
      *"$install_dir"*) return 0 ;;
    esac
    if [ -n "$data_path" ]; then
      case "$line" in
        *"$data_path"*) return 0 ;;
      esac
    fi

    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
    vsu_path_is_under_dir "$cwd" "$install_dir" && return 0

    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
    vsu_path_is_under_dir "$exe" "$install_dir" && return 0
  done < <(pgrep -af VintagestoryServer 2>/dev/null)

  return 1
}

vsu_instance_appears_running() {
  local install_dir="$1"
  local data_path="${2:-}"
  local service_name="${3:-}"

  vsu_service_appears_running "$service_name" && return 0
  vsu_vintagestory_process_matches_instance "$install_dir" "$data_path"
}
