#!/bin/sh
# Backup Settings: saves msettings.bin, minuisettings.txt and the LED settings
# to .userdata/<platform>/settings-backup/<device>/ and keeps the previous
# backup as <device>.previous.
# https://github.com/TR2NLG/brickpro-crash-guard

cd "$(dirname "$0")"
LOGO="$SDCARD_PATH/.system/res/logo.png"
DEV="${DEVICE:-unknown}"
BACKUP_ROOT="$USERDATA_PATH/settings-backup"
DEST="$BACKUP_ROOT/$DEV"
TMP="$BACKUP_ROOT/.new-$DEV"

case "$DEV" in
	brick)    LED="ledsettings_brick.txt" ;;
	brickpro) LED="ledsettings_brickpro.txt" ;;
	*)        LED="ledsettings.txt" ;;
esac

msg() {
	echo "$1"
	show2.elf --mode=simple --image="$LOGO" --text="$1" --timeout="${2:-2}" 2>/dev/null
}
fail() {
	rm -rf "$TMP"
	msg "Error: $1" 3
	exit 1
}

SRC_MS="$USERDATA_PATH/msettings.bin"
[ -s "$SRC_MS" ] || fail "msettings.bin not found"
rm -rf "$TMP"
mkdir -p "$TMP" || fail "cannot create backup folder"
cp "$SRC_MS" "$TMP/msettings.bin" || fail "copy failed"
[ "$(wc -c < "$SRC_MS")" = "$(wc -c < "$TMP/msettings.bin")" ] || fail "copy incomplete"
[ -f "$SHARED_USERDATA_PATH/minuisettings.txt" ] && cp "$SHARED_USERDATA_PATH/minuisettings.txt" "$TMP/"
[ -f "$SHARED_USERDATA_PATH/$LED" ] && cp "$SHARED_USERDATA_PATH/$LED" "$TMP/"
date '+%Y-%m-%d %H:%M' > "$TMP/date.txt"

rm -rf "$DEST.previous" "$DEST.vorher"
[ -d "$DEST" ] && mv "$DEST" "$DEST.previous"
mv "$TMP" "$DEST" || fail "could not store backup"
sync
msg "Settings saved" 2
