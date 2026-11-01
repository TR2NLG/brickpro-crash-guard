#!/bin/sh
# Crash Guard for NextUI on the TrimUI Brick Pro
# https://github.com/TR2NLG/brickpro-crash-guard
#
# Called at every boot by .userdata/<platform>/.hooks/boot.d/crash-guard.sync.sh,
# before the NextUI menu starts. It
#   1. keeps a short boot log and per boot snapshots of logs and settings,
#   2. saves new kernel crash records (pstore) to crash-guard/crashes/,
#   3. after a crash, puts recent.txt and minuisettings.txt back from the
#      snapshot taken before NextUI could damage them.
# msettings.bin cannot be repaired here, because keymon has already loaded it.
# For that, use Tools > Restore Settings.

CG_VERSION="1.0.1"
CG="$USERDATA_PATH/crash-guard"
SHARED="$SHARED_USERDATA_PATH"
RECENT="$SHARED/.minui/recent.txt"
MINUI="$SHARED/minuisettings.txt"
MSET="$USERDATA_PATH/msettings.bin"
LOGO="$SDCARD_PATH/.system/res/logo.png"
PSTORE="${CRASH_GUARD_PSTORE:-/sys/fs/pstore}"
STABLE_AFTER="${CRASH_GUARD_STABLE_AFTER:-60}"
KEEP=20

case "$DEVICE" in
	brick)    LED="ledsettings_brick.txt" ;;
	brickpro) LED="ledsettings_brickpro.txt" ;;
	*)        LED="ledsettings.txt" ;;
esac

mkdir -p "$CG/archive" "$CG/crashes"

# boot counter (the clock is not always reliable after a hard reset)
N=$(cat "$CG/bootcount" 2>/dev/null)
case "$N" in ''|*[!0-9]*) N=0 ;; esac
N=$((N + 1))
echo "$N" > "$CG/bootcount"
STAMP=$(printf "%04d" "$N")
ARCH="$CG/archive/$STAMP"
mkdir -p "$ARCH"
PREV=$((N - 1))
PREV_ARCH="$CG/archive/$(printf "%04d" "$PREV")"

msg() {
	show2.elf --mode=simple --image="$LOGO" --text="$1" --timeout="${2:-3}" > /dev/null 2>&1
}

# 1. Did the previous boot stay up for STABLE_AFTER seconds?
#    crash-guard/stable holds the last boot number that did. No file: treat as stable.
UNSTABLE=0
STABLE=$(cat "$CG/stable" 2>/dev/null)
if [ -n "$STABLE" ] && [ "$PREV" -gt 0 ] && [ "$STABLE" != "$PREV" ] && [ -d "$PREV_ARCH" ]; then
	UNSTABLE=1
fi

# 2. New kernel crash records?
[ -z "$CRASH_GUARD_PSTORE" ] && mount -t pstore pstore "$PSTORE" 2>/dev/null
NEW_CRASH=""
for f in "$PSTORE"/*; do
	[ -f "$f" ] || continue
	name=$(basename "$f")
	key="$name $(cksum < "$f" 2>/dev/null || wc -c < "$f")"
	grep -qxF "$key" "$CG/pstore-seen.txt" 2>/dev/null && continue
	mkdir -p "$CG/crashes/$STAMP"
	cp "$f" "$CG/crashes/$STAMP/$name.txt"
	echo "$key" >> "$CG/pstore-seen.txt"
	NEW_CRASH="$NEW_CRASH $name"
done
if [ -n "$NEW_CRASH" ]; then
	grep -hE 'Kernel panic|Internal error|Unable to handle|PC is at|xfer timeout|WARNING:|watchdog did not stop' \
		"$CG/crashes/$STAMP"/*.txt > "$CG/crashes/$STAMP/summary.txt" 2>/dev/null
fi

# 3. Repair
restore_from_prev() { # $1 name in archive, $2 target
	[ -s "$PREV_ARCH/$1" ] || return 1
	[ -f "$2" ] && cp "$2" "$ARCH/$1.damaged" 2>/dev/null
	cp "$PREV_ARCH/$1" "$2.tmp" && mv "$2.tmp" "$2"
}
REPAIRED=""
if [ "$UNSTABLE" = 1 ]; then
	# crash shortly after start: NextUI was rewriting these files, restore both
	restore_from_prev recent.txt "$RECENT" && REPAIRED="$REPAIRED recent.txt"
	restore_from_prev minuisettings.txt "$MINUI" && REPAIRED="$REPAIRED minuisettings.txt"
elif [ -n "$NEW_CRASH" ] && [ -d "$PREV_ARCH" ]; then
	# crash later in the session: only replace files that are clearly damaged
	[ -s "$RECENT" ] || { restore_from_prev recent.txt "$RECENT" && REPAIRED="$REPAIRED recent.txt"; }
	[ -s "$MINUI" ] || { restore_from_prev minuisettings.txt "$MINUI" && REPAIRED="$REPAIRED minuisettings.txt"; }
fi
MS_DIFF=0
if { [ "$UNSTABLE" = 1 ] || [ -n "$NEW_CRASH" ]; } && [ -s "$PREV_ARCH/msettings.bin" ] && command -v cmp > /dev/null 2>&1; then
	cmp -s "$PREV_ARCH/msettings.bin" "$MSET" || MS_DIFF=1
fi

# boot log
{
	echo "=== Boot $N ==="
	echo "Date:    $(date '+%Y-%m-%d %H:%M:%S')"
	echo "Uptime:  $(cut -d' ' -f1 /proc/uptime 2>/dev/null) s"
	echo "Device:  $DEVICE"
	echo "Version: $(head -n 1 "$SDCARD_PATH/.system/version.txt" 2>/dev/null)"
	echo "Crash Guard: v$CG_VERSION"
	echo "SD mount: $(awk -v m="${SDCARD_PATH:-/mnt/SDCARD}" '$2 == m { print $4; exit }' /proc/mounts 2>/dev/null)"
	for f in "$MSET" "$MINUI" "$SHARED/$LED" "$RECENT"; do
		if [ -f "$f" ]; then echo "$(basename "$f"): $(wc -c < "$f") bytes"; else echo "$(basename "$f"): MISSING"; fi
	done
	dmesg 2>/dev/null | grep -qi "not properly unmounted" && echo "SD card: was not unmounted cleanly"
	[ "$UNSTABLE" = 1 ] && echo "Previous boot: NOT stable, crash assumed"
	[ -n "$NEW_CRASH" ] && echo "New kernel crash record:$NEW_CRASH (see crashes/$STAMP)"
	[ -n "$REPAIRED" ] && echo "Restored from boot $PREV:$REPAIRED"
	[ "$MS_DIFF" = 1 ] && echo "msettings.bin differs from boot $PREV"
	echo
} >> "$CG/boots.log"

# snapshot (after a repair this is the repaired state)
cp "$LOGS_PATH"/*.txt "$ARCH/" 2>/dev/null
cp "$MSET" "$MINUI" "$SHARED/$LED" "$RECENT" "$ARCH/" 2>/dev/null
dmesg > "$ARCH/dmesg.txt" 2>/dev/null

OLD=$((N - KEEP))
[ "$OLD" -gt 0 ] && rm -rf "$CG/archive/$(printf "%04d" "$OLD")"
sync

# on screen notice
[ -n "$REPAIRED" ] && msg "Crash detected: recents and UI settings repaired" 3
[ "$MS_DIFF" = 1 ] && msg "Display and sound changed: run Tools > Restore Settings" 4

# mark this boot as stable after STABLE_AFTER seconds (keeps running in the background)
( sleep "$STABLE_AFTER" && echo "$N" > "$CG/stable" && sync ) > /dev/null 2>&1 &
exit 0
