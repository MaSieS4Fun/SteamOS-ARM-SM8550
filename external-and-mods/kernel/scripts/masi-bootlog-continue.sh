#!/bin/bash
# Continue appending dmesg to /boot/masi-boot.log after switch_root (debug builds).
set -u

BOOT="/boot/masi-boot.log"
RUN="/run/masi-bootlog-continue.pid"
DURATION="${MASIBOOTLOG_SECONDS:-120}"

[ -d /boot ] || exit 0
grep -q 'masi\.bootlog=1' /proc/cmdline 2>/dev/null || exit 0

if [ -f "${RUN}" ]; then
	read -r oldpid < "${RUN}" 2>/dev/null || true
	[ -n "${oldpid}" ] && kill "${oldpid}" 2>/dev/null
fi

{
	echo "===== MaSi boot log (userspace) $(date -u '+%Y-%m-%dT%H:%M:%SZ') ====="
	echo "--- cmdline ---"
	cat /proc/cmdline
	echo "--- dmesg userspace-start ---"
	dmesg
	echo
} >> "${BOOT}"

(
	end=$(( $(date +%s) + DURATION ))
	while [ "$(date +%s)" -lt "${end}" ]; do
		sleep 3
		dmesg -c >> "${BOOT}" 2>/dev/null
		sync /boot 2>/dev/null || sync
	done
	{
		echo "--- dmesg userspace-end $(date -u '+%Y-%m-%dT%H:%M:%SZ') ---"
		dmesg
		echo "===== end userspace capture ====="
		echo
	} >> "${BOOT}"
	sync /boot 2>/dev/null || sync
) &
echo $! > "${RUN}"
