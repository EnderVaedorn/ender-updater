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

## Installable Package

The root-level standalone script is kept as a one-off option for small
installations. The installable package uses its own updater entry point so it
can grow into multi-instance management without depending on the standalone
variant:

```text
vs-update           run the updater
vs-config-reset    set or clear the saved install directory
vs-log-viewer      view updater logs and review locations
vs-backup-restore  list or restore rollback snapshots
```

Build the Debian package locally with:

```bash
./scripts/build-deb.sh
```

The generated package is written to `dist/`:

```text
dist/vs-updater_VERSION_all.deb
```

The package installs the updater and helper commands to `/usr/bin/`. Release
binaries should be generated from these sources and attached to GitHub Releases
rather than committed to the main tree.

### Named Instances

The installed `vs-update` command can register multiple Vintage Story server
instances and update one selected instance per run:

```bash
vs-update --add-instance survival \
  --install-dir /home/vintagestory/survival/server \
  --data-path /home/vintagestory/survival/data \
  --username vintagestory \
  --service-name vintagestory-survival.service

vs-update --add-instance creative \
  --install-dir /home/vintagestory/creative/server \
  --data-path /home/vintagestory/creative/data \
  --username vintagestory \
  --service-name vintagestory-creative.service
```

Registered instances are stored in:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/vs-updater/instances/
```

List and inspect them with:

```bash
vs-update --list
vs-update --show-instance survival
```

Update an individual instance with:

```bash
vs-update --instance survival --url https://example.invalid/vintagestory-server.tar.gz
```

When multiple instances are registered and no `--instance` or `--install-dir`
is provided, interactive mode asks which instance to update. Non-interactive
updates should pass `--instance NAME` or `--install-dir PATH` explicitly.

The updater refuses registered instances whose server or data paths overlap.
Running-server detection is scoped to the selected instance by checking the
configured systemd service, process command lines, and process paths beneath
the selected install directory.

For multi-instance servers, always register a `--service-name` for each
instance. Without a service name, the updater must infer whether a server is
running from process details, which is inherently less reliable across wrapper
scripts, custom launchers, renamed binaries, and service managers. Failing to
set `SERVICE_NAME` for multi-instance installations can and likely eventually
will cause data loss or corruption if an instance is updated or restored while
it is still running.

The installed commands share one validation layer for instance config and
safety checks. `vs-config-reset --instance` and `vs-update --add-instance`
therefore apply the same path-overlap and data-path rules, while restore and
update commands use the same selected-instance running checks.

Update and restore operations take a per-instance lock before changing live
files, preventing two updater commands from modifying the same server at once.
Rollback restores copy the selected snapshot into a temporary staging directory
before moving the live payload aside.

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
