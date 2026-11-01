# Changelog

## v1.0.3 (2026-11-01)

- A start shorter than 60 seconds only counts as a crash if there is evidence: a new kernel crash record, an SD card that was not unmounted cleanly, or a power cut. Switching the device off from the menu right after power on no longer triggers a repair.
- After a power cut or an unclean unmount later in a session, files that are missing or empty are now restored as well.
- The boot log and `events.log` name the evidence behind every repair.

## v1.0.2 (2026-11-01)

- Detects starts after the power was cut, for example when a power off did not complete and the device only came back after a long press of the power button. The boot log shows the boot type, an RTC reset, the Wi-Fi setting and the number of sleep cycles in the previous session, and `crashes/<start>/power-cut.txt` holds a short report to attach to an issue.
- New `events.log` with one line per crash or power cut.
- README: what to do when the device does not turn on.

## v1.0.1 (2026-11-01)

- Boot log now records the Crash Guard version and the mount options of the SD card. The stock firmware mounts the card with `sync`; under NextUI it is mounted without it, so the slow writes reported for spruceOS do not apply to NextUI.
- README: note on shutdown and sleep problems and the related NextUI fix, plus update instructions.

## v1.0.0 (2026-11-01)

First public release.

- Crash Guard: boot hook with boot log, snapshots of the last 20 starts, capture of kernel crash records (pstore) with a short summary, and automatic repair of `recent.txt` and `minuisettings.txt` after a crash.
- Backup Settings: saves `msettings.bin`, `minuisettings.txt` and the LED settings, keeps the previous backup as a reserve.
- Restore Settings: restores the backup and reboots right away, so keymon cannot overwrite it.
