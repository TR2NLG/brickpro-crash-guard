#!/bin/sh
# Crash Guard: switches the boot hook on or off.
# https://github.com/TR2NLG/brickpro-crash-guard

cd "$(dirname "$0")"
LOGO="$SDCARD_PATH/.system/res/logo.png"
HOOK_DIR="$USERDATA_PATH/.hooks/boot.d"
STUB="$HOOK_DIR/crash-guard.sync.sh"

msg() {
	echo "$1"
	show2.elf --mode=simple --image="$LOGO" --text="$1" --timeout="${2:-2}" 2>/dev/null
}

if [ -f "$STUB" ]; then
	rm -f "$STUB"
	sync
	msg "Crash Guard disabled" 3
	exit 0
fi

mkdir -p "$HOOK_DIR" || { msg "Error: cannot create hook folder" 3; exit 1; }
cat > "$STUB" <<'EOS'
#!/bin/sh
# Crash Guard boot hook, created by Tools > Crash Guard
# https://github.com/TR2NLG/brickpro-crash-guard
S="${SDCARD_PATH:-/mnt/SDCARD}/Tools/${PLATFORM:-tg5040}/Crash Guard.pak/crash-guard.sh"
[ -f "$S" ] && sh "$S"
exit 0
EOS
chmod +x "$STUB" 2>/dev/null
sync
msg "Crash Guard enabled, active from next start" 3
