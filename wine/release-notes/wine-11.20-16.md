Wine 11.20 for Magic Kettle, sixteenth build.

- **An opt-in software drawing path supports child windows hosted by another process.** WebView2 can draw a
  complete page while its host, such as Gale, shows a white window: its drawing process had no access to the
  host's GDI surface. With `WINE_CROSS_PROCESS_GDI=1`, the processes share a section-backed pixel buffer, and
  completed drawing operations notify the owning window to present the updated pixels immediately. This also
  avoids a first-frame-only result where changing focus was needed to see a click's effect. The path is off by
  default and does not enable WebView2 automatically.

  WebView2 157 also needs a route around its DirectComposition output. The verified diagnostic configuration
  sets `HKCU\Software\Wine\AppDefaults\msedgewebview2.exe\Version` to `win7` and supplies WebView2 with
  `--disable-gpu --disable-direct-composition --disable-features=RemoveRedirectionBitmap`. The host remains on
  Windows 10. This configuration has not been integrated into Magic Kettle's normal launch preparation yet.

  Gale 1.23.3 was checked in an isolated prefix: the player confirmed immediate clicks, scrolling, menus and
  hover feedback. The GDI probes cover 32- and 64-bit hosts, mixed-bitness children, `SetParent`, and resizing.
  D3D9 probes passed in both bitnesses with the path on and off; 64-bit GDI/D3D9 scripted resizing and
  emulated fullscreen completed in both modes. The default-path D3D9 stretch run printed OK but returned
  exit 1 once; an identical repeat returned 0. That shutdown exit remains unexplained. Store clients,
  DXVK/DXMT games and Retina/display changes still need validation with this experimental path enabled. Do not add browser logging or remote-debugging switches to the release workaround: in the diagnostic
  runs their console stole focus and Wry treated `MoveFocus` returning `E_ACCESSDENIED` as fatal.
