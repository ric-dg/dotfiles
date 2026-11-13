#!/usr/bin/env bash
#
# android-connect.sh - connect to an Android device over TCP/IP and mirror its screen.
#
# Works for any device reachable over the network (a robot tablet on Tailscale, a
# phone on the LAN, ...). Arguments may be a Tailscale/MagicDNS node name, which is
# resolved to its tailnet IP first. The device must have adb-over-TCP enabled: on
# the device run `adb tcpip 5555`, or use one that advertises _adb-tls-connect.
#
# Exit codes: 0 ok, 2 usage, 3 missing tool, 4 device not ready, 5 target is this host.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: android-connect.sh [options] [host|ip][:port]

  host|ip            device name/IP (Tailscale MagicDNS, LAN, ...); default $ANDROID_HOST
  --serial SERIAL    use an already connected serial (USB or host:port); skip adb connect

Options:
  -n, --no-window         do not open a scrcpy window
  -r, --record FILE       record the screen to FILE (mp4); implies --no-window
      --no-mirror         connect only; do not start scrcpy
  -w, --stay-awake        keep the device screen awake while mirroring
  -S, --turn-screen-off   turn the device screen off while mirroring
      --codec NAME        scrcpy video codec: h264 (default), h265, av1
  -h, --help              this help

Environment:
  ANDROID_HOST      default device when no argument is given
  ANDROID_PORT      adb-over-TCP port (default 5555)
  ANDROID_MAX_SIZE  scrcpy --max-size       (default 1280)
  ANDROID_BIT_RATE  scrcpy --video-bit-rate (default 4M, light for a remote link)
  ANDROID_MAX_FPS   scrcpy --max-fps        (default 30)
  ANDROID_AUDIO=1   also forward audio       (default off, keeps the link light)
  ANDROID_CODEC     same as --codec
  ANDROID_CONNECT_TIMEOUT  seconds to wait for `adb connect` (default 10)
  ADB, SCRCPY       tool paths (default: from PATH)
EOF
}

die() { printf 'android-connect: %s\n' "$*" >&2; exit "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }

host='' serial='' record='' codec=''
mirror=1 window=1 stay_awake=0 screen_off=0

while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    -n|--no-window) window=0 ;;
    -r|--record) [ "$#" -ge 2 ] || die "--record needs a file" 2; record=$2; shift ;;
    --record=*) record=${1#*=} ;;
    --no-mirror) mirror=0 ;;
    -w|--stay-awake) stay_awake=1 ;;
    -S|--turn-screen-off) screen_off=1 ;;
    --codec) [ "$#" -ge 2 ] || die "--codec needs a name" 2; codec=$2; shift ;;
    --codec=*) codec=${1#*=} ;;
    --serial) [ "$#" -ge 2 ] || die "--serial needs a value" 2; serial=$2; shift ;;
    --serial=*) serial=${1#*=} ;;
    -*) die "unknown option: $1 (see --help)" 2 ;;
    *) [ -z "$host" ] || die "unexpected argument: $1" 2; host=$1 ;;
  esac
  shift
done

adb=${ADB:-adb}
scrcpy=${SCRCPY:-scrcpy}
have "$adb" || die "adb not found (install android-tools)" 3
if [ "$mirror" = 1 ]; then have "$scrcpy" || die "scrcpy not found (install scrcpy)" 3; fi
[ -n "$record" ] && window=0        # recording does not need a window

# Resolve a MagicDNS/tailnet node name to its IPv4 address; leave IPs and
# unresolved names alone (adb/DNS may still handle them).
resolve_host() {
  local h=$1 ip
  case $h in
    *:*) printf '%s' "$h"; return ;;        # already host:port
    *[!0-9.]*) ;;                           # not an IPv4 literal: may be a name
    *) printf '%s' "$h"; return ;;          # IPv4 literal
  esac
  if have tailscale; then
    ip=$(tailscale ip -4 "$h" 2>/dev/null | head -1 || true)
    if [ -n "$ip" ]; then printf '%s' "$ip"; return; fi
  fi
  printf '%s' "$h"
}

if [ -z "$serial" ]; then
  host=${host:-${ANDROID_HOST:-}}
  [ -n "$host" ] || die "no device given: pass <host|ip>, --serial, or set ANDROID_HOST" 2
  host=$(resolve_host "$host")
  case $host in
    *:*) serial=$host ;;
    *)   serial=$host:${ANDROID_PORT:-5555} ;;
  esac
fi

# Guard: a tailnet IP of this machine is never the tablet.
if have tailscale; then
  for ip in $(tailscale ip 2>/dev/null || true); do
    [ "$ip" = "${serial%:*}" ] &&
      die "${serial%:*} is this machine ($(uname -n)) - pass the tablet's name/IP instead" 5
  done
fi

printf 'Connecting to %s ...\n' "$serial"
# adb connect has no timeout of its own and can block for minutes on a peer
# that is off the tailnet (packets are dropped, not refused).
connect_msg=$(timeout "${ANDROID_CONNECT_TIMEOUT:-10}" "$adb" connect "$serial" 2>&1 || true)
[ -n "$connect_msg" ] ||
  connect_msg="no response within ${ANDROID_CONNECT_TIMEOUT:-10}s"

# Wait until the device is usable ("device", not "offline"/"unauthorized").
state='' i=0
while [ "$i" -lt 20 ]; do
  state=$("$adb" -s "$serial" get-state 2>/dev/null || true)
  [ "$state" = device ] && break
  sleep 0.5
  i=$((i + 1))
done
case $state in
  device) ;;
  unauthorized) die "device $serial is unauthorized: accept the USB debugging prompt on the device" 4 ;;
  *) die "device $serial not ready (state: ${state:-none})${connect_msg:+; adb said: $connect_msg}
  same network and Tailscale up? is adb-over-TCP enabled (adb tcpip 5555)?" 4 ;;
esac

printf 'Connected: %s\n' "$serial"
"$adb" devices -l
[ "$mirror" = 1 ] || exit 0

# scrcpy sized and rate-limited for a remote link.
scrcpy_args=(
  -s "$serial"
  --max-size "${ANDROID_MAX_SIZE:-1280}"
  --video-bit-rate "${ANDROID_BIT_RATE:-4M}"
  --max-fps "${ANDROID_MAX_FPS:-30}"
)
[ "${ANDROID_AUDIO:-0}" = 1 ] || scrcpy_args+=( --no-audio )
[ "$window" = 1 ] || scrcpy_args+=( --no-window )
[ "$stay_awake" = 1 ] && scrcpy_args+=( --stay-awake )
[ "$screen_off" = 1 ] && scrcpy_args+=( --turn-screen-off )
codec=${codec:-${ANDROID_CODEC:-}}
[ -n "$codec" ] && scrcpy_args+=( --video-codec "$codec" )
if [ -n "$record" ]; then
  printf 'Recording to %s\n' "$record"
  scrcpy_args+=( --record "$record" )
fi

exec "$scrcpy" "${scrcpy_args[@]}"
