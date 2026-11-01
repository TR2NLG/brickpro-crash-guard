# Brick Pro Crash Guard

Damage control for [NextUI](https://github.com/LoveRetro/NextUI) on the TrimUI Brick Pro. It keeps your settings and recents safe when the device crashes, and it records the kernel crash report so the underlying bug can be fixed upstream.

## The problem

The TrimUI Brick Pro can freeze and hard reboot, mostly while Wi-Fi is active. This happens on the stock OS, SpruceOS and NextUI alike, see [trimui/firmware_brickpro#4](https://github.com/trimui/firmware_brickpro/issues/4) and [#1](https://github.com/trimui/firmware_brickpro/issues/1). Kernel logs captured with this tool show a panic in the sunxi I2C driver of the stock kernel:

```
sunxi_i2c_do_xfer()1916 - [i2c3] xfer timeout (dev addr:0x28)
Unable to handle kernel NULL pointer dereference at virtual address 00000014
PC is at sunxi_i2c_handler+0x814/0x924
Kernel panic - not syncing: Fatal exception in interrupt
```

On NextUI, a crash shortly after startup also damages your data, because NextUI rewrites several files on every start without crash safe writes. Details are in [LoveRetro/NextUI#833](https://github.com/LoveRetro/NextUI/issues/833).

| File | Contents | After a crash |
|---|---|---|
| `.userdata/tg5040/msettings.bin` | brightness, volume, color, display calibration | reset to defaults |
| `.userdata/shared/minuisettings.txt` | interface settings, RetroAchievements login | empty or partly reset |
| `.userdata/shared/.minui/recent.txt` | recently played games | empty |

## What it does

Three tools for the NextUI Tools menu:

**Crash Guard** switches a boot hook on or off. Once enabled, it runs at every start, before the NextUI menu appears, and

- keeps a short boot log and snapshots of your settings and logs for the last 20 starts,
- saves every new kernel crash record (pstore) together with a short `summary.txt`,
- detects a crash and repairs `recent.txt` and `minuisettings.txt` from the snapshot taken before NextUI could damage them. No reboot is needed for that,
- detects starts after the power was cut, for example when a power off did not complete and the device only came back after a long press of the power button, and writes a short report.

**Backup Settings** saves your current settings: `msettings.bin`, `minuisettings.txt` and the LED settings.

**Restore Settings** puts that backup back and reboots right away. The reboot is required: keymon keeps `msettings.bin` in memory and would otherwise write the old values back. For the same reason, copying the file back with a file manager while NextUI is running does not work.

## What it does not do

Crash Guard does **not** prevent crashes. It limits the damage and collects data. The most effective workaround for the crashes themselves is to switch Wi-Fi off whenever you do not need it.

## Shutdown and sleep problems

Crashes when switching the device off or waking it from sleep are a separate issue. A fix is in [LoveRetro/NextUI#837](https://github.com/LoveRetro/NextUI/pull/837), which is not part of a regular release yet. A test build with this fix is available in the [NextUI nightly repository](https://github.com/LoveRetro/NextUI-nightly/releases/tag/v6.15.0a). It is meant for testing, lacks the other changes of 6.15.0, and the NextUI team asks not to report bugs based on nightly builds. Once #837 is merged, a regular NextUI update is the better choice. Crash Guard works with both.

## Requirements

- TrimUI Brick Pro running NextUI with boot hook support: 6.15.0 or newer, or the Brick Pro test build v6.15.0a.
- Platform folder `tg5040`. The tools should also work on the TrimUI Brick and Brick Hammer, but this is untested.

## Installation

1. Download `brickpro-crash-guard-vX.Y.Z.zip` from [Releases](../../releases).
2. Extract it to the root of the SD card. Three folders appear in `Tools/tg5040/`.
3. On the device, open **Tools › Crash Guard** once. The message "Crash Guard enabled" confirms it. It is active from the next start.
4. Set everything up the way you like it and run **Tools › Backup Settings**.

To update, extract the new zip the same way and replace the existing files. Crash Guard stays enabled.

## After a crash

- On the next start Crash Guard shows "Crash detected: recents and UI settings repaired".
- If display or sound settings were reset as well, it shows "Display and sound changed: run Tools > Restore Settings". Do that before changing anything else.
- Only run Backup Settings when everything is right again, never right after a crash. The previous backup is kept as a reserve in any case.

## If the device does not turn on

If the Brick Pro does not react to the power button after a shutdown, hold the button for about 20 seconds, then press it again. This forces a hardware reset. In the cases seen so far, the SD card had already been unmounted at that point, so no data was at risk.

Crash Guard recognises the following start and writes `crashes/<start>/power-cut.txt`, a short report with the boot type, the Wi-Fi setting, the number of sleep cycles in the previous session and the end of its log. Please add it to [LoveRetro/NextUI#835](https://github.com/LoveRetro/NextUI/issues/835) together with your NextUI version.

## Files

| Path | Contents |
|---|---|
| `.userdata/tg5040/crash-guard/boots.log` | boot log |
| `.userdata/tg5040/crash-guard/archive/<start>/` | snapshots: logs, settings, dmesg |
| `.userdata/tg5040/crash-guard/events.log` | one line per crash or power cut, the quickest overview |
| `.userdata/tg5040/crash-guard/crashes/<start>/` | kernel crash records with `summary.txt`, or `power-cut.txt` |
| `.userdata/tg5040/settings-backup/<device>/` | backup from Backup Settings, the previous one in `<device>.previous` |
| `.userdata/tg5040/.hooks/boot.d/crash-guard.sync.sh` | small hook created by Crash Guard |

When you report a crash, `summary.txt` and the records in the same folder are what developers need. On the first start, older crash records that are already stored on the device are collected once into the first crashes folder.

## Uninstall

1. Open **Tools › Crash Guard** again. The message "Crash Guard disabled" confirms it.
2. Delete the three folders from `Tools/tg5040/`.
3. Optionally delete `.userdata/tg5040/crash-guard/` and `.userdata/tg5040/settings-backup/`.

## How crash detection works

At every start Crash Guard takes a snapshot of the files before NextUI touches them, and 60 seconds later it marks that start as stable. A crash needs evidence: a new kernel crash record, an SD card that was not unmounted cleanly, or a power cut.

- After an early crash (the previous start never reached the mark, and there is evidence), both files are restored from the snapshot of the crashed start.
- After a crash or a power cut later in a session, only files that are missing or empty are restored, so changes made during a long session are kept.
- A short start without evidence is not a crash. Switching the device off from the menu right after power on, for example to check the logs or to update, does not trigger a repair.
- Restore Settings marks its own reboot as intended, so it is not mistaken for a crash.
- A start counts as a power cut when the kernel reports a cold boot or the clock starts at 1970. Normal starts after a power off are reported as hot reboots with a valid clock. An empty battery leaves the same signature, so check the battery level before reporting.

## Related issues

- [LoveRetro/NextUI#833](https://github.com/LoveRetro/NextUI/issues/833): settings reset after a crash, analysis and suggested code fixes
- [LoveRetro/NextUI#837](https://github.com/LoveRetro/NextUI/pull/837): Brick Pro shutdown and sleep hardening
- [LoveRetro/NextUI#835](https://github.com/LoveRetro/NextUI/issues/835): Brick Pro does not power off cleanly
- [trimui/firmware_brickpro#4](https://github.com/trimui/firmware_brickpro/issues/4) and [#1](https://github.com/trimui/firmware_brickpro/issues/1): Wi-Fi causes hangs and watchdog reboots

## Disclaimer

Provided as is, without warranty. The tools only write inside `.userdata` and their own folders in `Tools/`, and they change nothing in the NextUI system files. Use at your own risk.

## Credits

Thanks to the NextUI team, especially frysee for the Brick Pro work.

## License

[MIT](LICENSE)
