# EscApp-Runtime

Builds the Wine that [EscApp](https://github.com/Zig1375) uses to run Windows games on Apple Silicon Macs, and
publishes it on this repository's [Releases](../../releases). EscApp's runtime manifest pins each release archive by
URL, SHA-256 and size, so the app only installs files built here.

## Wine

`wine/build.sh` builds stock [Wine](https://www.winehq.org) 11.0 for x86_64 (run through Rosetta) with the new
WoW64, so 32-bit games need no 32-bit macOS code, and adds Wine Mono 10.4.1 and Wine Gecko 2.47.4 (the versions
Wine 11.0 asks for). The archive `escapp-wine-<wine>-<revision>.tar.xz` holds one folder, `wine/`, laid out as Wine
installs itself (`bin/`, `lib/`, `share/`), with every license and this build script in `wine/licenses/`.

One patch is applied, `wine/patches/0001`: it exports winemac's `macdrv_functions` table, which
[DXMT](https://github.com/3Shain/dxmt) (Direct3D 10/11 on Metal) uses to create its Metal view. Without it DXMT
fails with "Failed to create metal view".

Every download is pinned by SHA-256. Wine, Mono and Gecko come from WineHQ; the x86_64 libraries Wine loads
(FreeType, GnuTLS, SDL2 and their dependencies) come unmodified from
[Gcenx's Wine 11.18 build](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.18), and MoltenVK 1.4.2 from
[Khronos' release](https://github.com/KhronosGroup/MoltenVK/releases/tag/v1.4.2).

Build locally (Xcode, Rosetta, and `brew install bison pkgconf freetype gnutls sdl2 mingw-w64`):

```bash
wine/build.sh
```

Release: Actions → Wine → Run workflow, with the next revision number. The release notes and the job summary give
the SHA-256, the size and the manifest entry.

## License

The build scripts are under the Apache License 2.0 (`LICENSE`). The patches change Wine and are under Wine's
license, the GNU LGPL 2.1 or later. Each built component keeps its own license; see `wine/licenses/` in a release.
