#!/bin/bash

VS_UPDATER_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/vs-updater"
VS_UPDATER_CONFIG_FILE="${VS_UPDATER_CONFIG_FILE:-$VS_UPDATER_CONFIG_HOME/install-dir}"
VS_UPDATER_INSTANCE_DIR="${VS_UPDATER_INSTANCE_DIR:-$VS_UPDATER_CONFIG_HOME/instances}"

vsu_die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

vsu_validate_instance_name() {
  local name="$1"

  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] ||
    vsu_die "Instance name contains unsupported characters: $name"
}

vsu_instance_config_path() {
  local name="$1"

  vsu_validate_instance_name "$name"
  printf '%s/%s.conf' "$VS_UPDATER_INSTANCE_DIR" "$name"
}

vsu_read_config_value() {
  local file="$1"
  local key="$2"
  local line

  [ -f "$file" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "$key="*)
        printf '%s' "${line#*=}"
        return 0
        ;;
    esac
  done < "$file"
  return 1
}

vsu_realpath_existing_parent() {
  local path="$1"
  local candidate
  local suffix=""
  local resolved

  if [ -e "$path" ]; then
    realpath -e -- "$path"
    return
  fi

  candidate="$path"
  while [ ! -e "$candidate" ]; do
    suffix="/$(basename "$candidate")$suffix"
    candidate=$(dirname "$candidate")
    if [ "$candidate" = "/" ]; then
      break
    fi
  done

  [ -e "$candidate" ] || vsu_die "No existing parent directory found for: $path"
  resolved=$(realpath -e -- "$candidate") || vsu_die "Could not resolve parent directory: $candidate"
  printf '%s%s' "$resolved" "$suffix"
}

vsu_validate_install_dir() {
  local candidate="$1"
  local normalized
  local user_home

  [ -n "$candidate" ] || vsu_die "The install directory cannot be empty."
  [[ "$candidate" = /* ]] || vsu_die "The install directory must be an absolute path."

  normalized=$(vsu_realpath_existing_parent "$candidate") || vsu_die "Could not normalize install directory: $candidate"
  case "$normalized" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/media|/mnt|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var)
      vsu_die "Refusing to use protected directory as the install directory: $normalized"
      ;;
  esac

  if [ "$normalized" = "$HOME" ]; then
    vsu_die "Refusing to replace your home directory directly: $normalized. Choose a dedicated child directory, such as /home/vintagestory/server."
  fi

  if command -v getent >/dev/null 2>&1; then
    while IFS=: read -r _ _ _ _ _ user_home _; do
      [ -n "$user_home" ] || continue
      if [ "$normalized" = "$user_home" ]; then
        vsu_die "Refusing to replace an account home directory directly: $normalized. Choose a dedicated child directory, such as $normalized/server."
      fi
    done < <(getent passwd)
  fi

  printf '%s' "$normalized"
}

vsu_validate_instance_settings() {
  local install_dir="$1"
  local data_path="$2"
  local username="$3"
  local normalized_install_dir
  local normalized_data_path

  [[ "$username" =~ ^[a-z_][a-z0-9_-]*\$?$ ]] ||
    vsu_die "Dedicated username contains unsupported characters: $username"
  [[ "$data_path" = /* ]] || vsu_die "The server data directory must be an absolute path."
  [[ "$data_path" != *"'"* && "$data_path" != *$'\n'* ]] ||
    vsu_die "The server data directory cannot contain quotes or newlines."
  [[ "$install_dir" != *"'"* && "$install_dir" != *$'\n'* ]] ||
    vsu_die "The server install directory cannot contain quotes or newlines."

  normalized_install_dir=$(vsu_realpath_existing_parent "$install_dir")
  normalized_data_path=$(vsu_realpath_existing_parent "$data_path")

  case "$normalized_data_path/" in
    "$normalized_install_dir/"*)
      vsu_die "The server data directory must be outside the replaceable install directory. Use a sibling path such as $(dirname "$install_dir")/data."
      ;;
  esac
}

vsu_paths_overlap() {
  local first="$1"
  local second="$2"

  [ -n "$first" ] && [ -n "$second" ] || return 1
  first=$(vsu_realpath_existing_parent "$first")
  second=$(vsu_realpath_existing_parent "$second")

  [ "$first" = "$second" ] && return 0
  case "$first/" in "$second/"*) return 0 ;; esac
  case "$second/" in "$first/"*) return 0 ;; esac
  return 1
}

vsu_list_instance_files() {
  find "$VS_UPDATER_INSTANCE_DIR" -mindepth 1 -maxdepth 1 -name '*.conf' -type f -print 2>/dev/null | sort
}

vsu_instance_name_from_file() {
  local file="$1"
  local name

  name=$(basename "$file")
  printf '%s' "${name%.conf}"
}

vsu_guard_instance_collisions() {
  local instance_name="$1"
  local current_file="$2"
  local install_dir="$3"
  local data_path="$4"
  local file
  local name
  local other_install
  local other_data
  local install_path
  local data_path_normalized

  install_path=$(vsu_realpath_existing_parent "$install_dir")
  data_path_normalized=$(vsu_realpath_existing_parent "$data_path")

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    [ "$file" = "$current_file" ] && continue
    name=$(vsu_instance_name_from_file "$file")
    other_install=$(vsu_read_config_value "$file" INSTALL_DIR || true)
    other_data=$(vsu_read_config_value "$file" DATA_PATH || true)

    if vsu_paths_overlap "$install_path" "$other_install"; then
      vsu_die "Instance '$instance_name' install directory overlaps registered instance '$name': $other_install"
    fi
    if vsu_paths_overlap "$data_path_normalized" "$other_data"; then
      vsu_die "Instance '$instance_name' data directory overlaps registered instance '$name': $other_data"
    fi
    if vsu_paths_overlap "$data_path_normalized" "$other_install"; then
      vsu_die "Instance '$instance_name' data directory overlaps '$name' install directory: $other_install"
    fi
    if vsu_paths_overlap "$install_path" "$other_data"; then
      vsu_die "Instance '$instance_name' install directory overlaps '$name' data directory: $other_data"
    fi
  done < <(vsu_list_instance_files)
}

vsu_find_overlapping_instance() {
  local install_dir="$1"
  local current_instance="${2:-}"
  local install_path
  local file
  local name
  local other_install

  install_path=$(vsu_realpath_existing_parent "$install_dir")

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    name=$(vsu_instance_name_from_file "$file")
    [ "$name" = "$current_instance" ] && continue
    other_install=$(vsu_read_config_value "$file" INSTALL_DIR || true)
    if vsu_paths_overlap "$install_path" "$other_install"; then
      printf '%s\t%s\n' "$name" "$other_install"
      return 0
    fi
  done < <(vsu_list_instance_files)

  return 1
}

vsu_write_instance_config() {
  local instance_name="$1"
  local install_dir="$2"
  local data_path="$3"
  local username="$4"
  local service_name="${5:-}"
  local file

  vsu_validate_instance_name "$instance_name"
  install_dir=$(vsu_validate_install_dir "$install_dir")
  vsu_validate_instance_settings "$install_dir" "$data_path" "$username"
  data_path=$(vsu_realpath_existing_parent "$data_path")

  file=$(vsu_instance_config_path "$instance_name")
  vsu_guard_instance_collisions "$instance_name" "$file" "$install_dir" "$data_path"

  mkdir -p -- "$VS_UPDATER_INSTANCE_DIR" || vsu_die "Could not create instance config directory."
  {
    printf 'INSTALL_DIR=%s\n' "$install_dir"
    printf 'DATA_PATH=%s\n' "$data_path"
    printf 'USERNAME=%s\n' "$username"
    if [ -n "$service_name" ]; then
      printf 'SERVICE_NAME=%s\n' "$service_name"
    fi
  } > "$file" || vsu_die "Could not save instance config: $file"
}

vsu_load_instance_config() {
  local instance_name="$1"
  local file

  file=$(vsu_instance_config_path "$instance_name")
  [ -f "$file" ] || vsu_die "Unknown Vintage Story instance: $instance_name"
  vsu_read_config_value "$file" INSTALL_DIR >/dev/null ||
    vsu_die "Instance is missing INSTALL_DIR: $instance_name"
}

vsu_write_legacy_install_dir() {
  local install_dir="$1"

  install_dir=$(vsu_validate_install_dir "$install_dir")
  mkdir -p -- "$(dirname "$VS_UPDATER_CONFIG_FILE")" || vsu_die "Could not create config directory."
  printf '%s\n' "$install_dir" > "$VS_UPDATER_CONFIG_FILE" || vsu_die "Could not save config file: $VS_UPDATER_CONFIG_FILE"
}
