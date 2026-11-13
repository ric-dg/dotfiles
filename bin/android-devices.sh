#!/usr/bin/env bash
#
# android-devices.sh - list attached adb devices and Android peers on the tailnet.
#
# Answers "which device do I pass to android-connect.sh?" without guessing: the
# attached list is what adb can talk to right now, the tailnet list is what could
# be connected to (with its MagicDNS name, which android-connect.sh resolves).
#
# Exit codes: 0 ok, 2 usage, 3 missing tool.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: android-devices.sh [options]

  -a, --adb-only    only attached adb devices
  -t, --tailnet     only Android peers on the tailnet
  -h, --help        this help

Output:
  attached: serial, state, model, Android version, transport
  tailnet:  MagicDNS name, IP, online state (Android devices only)

The "next step" line under each entry is ready to copy-paste.
EOF
}

die() { printf 'android-devices.sh: %s\n' "$*" >&2; exit "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }

show_adb=1 show_tailnet=1
while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    -a|--adb-only) show_tailnet=0 ;;
    -t|--tailnet) show_adb=0 ;;
    -*) die "unknown option: $1 (see --help)" 2 ;;
    *) die "unexpected argument: $1" 2 ;;
  esac
  shift
done

adb=${ADB:-adb}

if [ "$show_adb" = 1 ]; then
  have "$adb" || die "adb not found (install android-tools)" 3
  printf '== attached devices ==\n'
  found=0
  while read -r serial state rest; do
    [ -n "$serial" ] || continue
    found=1
    model=''
    for f in ${rest:-}; do
      case $f in model:*) model=${f#model:} ;; esac
    done
    case $serial in *:*) transport=tcp ;; *) transport=usb ;; esac
    ver=''
    if [ "$state" = device ]; then
      rel=$(timeout 3 "$adb" -s "$serial" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r' || true)
      sdk=$(timeout 3 "$adb" -s "$serial" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r' || true)
      ver="Android ${rel:-?}${sdk:+ (SDK $sdk)}"
    fi
    printf '%-24s %-9s %-16s %-22s %s\n' \
      "$serial" "$state" "${model:-?}" "${ver:-?}" "$transport"
    [ "$state" = device ] &&
      printf '  ANDROID_SERIAL=%s android-install.sh <app.apk>\n' "$serial"
  done < <("$adb" devices -l | sed -n '2,$p' | grep .)
  [ "$found" = 1 ] || printf '  (none)\n'
fi

if [ "$show_tailnet" = 1 ]; then
  have tailscale || die "tailscale not found (install tailscale)" 3
  [ "$show_adb" = 1 ] && echo
  printf '== tailnet Android peers ==\n'
  found=0
  while IFS='|' read -r name ip state; do
    [ -n "$name" ] || continue
    found=1
    printf '%-24s %-16s %s\n' "$name" "$ip" "$state"
    case $state in
      offline*) ;;
      *) printf '  android-connect.sh %s\n' "$name" ;;
    esac
  done < <(tailscale status 2>/dev/null |
             awk '$4=="android" { ip=$1; name=$2; $1=$2=$3=$4=""; sub(/^ +/,""); print name "|" ip "|" $0 }')
  [ "$found" = 1 ] || printf '  (none)\n'
  printf '\nNote: an offline peer cannot be connected to until it is back on the tailnet.\n'
fi
