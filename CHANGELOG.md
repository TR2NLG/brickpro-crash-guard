# Changelog

## v1.0.0 (2026-11-01)

First public release.

- Crash Guard: boot hook with boot log, snapshots of the last 20 starts, capture of kernel crash records (pstore) with a short summary, and automatic repair of `recent.txt` and `minuisettings.txt` after a crash.
- Backup Settings: saves `msettings.bin`, `minuisettings.txt` and the LED settings, keeps the previous backup as a reserve.
- Restore Settings: restores the backup and reboots right away, so keymon cannot overwrite it.
