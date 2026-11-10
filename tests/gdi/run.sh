#!/usr/bin/env bash
# Cross-process GDI drawing, including SetParent, resizing and mixed 32/64-bit processes.
# Requires the real macOS display and explicit permission to show the probe windows:
#   TMP_DIR=/path/to/test-output WINE_CROSS_PROCESS_GDI=1 tests/gdi/run.sh <wine dir> --display
# Without WINE_CROSS_PROCESS_GDI, unpatched Wine reproduces the foreign-window failures.
set -euo pipefail
if [ "${2:-}" != --display ]; then
  echo "Usage: TMP_DIR=<test-output> $0 <wine dir> --display (shows test windows)" >&2
  exit 2
fi
WINE_DIR="$(cd "$1" && pwd)"
cd "$(dirname "$0")"
T="${TMP_DIR:?Set TMP_DIR to a disposable test-output directory}"
mkdir -p "$T"
T="$(cd "$T" && pwd)"
export WINEPREFIX
WINEPREFIX="$(mktemp -d "$T/prefix.XXXXXX")"
# shellcheck disable=SC2329 # Invoked by the EXIT trap.
cleanup() {
  "$WINE_DIR/bin/wineserver" -k >/dev/null 2>&1 || true
  timeout 20 "$WINE_DIR/bin/wineserver" -w >/dev/null 2>&1 || true
  rm -rf "$WINEPREFIX"
}
trap 'cleanup' EXIT
export WINEDEBUG="${WINEDEBUG:--all}" WINEDLLOVERRIDES="mscoree,mshtml=;winemenubuilder.exe=d"
for arch in x86_64 i686; do
  "$arch-w64-mingw32-gcc" -municode -O2 -Wall -Wextra -Werror -o "$T/gdi-$arch.exe" gdiprobe.c -luser32 -lgdi32
done
"$WINE_DIR/bin/wine" reg add 'HKCU\Software\Wine\WineDbg' /v ShowCrashDialog /t REG_DWORD /d 0 /f \
  > "$T/setup.log" 2>&1
# Wine's initial user folders point at the Mac. The probes don't need those mappings.
python3 - "$WINEPREFIX" <<'PY'
from pathlib import Path
import sys
for user in (Path(sys.argv[1]) / "drive_c/users").iterdir():
    if not user.is_dir():
        continue
    for item in user.iterdir():
        if item.is_symlink():
            item.unlink()
            item.mkdir()
PY
failed=0
run() {
  local name="$1" exe="$2" mode="$3" worker="${4:-}" status=0
  local args=("$T/gdi-$exe.exe" "$mode")
  if [ -n "$worker" ]; then args+=("$T/gdi-$worker.exe"); fi
  timeout 30 "$WINE_DIR/bin/wine" "${args[@]}" > "$T/$name.log" 2>&1 || status=$?
  if [ "$status" -eq 0 ] && tr -d '\r' < "$T/$name.log" | grep -q 'RESULT .*samples=10 failures=0'; then
    echo "PASS $name"
  else
    echo "FAIL $name (exit $status)"
    failed=1
  fi
}
for arch in x86_64 i686; do
  run "$arch-control" "$arch" 0
  run "$arch-child" "$arch" 1
  run "$arch-reparent" "$arch" 2
  run "$arch-resize" "$arch" 3
done
run x64-to-x86 x86_64 2 i686
run x86-to-x64 i686 2 x86_64
exit "$failed"
