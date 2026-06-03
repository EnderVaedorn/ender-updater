# Vintage Story Server Updater

A careful, interactive installer and updater for a Vintage Story dedicated
server.

## What It Does

The updater downloads and validates a server archive in a temporary staging
directory before changing the live server files. For an existing installation,
it creates a complete rollback snapshot, moves the previous live payload into a
review folder, and preserves the existing `server.sh` configuration while
deploying the new package.

Updater metadata is kept inside the server installation:

```text
.vs-backups/         rollback snapshots
.vs-updater-trash/   previous payloads awaiting manual review
.vs-logs/            deployment and summary logs
```

The selected install directory is remembered per user in:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/vs-updater/install-dir
```

An older `.vs-config` file in the current directory is migrated automatically
when it is found.

## Requirements

- `bash`
- `curl`
- `tar`
- GNU `realpath`
- `whiptail` for interactive use

## Interactive Use

Run:

```bash
./vs-update-standalone.sh
```

The updater asks for the installation directory, package URL, and any settings
needed for a new installation. Before replacing live files, it shows a final
confirmation. If a Vintage Story server process appears to be running, the
updater warns before proceeding.

The recommended Linux layout from the Vintage Story dedicated-server guide is
supported:

```text
/home/vintagestory/
├── server/   replaceable server application files
└── data/     persistent worlds, configuration, and mods
```

The updater deliberately refuses to target `/home/vintagestory` itself because
an update replaces the selected installation directory's payload. It also
rejects a new-install data path beneath the replaceable `server/` directory.
Existing installations with a nested `DATAPATH` in `server.sh` remain
supported. In interactive mode, the updater offers to migrate that persistent
directory to the recommended sibling `data/` path during the update. Choosing
to keep the legacy layout restores the nested directory into the live install
after the new package is deployed.

The updater parses common `server.sh` assignment forms such as
`DATAPATH="/path"`, `export DATAPATH="/path"`, `DATAPATH="$VSPATH/data"`, and
relative data paths. It deliberately refuses complex shell expressions. If a
`data/` directory exists inside the server install and the updater cannot prove
how to preserve it safely, the update stops before moving files.

## Command-Line Use

For a non-interactive update:

```bash
./vs-update-standalone.sh \
  --yes \
  --install-dir /home/vintagestory/server \
  --url https://example.invalid/vintagestory-server.tar.gz
```

An unattended update preserves an existing nested `DATAPATH` by default. To
explicitly migrate it to the recommended sibling `data/` directory:

```bash
./vs-update-standalone.sh \
  --yes \
  --migrate-nested-data \
  --install-dir /home/vintagestory/server \
  --url https://example.invalid/vintagestory-server.tar.gz
```

Automatic migration refuses to merge into an existing sibling `data/`
directory. Review and move those files manually if that destination is already
present.

For a non-interactive fresh installation:

```bash
./vs-update-standalone.sh \
  --yes \
  --new-install \
  --install-dir /home/vintagestory/server \
  --data-path /home/vintagestory/data \
  --username vintagestory \
  --url https://example.invalid/vintagestory-server.tar.gz
```

Use `--help` to list all options.

## Rollback Snapshots

Snapshots are stored as timestamped directories:

```text
.vs-backups/server-backup-YYYYMMDD-HHMMSS/
```

The updater restores the latest snapshot automatically if copying a staged
package into the live directory fails. Snapshots are retained until an
administrator removes them.

## Updater Trash

During an update, the previous live payload is moved to:

```text
.vs-updater-trash/server-payload-YYYYMMDD-HHMMSS/
```

The updater does not delete this folder after a successful deployment. Start
the updated server and verify worlds, mods, configuration, and player access
before deleting anything from `.vs-updater-trash/`. A warning README is written
inside that folder as a reminder.

## Operational Notes

- Stop the dedicated server before updating it.
- Review old rollback snapshots and updater trash folders occasionally so they
  do not consume unnecessary disk space.
- Avoid running the updater as `root` unless the server installation genuinely
  requires it.

## Author

Maintained by **Ender Vaedorn**  
<ender@endershollow.com>
