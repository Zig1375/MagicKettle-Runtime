Wine 11.20 for EscApp, fifteenth build: 32-bit Direct3D 11 games no longer run out of memory. This is the only
build of Wine 11.20 still published, so below are also all the changes it carries compared to stock Wine 11.20.

## New in this build

- **32-bit Direct3D 11 games on DXVK no longer crash after a few minutes.** A 32-bit program can only address
  4 GB, so Wine gives each graphics buffer the game can write to pages of its own below that line. When the game
  freed a buffer, Wine forgot to give those pages back, and a game that loads and drops pictures as it goes used up
  all 4 GB: the Daughter for Dessert chapters (GameMaker) crashed every ten to fifteen scenes, "out of memory" in
  the log, although the game itself needs far less. Freed buffers now give their memory back. A test that makes and
  frees a 64 MB buffer over and over failed at round 61 before and passes 400 rounds now.

## Everything this build carries compared to stock Wine 11.20

### Graphics

- **DXMT works.** Wine's Mac driver exports the table DXMT (Direct3D 10/11 on Metal) uses to create its Metal view;
  without it DXMT failed with "Failed to create metal view".
- **DirectX 12 games run on Apple's D3DMetal** (build 10). EscApp doesn't ship D3DMetal: the player downloads Apple's
  "Evaluation environment for Windows games" and adds it in EscApp's DirectX 12 settings. Wine exports the ntdll
  function D3DMetal's DLLs import, and with `WINEMACSHAREDTSD=1`, which EscApp sets only for games on D3DMetal,
  D3DMetal's macOS library can be called from Windows threads.
- **Fixed-size game windows can be stretched** by dragging their corner (build 6, with `StretchWindows` next to
  `EmulateModeset`). The game keeps drawing at its own size, Wine scales the picture and the mouse, the window keeps
  the game's proportions and its size is remembered. When the game changes resolution the picture is fitted again.
- **Stretched and big windows move between displays** (build 7): a window taller than a small screen, or a stretched
  window in Retina mode, no longer jumps back when dragged to another display.
- **Mac driver fixes** (build 6): Direct3D 9 games in an emulated full screen no longer show a white window, OpenGL
  games are no longer drawn at a stale size or only by their corner, a Direct3D 9 hang on resize is gone, the bars
  beside an emulated full screen are black on both sides in Retina mode, and DXMT's picture follows its window.
- **No flicker in NW.js and Electron games** (build 8): the last frame stays in the buffer the game draws into next.
- **32-bit Direct3D 11 games no longer run out of memory** (this build).

### Speed and stability

- **osync** (builds 3 to 5, `docs/osync.md`): events, semaphores and mutexes are waited on and signalled inside the
  game's process, 9 to 26 times faster than through wineserver on our benchmarks (event round trip about 1.2 us
  instead of 26 us). Off unless `WINEOSYNC=1` is set for wineserver. Handles stay fast after a killed thread, a
  mutex can't starve a waiter, and suspended or killed threads can no longer hang the whole prefix (Steam hung at
  start before build 5).
- **32-bit games under Rosetta 2** no longer crash at random in wow64cpu.dll (build 3): it switches between 32- and
  64-bit code with far returns instead of far jumps.
- **Games no longer hang on their first game controller check** (build 11): Among Us froze on a black window right
  after its intro.
- **No crash when the Mac is slow to start a game** (build 12): the Cocoa start-up handshake no longer lives on a
  stack that could be freed, and the wait for the main thread is a minute instead of five seconds.
- **Steam comes up reliably** (build 13): a thread is no longer paused while it loads a library, which could hang
  Steam's browser at start, and a dying OpenGL context is no longer handed to the main thread, which crashed Steam
  and games in `objc_release`.
- **Crashes on macOS threads say where and always end the process** (builds 12 and 14): the log lists the native
  stack, first as bare addresses, then with libraries and function names.

### Stores and programs

- **The Epic Games Launcher installs games** (builds 7 and 9): Wine reports folder changes through FSEvents
  (ReadDirectoryChangesW, FindFirstChangeNotification), and keeps the permissions a program gives a file or folder,
  so the launcher no longer stops with DP-06 or DP-07.
- **Epic keeps the player signed in** (build 7): named CNG keys are kept in the bottle's registry across runs.

## What to watch for

- 32-bit games on DXVK (most 32-bit Direct3D 11 games) take the new memory path: watch for any new graphics glitch
  or crash in them. 64-bit games don't take this path.
- A game that resizes its window without telling Direct3D 11 (no `ResizeBuffers`) shows a white window with DXMT.
- A stretched window's size belongs to the display it was stretched on; on another display the game is shown at
  its own size until the player stretches it there.
- macOS reports folder changes a few milliseconds late, where Windows reports them at once.
- Named CNG keys are kept in the bottle's registry (`HKCU\Software\Wine\NCrypt\Keys`) as plain key data; anyone who
  can read the bottle can read them. RSA and ECDSA P-256 keys only.
- Permissions are kept in an extended attribute (`user.wine.sd`) and dropped when the Mac permissions change
  outside Wine. Files created inside a folder don't inherit its permissions as on Windows.
- In D3DMetal's mode, Windows code reads only the TEB itself and its TLS array through the thread register; code
  that reads other TEB fields that way directly gets wrong values.
- Every OpenGL frame on the emulated display path is copied once more inside the graphics card.
- A process whose Mac side doesn't start waits up to a minute before it goes on without windows.
- Pausing a thread waits until any library load it is doing finishes, a few milliseconds at most.
