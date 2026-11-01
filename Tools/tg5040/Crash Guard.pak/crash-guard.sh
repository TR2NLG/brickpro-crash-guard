#!/bin/sh
# Crash Guard for NextUI on the TrimUI Brick Pro
# https://github.com/TR2NLG/brickpro-crash-guard
#
# Called at every boot by .userdata/<platform>/.hooks/boot.d/crash-guard.sync.sh,
# before the NextUI menu starts. It
#   1. keeps a short boot log and per boot snapshots of logs and settings,
#   2. saves new kernel crash records (pstore) to crash-guard/crashes/,
#   3. after a crash, puts recent.txt and minuisettings.txt back from the
#      snapshot taken before NextUI could damage them. A crash needs evidence:
#      a new kernel crash record, an SD card that was not unmounted cleanly,
#      or a power cut. A quick power off from the menu is not a crash.
#   4. detects starts after the power was cut (a power off that did not
#      complete and needed a long press reset, or an empty battery) and
#      records them in crash-guard/events.log.
# msettings.bin cannot be repaired here, because keymon has already loaded it.
# For that, use Tools > Restore Settings.

CG_VERSION="1.0.3"
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

kernel_log() {
	if [ -n "$CRASH_GUARD_DMESG" ]; then cat "$CRASH_GUARD_DMESG"; else dmesg 2>/dev/null; fi
}
KLOG=$(kernel_log)

log_event() {
	echo "$(date '+%Y-%m-%d %H:%M') boot $N: $1" >> "$CG/events.log"
}

msg() {
	show2.elf --mode=simple --image="$LOGO" --text="$1" --timeout="${2:-3}" > /dev/null 2>&1
}

# 1. Did the previous boot stay up for STABLE_AFTER seconds?
#    crash-guard/stable holds the last boot number that did. No file: treat as stable.
#    A short boot alone is no crash, see the evidence check below.
SHORT_PREV=0
STABLE=$(cat "$CG/stable" 2>/dev/null)
if [ -n "$STABLE" ] && [ "$PREV" -gt 0 ] && [ "$STABLE" != "$PREV" ] && [ -d "$PREV_ARCH" ]; then
	SHORT_PREV=1
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

# 3. Was the power cut before this start?
#    Normal starts after a power off report "hot reboot" and keep the clock.
#    After a long press hard reset or an empty battery the kernel reports
#    "cold boot" and the RTC starts at 1970.
BOOT_TYPE="unknown"
echo "$KLOG" | grep -q "fix to hot reboot" && BOOT_TYPE="hot reboot"
echo "$KLOG" | grep -q "fix to cold boot" && BOOT_TYPE="cold boot"
RTC_RESET=0
echo "$KLOG" | grep -qE "setting system clock to 19[0-9][0-9]-" && RTC_RESET=1
POWER_CUT=0
{ [ "$BOOT_TYPE" = "cold boot" ] || [ "$RTC_RESET" = 1 ]; } && POWER_CUT=1
# context of the previous session (nextui.txt still holds its log at this point)
PREV_SLEEPS=$(grep -c "Entering hybrid sleep" "$LOGS_PATH/nextui.txt" 2>/dev/null)
case "$PREV_SLEEPS" in ''|*[!0-9]*) PREV_SLEEPS=0 ;; esac
WIFI=$(grep -m1 '^wifi=' "$MINUI" 2>/dev/null | cut -d= -f2)
case "$WIFI" in 1) WIFI="on" ;; 0) WIFI="off" ;; *) WIFI="unknown" ;; esac

# 4. Evidence for a crash
#    A menu power off unmounts the card cleanly and leaves no kernel record,
#    so a quick power off after a short boot is not treated as a crash.
DIRTY=0
echo "$KLOG" | grep -qi "not properly unmounted" && DIRTY=1
EVIDENCE=""
[ -n "$NEW_CRASH" ] && EVIDENCE="$EVIDENCE kernel crash record,"
[ "$DIRTY" = 1 ] && EVIDENCE="$EVIDENCE SD card not unmounted cleanly,"
[ "$POWER_CUT" = 1 ] && EVIDENCE="$EVIDENCE power cut,"
EVIDENCE=${EVIDENCE%,}
UNSTABLE=0
[ "$SHORT_PREV" = 1 ] && [ -n "$EVIDENCE" ] && UNSTABLE=1

# 5. Repair
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
elif [ -n "$EVIDENCE" ] && [ -d "$PREV_ARCH" ]; then
	# crash or power cut later in the session: only replace files that are clearly damaged
	[ -s "$RECENT" ] || { restore_from_prev recent.txt "$RECENT" && REPAIRED="$REPAIRED recent.txt"; }
	[ -s "$MINUI" ] || { restore_from_prev minuisettings.txt "$MINUI" && REPAIRED="$REPAIRED minuisettings.txt"; }
fi
MS_DIFF=0
if [ -n "$EVIDENCE" ] && [ -s "$PREV_ARCH/msettings.bin" ] && command -v cmp > /dev/null 2>&1; then
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
	[ "$DIRTY" = 1 ] && echo "SD card: was not unmounted cleanly"
	[ "$UNSTABLE" = 1 ] && echo "Previous boot: shorter than ${STABLE_AFTER} s and crash evidence:$EVIDENCE"
	[ "$SHORT_PREV" = 1 ] && [ "$UNSTABLE" = 0 ] && echo "Previous boot: shorter than ${STABLE_AFTER} s, no crash evidence (normal quick power off)"
	[ -n "$NEW_CRASH" ] && echo "New kernel crash record:$NEW_CRASH (see crashes/$STAMP)"
	[ -n "$REPAIRED" ] && echo "Restored from boot $PREV:$REPAIRED"
	[ "$MS_DIFF" = 1 ] && echo "msettings.bin differs from boot $PREV"
	echo "Boot type: $BOOT_TYPE"
	[ "$RTC_RESET" = 1 ] && echo "RTC: was reset, the clock started at 1970"
	echo "Previous session: $PREV_SLEEPS sleep cycle(s), Wi-Fi setting: $WIFI"
	[ "$POWER_CUT" = 1 ] && echo "Power was cut before this start: a power off that did not complete (long press reset) or an empty battery, see crashes/$STAMP/power-cut.txt"
	echo
} >> "$CG/boots.log"

# power cut report, ready to attach to an issue
if [ "$POWER_CUT" = 1 ]; then
	mkdir -p "$CG/crashes/$STAMP"
	{
		echo "Crash Guard v$CG_VERSION, boot $N"
		echo "NextUI: $(head -n 1 "$SDCARD_PATH/.system/version.txt" 2>/dev/null)"
		echo "Device: $DEVICE"
		echo "Boot type: $BOOT_TYPE"
		echo "RTC reset: $([ "$RTC_RESET" = 1 ] && echo yes || echo no)"
		echo "Previous session: $PREV_SLEEPS sleep cycle(s), Wi-Fi setting: $WIFI"
		echo
		echo "Kernel lines:"
		echo "$KLOG" | grep -E "fix to (cold|hot)|setting system clock|not properly unmounted"
		echo
		echo "Last 40 lines of the previous NextUI session:"
		tail -n 40 "$LOGS_PATH/nextui.txt" 2>/dev/null
	} > "$CG/crashes/$STAMP/power-cut.txt"
fi

# event log: one line per notable event
[ "$UNSTABLE" = 1 ] && log_event "previous boot crashed within ${STABLE_AFTER} s (evidence:$EVIDENCE)${REPAIRED:+, restored:$REPAIRED}"
[ "$UNSTABLE" = 0 ] && [ -n "$REPAIRED" ] && log_event "damaged files after${EVIDENCE}, restored:$REPAIRED"
[ -n "$NEW_CRASH" ] && log_event "kernel crash record:$NEW_CRASH (crashes/$STAMP)"
[ "$POWER_CUT" = 1 ] && log_event "power was cut before this start ($BOOT_TYPE$([ "$RTC_RESET" = 1 ] && echo ', RTC reset, date unreliable')), previous session: $PREV_SLEEPS sleep cycle(s), Wi-Fi $WIFI (crashes/$STAMP/power-cut.txt)"

# snapshot (after a repair this is the repaired state)
cp "$LOGS_PATH"/*.txt "$ARCH/" 2>/dev/null
cp "$MSET" "$MINUI" "$SHARED/$LED" "$RECENT" "$ARCH/" 2>/dev/null
echo "$KLOG" > "$ARCH/dmesg.txt"

OLD=$((N - KEEP))
[ "$OLD" -gt 0 ] && rm -rf "$CG/archive/$(printf "%04d" "$OLD")"
sync

# on screen notice
[ -n "$REPAIRED" ] && msg "Crash detected: recents and UI settings repaired" 3
[ "$MS_DIFF" = 1 ] && msg "Display and sound changed: run Tools > Restore Settings" 4

# mark this boot as stable after STABLE_AFTER seconds (keeps running in the background)
( sleep "$STABLE_AFTER" && echo "$N" > "$CG/stable" && sync ) > /dev/null 2>&1 &
exit 0
