# Focus Swap Monitor

A KWin 6 script for theia's two-output setup:

- local interactive display: `eDP-1`
- VNC/krfb display: `Virtual-Chromebook`

Whenever a fullscreen or maximized normal application window becomes active,
it moves to `eDP-1` and the previously active eligible application window moves
to `Virtual-Chromebook`. Panels, dialogs, menus, minimized windows, floating
windows, and **Keep Above Others** windows are ignored. This leaves those small
or pinned windows free to coexist on either display.

The installed package is enabled in **System Settings → Window Management →
KWin Scripts**. Disable `Focus Swap Monitor` there to turn the behavior off.

The display names are constants at the top of `contents/code/main.js`; change
them if the virtual output is recreated with a different name.
