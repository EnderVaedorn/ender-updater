# Vintage Story Server Updater

A multi-user-safe, install-directory-scoped shell toolkit to update and manage a Vintage Story dedicated server.

## 📦 Included Scripts

- `vs-update`: Downloads and installs a new Vintage Story server build
- `vs-log-viewer`: View past update or deletion logs
- `vs-config-reset`: Change the configured server install path
- `vs-backup-restore`: Restore the previously backed up `server.sh`

## 🔧 Installation (via .deb)

1. Download the `.deb` file from this release.
2. Install it using:
   ```bash
   sudo dpkg -i vs-updater-1.1-multiuser.deb
   ```

3. Run the updater:
   ```bash
   vs-update
   ```

## 📁 Where Files Go

All config, logs, and backups are stored inside your server's install directory:
```
.your-server-dir/
├── .vs-config
├── .vs-logs/
├── .vs-backups/
├── .vs-temp/
```

## 💡 Requirements

- `bash`
- `curl`
- `tar`
- `whiptail`  
  (Install via `sudo apt install whiptail`)

## 📄 Author

Maintained by **Ender Vaedorn**  
📧 ender@endershollow.com
