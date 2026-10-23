#!/usr/bin/env bash
# Builds ExePort's Wine: stock Wine 11.0 with the patches in patches/, for Apple Silicon through Rosetta
# (x86_64 with the new WoW64, so 32-bit games run without 32-bit macOS code), plus Wine Mono and Wine Gecko.
#   wine/build.sh                -> $OUT_DIR/exeport-wine-<wine>-<revision>.tar.xz
# The archive holds one folder, `wine/`, laid out as Wine installs itself (bin/ lib/ share/) plus licenses/;
# the runtime manifest installs it with `"from": "wine", "into": "wine"`.
#
# Why build Wine: DXMT (Direct3D 10/11 on Metal) needs winemac's `macdrv_functions` table, which stock Wine and
# Gcenx's current builds don't export (DXMT then logs "Failed to create metal view"). patches/0001 adds it.
# Why Wine 11.0: the stable branch, the version every backend was tested on with WhiskyWine 3.1.1 (DXVK, DXMT
# and WineD3D, 32- and 64-bit), and the one Wine Mono/Gecko pins below match. Development releases change
# every two weeks; move to 12.0 when it ships.
#
# Trust: every download is pinned by SHA-256. Wine, Mono and Gecko come from WineHQ. The x86_64 runtime libraries
# Wine loads (FreeType, GnuTLS, SDL2, MoltenVK, the Vulkan loader and their dependencies) are taken from Gcenx's
# Wine 11.18 build, the same pin MaPC uses, since Homebrew on Apple Silicon only has arm64 ones.
#
# Env:
#   CACHE_DIR  downloads (default wine/.cache/dl)    WORK_DIR  build tree (default wine/.cache/work)
#   OUT_DIR    default wine/dist                     REVISION  build number of this Wine version (default 1)
#   RESUME=1   continue the build tree in WORK_DIR (after fixing a failure) instead of reconfiguring
# Needs: Xcode, Rosetta, `brew install bison pkgconf freetype gnutls sdl2 mingw-w64`.
set -euo pipefail
cd "$(dirname "$0")"
REVISION="${REVISION:-1}"
CACHE="${CACHE_DIR:-.cache/dl}"; WORK="${WORK_DIR:-.cache/work}"; OUT="${OUT_DIR:-dist}"
mkdir -p "$CACHE" "$WORK" "$OUT"
CACHE="$(cd "$CACHE" && pwd)"; WORK="$(cd "$WORK" && pwd)"; OUT="$(cd "$OUT" && pwd)"

WINE_VERSION="11.0"
WINE_NAME="wine-$WINE_VERSION.tar.xz"
WINE_URL="https://dl.winehq.org/wine/source/11.0/$WINE_NAME"
WINE_SHA="c07a6857933c1fc60dff5448d79f39c92481c1e9db5aa628db9d0358446e0701"
# The versions Wine 11.0 asks for (MONO_VERSION and GECKO_VERSION in dlls/appwiz.cpl/addons.c); checked below.
MONO_VERSION="10.4.1"
MONO_NAME="wine-mono-$MONO_VERSION-x86.tar.xz"
MONO_URL="https://dl.winehq.org/wine/wine-mono/$MONO_VERSION/$MONO_NAME"
MONO_SHA="a16606ef0724202e6a6848ece6e0cbba64d11e2f11aefe744af1d93c6d9f99bb"
GECKO_VERSION="2.47.4"
GECKO_URL="https://dl.winehq.org/wine/wine-gecko/$GECKO_VERSION"
GECKO_X86_SHA="2cfc8d5c948602e21eff8a78613e1826f2d033df9672cace87fed56e8310afb6"
GECKO_X64_SHA="fd88fc7e537d058d7a8abf0c1ebc90c574892a466de86706a26d254710a82814"
RUNTIME_NAME="wine-staging-11.18-osx64.tar.xz"
RUNTIME_URL="https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.18/$RUNTIME_NAME"
RUNTIME_SHA="b63704b91af269bc026a87f12bd297c4a50caaf570c322e600b6621ef918f127"
# ExePort's oldest macOS (minMacOS in the runtime manifest).
MIN_MACOS="15.0"

command -v x86_64-w64-mingw32-gcc >/dev/null || { echo "need mingw-w64 (brew install mingw-w64)" >&2; exit 1; }
BREW="$(brew --prefix)"
[ -x "$BREW/opt/bison/bin/bison" ] || { echo "need bison >= 3 (brew install bison)" >&2; exit 1; }
arch -x86_64 /usr/bin/true 2>/dev/null || { echo "need Rosetta (softwareupdate --install-rosetta)" >&2; exit 1; }

fetch() { # name url sha
  local f="$CACHE/$1"
  if [ ! -f "$f" ]; then curl -fL --retry 3 -sS -o "$f.part" "$2"; mv "$f.part" "$f"; fi
  [ "$(shasum -a 256 "$f" | cut -d' ' -f1)" = "$3" ] || { echo "checksum mismatch: $1 (moved aside)" >&2; mv "$f" "$f.bad"; exit 1; }
}
fetch "$WINE_NAME" "$WINE_URL" "$WINE_SHA"
fetch "$MONO_NAME" "$MONO_URL" "$MONO_SHA"
fetch "wine-gecko-$GECKO_VERSION-x86.tar.xz" "$GECKO_URL/wine-gecko-$GECKO_VERSION-x86.tar.xz" "$GECKO_X86_SHA"
fetch "wine-gecko-$GECKO_VERSION-x86_64.tar.xz" "$GECKO_URL/wine-gecko-$GECKO_VERSION-x86_64.tar.xz" "$GECKO_X64_SHA"
fetch "$RUNTIME_NAME" "$RUNTIME_URL" "$RUNTIME_SHA"

# --- 1. Runtime libraries (x86_64) from the pinned Gcenx build -----------------------------------------
rm -rf "$WORK/runtime" && mkdir -p "$WORK/runtime"
tar -xJf "$CACHE/$RUNTIME_NAME" -C "$WORK/runtime"
RLIB="$(ls -d "$WORK"/runtime/*.app/Contents/Resources/wine/lib)"
# Link-time copies carry `@rpath/libX.N.dylib` ids so configure records versioned sonames.
DEPS="$WORK/deps"; rm -rf "$DEPS" && mkdir -p "$DEPS/lib" "$DEPS/include"
for pair in libgnutls:libgnutls.30 libfreetype:libfreetype.6 libSDL2:libSDL2-2.0.0 libvulkan:libvulkan.1 libMoltenVK:libMoltenVK; do
  cp "$RLIB/${pair#*:}.dylib" "$DEPS/lib/${pair%%:*}.dylib"; chmod u+w "$DEPS/lib/${pair%%:*}.dylib"
  install_name_tool -id "@rpath/${pair#*:}.dylib" "$DEPS/lib/${pair%%:*}.dylib" 2>/dev/null
done
ln -s "$BREW/opt/freetype/include/freetype2" "$DEPS/include/freetype2"
ln -s "$BREW/opt/gnutls/include/gnutls" "$DEPS/include/gnutls"
ln -s "$BREW/include/SDL2" "$DEPS/include/SDL2"

# --- 2. Wine -------------------------------------------------------------------------------------------
SRC="$WORK/wine-$WINE_VERSION"
CLEAN_ENV=(/usr/bin/env -i HOME="$HOME" PATH="$BREW/opt/bison/bin:$BREW/bin:/usr/bin:/bin:/usr/sbin:/sbin" MACOSX_DEPLOYMENT_TARGET="$MIN_MACOS")
if [ "${RESUME:-0}" != 1 ] || [ ! -f "$WORK/build/Makefile" ]; then
  rm -rf "$SRC" "$WORK/build"
  tar -xJf "$CACHE/$WINE_NAME" -C "$WORK"
  grep -q "define MONO_VERSION \"$MONO_VERSION\"" "$SRC/dlls/appwiz.cpl/addons.c" \
    && grep -q "define GECKO_VERSION \"$GECKO_VERSION\"" "$SRC/dlls/appwiz.cpl/addons.c" \
    || { echo "Wine $WINE_VERSION wants other Mono/Gecko versions (dlls/appwiz.cpl/addons.c)" >&2; exit 1; }
  for p in patches/*.patch; do patch -d "$SRC" -p1 --forward --quiet < "$p" || { echo "patch failed: $p" >&2; exit 1; }; done
  mkdir -p "$WORK/build"
  # No -g: debug info would double the size of the PE DLLs and nobody here reads it.
  ( cd "$WORK/build" && "${CLEAN_ENV[@]}" \
      CC="clang -arch x86_64" CXX="clang++ -arch x86_64" OBJC="clang -arch x86_64" \
      CFLAGS="-O2" CROSSCFLAGS="-O2" \
      FREETYPE_CFLAGS="-I$DEPS/include/freetype2" FREETYPE_LIBS="-L$DEPS/lib -lfreetype" \
      GNUTLS_CFLAGS="-I$DEPS/include" GNUTLS_LIBS="-L$DEPS/lib -lgnutls" \
      SDL2_CFLAGS="-I$DEPS/include/SDL2 -D_THREAD_SAFE" SDL2_LIBS="-L$DEPS/lib -lSDL2" \
      LDFLAGS="-L$DEPS/lib -Wl,-rpath,@loader_path/../../" \
      ac_cv_func_pipe2=no \
      "$SRC/configure" --build=x86_64-apple-darwin --host=x86_64-apple-darwin --prefix="$WORK/stage" \
        --enable-archs=i386,x86_64 --disable-tests --disable-win16 \
        --with-mingw --with-freetype --with-gnutls --with-sdl --with-vulkan --with-coreaudio --with-opencl --with-unwind \
        --without-x --without-wayland --without-alsa --without-oss --without-udev --without-v4l2 --without-capi \
        --without-inotify --without-pulse --without-dbus --without-netapi --without-krb5 --without-gssapi \
        --without-fontconfig --without-sane --without-gphoto --without-gstreamer --without-ffmpeg --without-usb \
        > configure.out 2>&1 ) || { echo "configure failed; see $WORK/build/configure.out" >&2; exit 1; }
fi
# Build-time tools (sfnt2fon links FreeType) get the same `@loader_path/../../` rpath as Wine's modules;
# from build/tools/<tool>/ that is the build root, so the runtime libraries go there too.
cp -a "$RLIB"/*.dylib "$WORK/build/"
rm -rf "$WORK/stage"
( cd "$WORK/build" && "${CLEAN_ENV[@]}" make -j"${JOBS:-$(sysctl -n hw.ncpu)}" > make.out 2>&1 \
  && "${CLEAN_ENV[@]}" make install > install.out 2>&1 ) \
  || { echo "Wine build failed; see $WORK/build/make.out and install.out" >&2; exit 1; }

# The SDK can be newer than the oldest macOS ExePort supports. Functions only a newer macOS has are weak imports,
# NULL on older systems: with the macOS 27 SDK configure finds pipe2, and Wine then crashes at start on macOS 26
# (ntdll server_pipe -> pipe2 -> address 0; MaPC engine 2.0.1). Hence ac_cv_func_pipe2=no above, and this check:
# weak imports in Wine's modules must be ones its source guards with an availability check.
GUARDED_WEAK='^(ulock_wait2|availability_version_check|os_sync_wait_on_address|os_sync_wait_on_address_with_timeout|os_sync_wake_by_address_any|clCreateImage2D|clCreateImage3D|clEnqueueBarrier|clEnqueueMarker|clEnqueueWaitForEvents|clUnloadCompiler)$'
for bin in "$WORK"/stage/bin/wine "$WORK"/stage/bin/wineserver "$WORK"/stage/lib/wine/x86_64-unix/*.so; do
  [ -L "$bin" ] && continue
  unguarded="$(dyld_info -imports "$bin" 2>/dev/null | grep weak-import | grep -oE '_[A-Za-z0-9_]+' | sed 's/^_*//' \
    | grep -vE "$GUARDED_WEAK" || true)"
  [ -z "$unguarded" ] || { echo "$(basename "$bin") weak-imports $unguarded: check it is guarded, or pin it off in configure" >&2; exit 1; }
done
nm -gU "$WORK/stage/lib/wine/x86_64-unix/winemac.so" | grep -q " _macdrv_functions$" \
  || { echo "winemac.so doesn't export macdrv_functions; DXMT can't create its Metal view" >&2; exit 1; }

# --- 3. Assemble ---------------------------------------------------------------------------------------
PKG="$WORK/package"; rm -rf "$PKG" && mkdir -p "$PKG"
cp -R "$WORK/stage" "$PKG/wine"
W="$PKG/wine"
rm -rf "$W/include" "$W/share/man" "$W/share/applications"      # build-time only
find "$W/lib/wine" -name "*.a" -delete
cp -a "$RLIB"/*.dylib "$W/lib/"
# Wine dlopens these by leaf name, which dyld resolves through the calling module's rpaths. Wine adds
# `@loader_path/`; LDFLAGS above adds `@loader_path/../../` (= wine/lib). A missing rpath would only show up later
# as broken fonts, TLS or Vulkan, so check it now.
for so in ntdll win32u bcrypt winevulkan; do
  otool -l "$W/lib/wine/x86_64-unix/$so.so" | grep -q "path @loader_path/../../ " || { echo "no rpath in $so.so" >&2; exit 1; }
done
for lib in libfreetype.6.dylib libgnutls.30.dylib libSDL2-2.0.0.dylib libvulkan.1.dylib libMoltenVK.dylib; do
  [ -f "$W/lib/$lib" ] || { echo "runtime library missing: $lib" >&2; exit 1; }
done
# No library reference or rpath may point back into this build machine's folders. (Wine's loader keeps the
# configure prefix as text, only to compute relative paths; that is harmless.)
for bin in "$W"/bin/wine "$W"/bin/wineserver "$W"/lib/wine/x86_64-unix/*; do
  [ -L "$bin" ] && continue
  if { otool -L "$bin" | tail -n +2; otool -l "$bin" | grep -A2 LC_RPATH || true; } | grep -qF "$WORK"; then
    echo "build path leaked into $bin" >&2; exit 1
  fi
done

# Wine Mono and Gecko where Wine looks for them first (share/wine/{mono,gecko}), so a new bottle installs them
# without a download prompt.
mkdir -p "$W/share/wine/mono" "$W/share/wine/gecko"
tar -xJf "$CACHE/$MONO_NAME" -C "$W/share/wine/mono"
tar -xJf "$CACHE/wine-gecko-$GECKO_VERSION-x86.tar.xz" -C "$W/share/wine/gecko"
tar -xJf "$CACHE/wine-gecko-$GECKO_VERSION-x86_64.tar.xz" -C "$W/share/wine/gecko"

# Licenses, and how this build was made: the LGPL's "scripts used to control compilation" ship with the binaries.
L="$W/licenses"; mkdir -p "$L/wine-libs" "$L/runtime-libs" "$L/build"
cp "$SRC/COPYING.LIB" "$L/Wine-COPYING.LIB.txt"; cp "$SRC/LICENSE" "$L/Wine-LICENSE.txt"
# Libraries Wine builds into its own DLLs (libs/ in Wine's source).
for f in "$SRC"/libs/*/{COPYING,LICENSE,COPYRIGHT}*; do
  [ -f "$f" ] && cp "$f" "$L/wine-libs/$(basename "$(dirname "$f")")-$(basename "$f").txt"
done
cp licenses/* "$L/runtime-libs/"
cp build.sh "$L/build/"; cp -R patches "$L/build/"
cat > "$L/NOTICE.txt" <<TXT
Wine for ExePort, Wine $WINE_VERSION build $REVISION.

Wine $WINE_VERSION (LGPL-2.1-or-later): $WINE_URL (sha256 $WINE_SHA),
  with the patches in build/patches applied, built by build/build.sh. Wine's own licenses: Wine-*.txt;
  libraries built into Wine's DLLs: wine-libs/.
Wine Mono $MONO_VERSION (share/wine/mono; MIT, LGPL, GPL with exceptions, MS-PL and others, listed in its source):
  $MONO_URL; source: https://dl.winehq.org/wine/wine-mono/$MONO_VERSION/wine-mono-$MONO_VERSION-src.tar.xz
Wine Gecko $GECKO_VERSION (share/wine/gecko; MPL-2.0): $GECKO_URL/
  source: $GECKO_URL/wine-gecko-$GECKO_VERSION-src.tar.xz
Runtime libraries in lib/ (FreeType, GnuTLS and its dependencies, SDL2, MoltenVK, the Vulkan loader and others):
  unmodified from Gcenx's Wine 11.18 build, $RUNTIME_URL (sha256 $RUNTIME_SHA), built with MacPorts.
  Their licenses: runtime-libs/.
TXT
cat > "$W/BUILD.json" <<JSON
{ "wine": "$WINE_VERSION", "revision": $REVISION, "mono": "$MONO_VERSION", "gecko": "$GECKO_VERSION", "minMacOS": "$MIN_MACOS" }
JSON

# --- 4. Package ----------------------------------------------------------------------------------------
ARCHIVE="$OUT/exeport-wine-$WINE_VERSION-$REVISION.tar.xz"
rm -f "$ARCHIVE"
XZ_OPT="-T0 -9" tar -cJf "$ARCHIVE" -C "$PKG" wine
SHA="$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"; SIZE="$(stat -f%z "$ARCHIVE")"
echo "archive: $ARCHIVE ($((SIZE / 1048576)) MB)"
echo "sha256:  $SHA"
echo "size:    $SIZE"
cat > "$OUT/exeport-wine-$WINE_VERSION-$REVISION.component.json" <<JSON
{
  "kind": "wine",
  "version": "$WINE_VERSION (ExePort build $REVISION)",
  "url": "${BASE_URL:-file://$OUT}/exeport-wine-$WINE_VERSION-$REVISION.tar.xz",
  "sha256": "$SHA",
  "size": $SIZE,
  "license": "LGPL-2.1-or-later",
  "from": "wine",
  "into": "wine"
}
JSON
echo "manifest component: $OUT/exeport-wine-$WINE_VERSION-$REVISION.component.json"
