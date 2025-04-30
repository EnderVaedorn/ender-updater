Vintage Story Server Updater (vs-update)
========================================

This script automates the process of updating a Vintage Story dedicated server.
It downloads a new release tarball, deletes old server files, preserves your
server.sh script, and logs all deletions and update events.

All logs and backups are kept inside hidden folders in your Vintage Story
install directory. This makes the script portable and safe to run from any user
account with write access to that directory.

Maintained by: Ender Vaedorn <ender@endershollow.com>

Usage Instructions for vs-update
================================

1. Place the script `vs-update-standalone.sh` anywhere you'd like.
2. Make it executable:
   chmod +x vs-update-standalone.sh

3. Run the script:
   ./vs-update-standalone.sh

4. On first run, it will prompt for:
   - The path to your Vintage Story install directory (e.g., /home/server)
   - The URL to download the latest VS server release (.tar.gz)

5. The script will:
   - Backup server.sh (to .vs-backups/)
   - Delete old files (excluding .vs-* folders)
   - Extract the new server package
   - Restore server.sh
   - Log all events in .vs-logs/ within your install directory

6. Subsequent runs will reuse your previously entered path unless you delete `.vs-config`.

Requirements:
-------------
- bash
- curl
- tar
- whiptail (sudo apt install whiptail)

Notes:
------
- Run as any user with write access to the install directory.
- Works well with sudo or non-login user environments.

