#!/usr/bin/env bash
#
# android-install.sh - install an APK, launch it, and stream its logs.
#
# The device is chosen with ANDROID_SERIAL (adb's standard variable); with a
# single attached device it is picked automatically. Logs are filtered to the
# app's pid by default, which needs Android 8+; older devices fall back to a
# package-name grep.
#
# Exit codes: 0 ok, 2 usage/bad APK, 3 missing tool, 4 device/package undetermined.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: android-install.sh [options] <app.apk> [package]

  app.apk            APK to install (adb install -r)
  package            package name; auto-detected from the APK when omitted

Options:
  -n, --no-launch    install only; do not start the app
  -l, --no-logs      start the app but do not stream logs
  -L, --logs-only    skip install/launch; stream logs for <app.apk|package>
  -c, --clear        clear logcat before launching
  -t, --tag TAG      only show this tag (a comma-separated list adds more)
  -v, --level LEVEL  minimum level: V D I W E F (default V)
  -f, --file FILE    also write the log stream to FILE
  -d, --downgrade    allow an older versionCode (adb install -d)
  -h, --help         this help

Environment:
  ANDROID_SERIAL  target device (serial or host:port); default: the single device
  ADB             adb binary (default: from PATH)
  AAPT2           aapt2 binary (default: newest under $ANDROID_HOME/build-tools/*)

Ctrl-C stops the log stream. The app stays installed and running.
EOF
}

die() { printf 'android-install: %s\n' "$*" >&2; exit "${2:-1}"; }
have() { command -v "$1" >/dev/null 2>&1; }

no_launch=0 no_logs=0 logs_only=0 clear_logs=0 downgrade=0
tag='' level=V file=''
pos=()

while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    -n|--no-launch) no_launch=1 ;;
    -l|--no-logs) no_logs=1 ;;
    -L|--logs-only) logs_only=1 no_launch=1 ;;
    -c|--clear) clear_logs=1 ;;
    -d|--downgrade) downgrade=1 ;;
    -t|--tag) [ "$#" -ge 2 ] || die "--tag needs a value" 2; tag=$2; shift ;;
    --tag=*) tag=${1#*=} ;;
    -v|--level) [ "$#" -ge 2 ] || die "--level needs a value" 2; level=$2; shift ;;
    --level=*) level=${1#*=} ;;
    -f|--file) [ "$#" -ge 2 ] || die "--file needs a path" 2; file=$2; shift ;;
    --file=*) file=${1#*=} ;;
    -*) die "unknown option: $1 (see --help)" 2 ;;
    *) pos+=( "$1" ) ;;
  esac
  shift
done

[ "${#pos[@]}" -ge 1 ] || { usage >&2; exit 2; }
[ "${#pos[@]}" -le 2 ] || die "too many arguments: ${pos[*]}" 2

# First positional is an APK when it exists on disk, otherwise a package name
# (that form is only meaningful with --logs-only).
apk='' pkg=''
if [ -f "${pos[0]}" ]; then
  apk=${pos[0]}
  pkg=${pos[1]:-}
else
  pkg=${pos[0]}
  [ "$logs_only" = 1 ] || die "not a file: ${pos[0]} (use --logs-only to stream by package name)" 2
fi

case ${level^^} in
  V|D|I|W|E|F) level=${level^^} ;;
  *) die "bad log level: $level (use V D I W E F)" 2 ;;
esac

adb=${ADB:-adb}
have "$adb" || die "adb not found (install android-tools)" 3

adb_args=()
if [ -n "${ANDROID_SERIAL:-}" ]; then
  adb_args=( -s "$ANDROID_SERIAL" )
else
  # Refuse to guess when more than one device is attached.
  ndev=$("$adb" devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')
  [ "$ndev" -ge 1 ] || die "no device connected (run android-connect.sh first, or set ANDROID_SERIAL)" 4
  [ "$ndev" -eq 1 ] || die "$ndev devices connected; set ANDROID_SERIAL to choose one" 4
fi

# --- locate aapt2 (used for package + launchable-activity detection) ---------
aapt2=''
if [ -n "${AAPT2:-}" ]; then
  aapt2=$AAPT2
elif have aapt2; then
  aapt2=$(command -v aapt2)
elif [ -n "${ANDROID_HOME:-}" ]; then
  aapt2=$(printf '%s\n' "$ANDROID_HOME"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
  [ -x "$aapt2" ] || aapt2=''
fi

badging=''
if [ -n "$apk" ] && [ -n "$aapt2" ]; then
  badging=$("$aapt2" dump badging "$apk" 2>/dev/null || true)
fi

# --- resolve the package name ------------------------------------------------
if [ -z "$pkg" ] && [ -n "$badging" ]; then
  pkg=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)
fi
[ -n "$pkg" ] || die "could not determine the package name; pass it as the 2nd argument" 4

# --- install -----------------------------------------------------------------
if [ -n "$apk" ]; then
  install_args=( -r )
  [ "$downgrade" = 1 ] && install_args+=( -d )
  printf 'Installing %s -> %s\n' "$apk" "$pkg"
  "$adb" "${adb_args[@]}" install "${install_args[@]}" "$apk"
fi

# --- launch ------------------------------------------------------------------
launch=''
if [ "$no_launch" = 0 ]; then
  if [ -n "$badging" ]; then
    launch=$(printf '%s\n' "$badging" | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -1)
  fi
  [ "$clear_logs" = 1 ] && "$adb" "${adb_args[@]}" logcat -c 2>/dev/null || true
  if [ -n "$launch" ]; then
    "$adb" "${adb_args[@]}" shell am start -n "$pkg/$launch"
  else
    "$adb" "${adb_args[@]}" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null
  fi
fi
[ "$no_logs" = 0 ] || exit 0

# --- stream logs -------------------------------------------------------------
# Give the app a moment to register a pid so --pid filtering works. Only wait
# when we just launched it; with --logs-only one attempt is enough.
tries=1
[ "$no_launch" = 0 ] && tries=10
pid='' i=0
while [ "$i" -lt "$tries" ]; do
  pid=$("$adb" "${adb_args[@]}" shell pidof -s "$pkg" 2>/dev/null | tr -d '\r' || true)
  [ -n "$pid" ] && break
  sleep 0.5
  i=$((i + 1))
done

opts=( -v threadtime )
# --pid (Android 8+) is the precise filter; with explicit tags it is unnecessary.
[ -n "$pid" ] && [ -z "$tag" ] && opts+=( --pid="$pid" )
specs=()
if [ -n "$tag" ]; then
  for t in ${tag//,/ }; do specs+=( "$t:$level" ); done
  specs+=( '*:S' )
elif [ -z "$pid" ]; then
  specs+=( "*:$level" )
fi

printf '\nStreaming logcat for %s%s  (Ctrl-C to stop)\n' "$pkg" "${pid:+ (pid $pid)}"
if [ -n "$file" ]; then
  printf 'Writing to %s\n' "$file"
  "$adb" "${adb_args[@]}" logcat "${opts[@]}" "${specs[@]}" 2>&1 | tee "$file"
elif [ -n "$pid" ] || [ -n "$tag" ]; then
  exec "$adb" "${adb_args[@]}" logcat "${opts[@]}" "${specs[@]}"
else
  # No pid and no tag (app not running): filter by the package name instead.
  "$adb" "${adb_args[@]}" logcat "${opts[@]}" | grep --line-buffered -i -- "$pkg"
fi
