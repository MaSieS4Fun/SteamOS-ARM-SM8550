#!/usr/bin/env bash
# Capture kernel / boot logs on the handheld (no photos needed).
# Usage on device:
#   ./scripts/capture-kernel-log.sh
#   ./scripts/capture-kernel-log.sh --since-boot --errors
#   ./scripts/capture-kernel-log.sh --prev-boot
#
# Saves under ~/kernel-logs/ and prints the file path.
set -euo pipefail

OUT_DIR="${KERNEL_LOG_DIR:-${HOME}/kernel-logs}"
STAMP="$(date +%Y%m%d-%H%M%S%N)"
STAMP="${STAMP:0:18}" # trim ns to keep filenames readable
KERNEL="$(uname -r)"
MODE="current"
FILTER="all"
SINCE_BOOT=0
TAGS=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	--prev-boot|-p) MODE="prev"; TAGS+=("prev") ;;
	--since-boot|-b) SINCE_BOOT=1; TAGS+=("full") ;;
	--errors|-e) FILTER="errors"; TAGS+=("err") ;;
	--warn|-w) FILTER="warn"; TAGS+=("warn") ;;
	--help|-h)
		cat <<'EOF'
capture-kernel-log.sh — save dmesg/journal to ~/kernel-logs/

  (default)     dmesg + journal kernel lines (current boot)
  --prev-boot   previous boot via journalctl (-b -1)
  --since-boot  include full journal since boot (can be large)
  --errors      only err/crit/alert/emerg
  --warn        err + warning

Examples:
  ./scripts/capture-kernel-log.sh
  ./scripts/capture-kernel-log.sh --errors > /dev/null && ls -t ~/kernel-logs | head -1
  scp steam@handheld:~/kernel-logs/*.log .
EOF
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
	shift
done

mkdir -p "${OUT_DIR}"
SUFFIX=""
if ((${#TAGS[@]} > 0)); then
	SUFFIX="-$(IFS=-; echo "${TAGS[*]}")"
fi
BASE="${OUT_DIR}/kernel-${KERNEL}-${STAMP}${SUFFIX}"
DMESG="${BASE}-dmesg.log"
JOURNAL="${BASE}-journal.log"
META="${BASE}-meta.txt"

{
	echo "date: $(date -Is)"
	echo "kernel: ${KERNEL}"
	echo "hostname: $(hostname)"
	echo "cmdline: $(cat /proc/cmdline 2>/dev/null || true)"
	echo "uptime: $(uptime -p 2>/dev/null || uptime)"
} >"${META}"

if command -v dmesg >/dev/null 2>&1; then
	if [[ "${FILTER}" == "errors" ]]; then
		dmesg --level=err,crit,alert,emerg 2>/dev/null >"${DMESG}" \
			|| dmesg 2>/dev/null | grep -iE 'error|fail|fatal|panic|bug:' >"${DMESG}" || true
	elif [[ "${FILTER}" == "warn" ]]; then
		dmesg --level=warn,err,crit,alert,emerg 2>/dev/null >"${DMESG}" \
			|| dmesg 2>/dev/null | grep -iE 'warn|error|fail|fatal' >"${DMESG}" || true
	else
		dmesg 2>/dev/null >"${DMESG}" || true
	fi
fi

if command -v journalctl >/dev/null 2>&1; then
	J_ARGS=(-k --no-pager)
	case "${MODE}" in
	prev) J_ARGS+=(-b -1) ;;
	*) J_ARGS+=(-b 0) ;;
	esac
	case "${FILTER}" in
	errors) J_ARGS+=(-p err..emerg) ;;
	warn) J_ARGS+=(-p warning..emerg) ;;
	esac
	if [[ "${SINCE_BOOT}" -eq 1 ]]; then
		journalctl -b 0 --no-pager >"${JOURNAL}" 2>/dev/null || true
	else
		journalctl "${J_ARGS[@]}" >"${JOURNAL}" 2>/dev/null || true
	fi
fi

# One combined file for easy sharing
COMBO="${BASE}-combined.log"
{
	echo "=== meta ==="
	cat "${META}"
	echo
	echo "=== dmesg ==="
	[[ -f "${DMESG}" ]] && cat "${DMESG}"
	echo
	if [[ "${SINCE_BOOT}" -eq 1 ]]; then
		echo "=== journal (full boot) ==="
	else
		echo "=== journal (kernel) ==="
	fi
	[[ -f "${JOURNAL}" ]] && cat "${JOURNAL}"
} >"${COMBO}"

# Compact summary: unique lines, skip known spam
SUMMARY="${BASE}-summary.log"
{
	echo "=== meta ==="
	cat "${META}"
	echo
	echo "=== unique kernel messages (spam filtered) ==="
	{
		[[ -f "${DMESG}" ]] && cat "${DMESG}"
		[[ -f "${JOURNAL}" ]] && grep ' kernel: ' "${JOURNAL}" 2>/dev/null | sed 's/^[^ ]* [^ ]* [^ ]* kernel: //'
	} | grep -v 'Handover signaled, but it already happened' \
		| sed 's/^\[[^]]*\] //' \
		| sort -u | head -200
} >"${SUMMARY}" 2>/dev/null || true

# Trim old logs (keep last 20 bundles)
ls -1t "${OUT_DIR}"/kernel-*-combined.log 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -1t "${OUT_DIR}"/kernel-*-dmesg.log 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -1t "${OUT_DIR}"/kernel-*-journal.log 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -1t "${OUT_DIR}"/kernel-*-meta.txt 2>/dev/null | tail -n +21 | xargs -r rm -f
ls -1t "${OUT_DIR}"/kernel-*-summary.log 2>/dev/null | tail -n +21 | xargs -r rm -f

echo "${SUMMARY}"
echo "  combined: ${COMBO}" >&2
echo "  dmesg:    ${DMESG}" >&2
echo "  journal:  ${JOURNAL}" >&2
echo "  share:    scp $(whoami)@$(hostname -I 2>/dev/null | awk '{print $1}'):${SUMMARY} ." >&2
