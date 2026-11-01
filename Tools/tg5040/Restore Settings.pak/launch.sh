#!/bin/sh
# Restore Settings: puts the backup from .userdata/<platform>/settings-backup/<device>/
# back in place and reboots right away. The reboot is required because keymon
# keeps the settings in memory and would otherwise write the old values back.
# https://github.com/TR2NLG/brickpro-crash-guard

cd "$(dirname "$0")"
LOGO="$SDCARD_PATH/.system/res/logo.png"
DEV="${DEVICE:-unknown}"
SRC="$USERDATA_PATH/settings-backup/$DEV"

case "$DEV" in
	brick)    LED="ledsettings_brick.txt" ;;
	brickpro) LED="ledsettings_brickpro.txt" ;;
	*)        LED="ledsettings.txt" ;;
esac

msg() {
	echo "$1"
	show2.elf --mode=simple --image="$LOGO" --text="$1" --timeout="${2:-2}" 2>/dev/null
}

if [ ! -s "$SRC/msettings.bin" ]; then
	msg "No backup found" 3
	exit 1
fi

WHEN=$(cat "$SRC/date.txt" 2>/dev/null || cat "$SRC/datum.txt" 2>/dev/null)
msg "Restoring backup ${WHEN:+from $WHEN}, rebooting" 3

restore() {
	[ -f "$1" ] || return 0
	cp "$1" "$2.tmp" && mv "$2.tmp" "$2"
}
if ! restore "$SRC/msettings.bin" "$USERDATA_PATH/msettings.bin"; then
	msg "Error while restoring" 3
	exit 1
fi
restore "$SRC/minuisettings.txt" "$SHARED_USERDATA_PATH/minuisettings.txt"
restore "$SRC/$LED" "$SHARED_USERDATA_PATH/$LED"

# mark this boot as intentionally ended, so Crash Guard does not treat the reboot as a crash
for d in "$USERDATA_PATH/crash-guard" "$USERDATA_PATH/diag"; do
	[ -f "$d/bootcount" ] && cp "$d/bootcount" "$d/stable"
done
sync

if [ -x "$SYSTEM_PATH/bin/reboot_next" ]; then
	"$SYSTEM_PATH/bin/reboot_next"
else
	reboot
fi
