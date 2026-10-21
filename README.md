# Glance Switch

A tiny macOS **menu‑bar app** that uses your camera to see **which display you're
facing** and moves keyboard focus there — so your keystrokes land on the screen
you're looking at, before you start typing.

Built from scratch in
Swift using `AVFoundation` (camera), `Vision` (head‑pose), and the macOS
`Accessibility` API (focus control).

- Runs in the **background** as a menu‑bar agent (no Dock icon).
- **Toggle on/off** from the menu bar (the eye icon).
- Switches focus to the frontmost window on whichever display you turn toward.
- A short **dwell** delay prevents focus from flickering as you glance around.

> **How it works:** The camera estimates how far your head is turned left/right.
> That angle is mapped across your displays (sorted left → right). When you hold
> your gaze on another display briefly, the frontmost window there is raised and
> its app is activated, giving it keyboard focus.

---

## Requirements

- macOS 13 or newer (built/tested on macOS 26/27, Apple Silicon).
- Apple **Command Line Tools** (`xcode-select --install`) — full Xcode is *not*
  required.
- A built‑in or external camera.
- **Two or more displays** (with a single display there's nothing to switch to).

## Build & run

```bash
cd GlanceSwitch
./build_app.sh        # compiles + bundles + ad-hoc signs GlanceSwitch.app
open GlanceSwitch.app  # launches it (look for the eye icon in the menu bar)
```

### First launch — grant two permissions

On first run macOS will ask for permissions. Both are required:

1. **Camera** — click *Allow* when prompted (needed to see which way you face).
2. **Accessibility** — needed to move focus between other apps' windows.
   - Open the menu‑bar menu → **“Grant Accessibility access…”**.
   - In **System Settings → Privacy & Security → Accessibility**, enable
     **GlanceSwitch** (toggle it on).

After granting Accessibility, toggle **“Enable focus follow”** off and on once so
the app picks up the new permission.

> If permissions misbehave after rebuilding, remove the old entries in
> System Settings (Camera & Accessibility), then re‑add the freshly built app.

## Using it

Click the **eye icon** in the menu bar:

| Menu item | What it does |
|---|---|
| **Enable focus follow** | Start/stop gaze tracking (the main on/off toggle). |
| **Camera ▸** | Pick which camera to use — **System default** or any built-in / external / Continuity camera. Your choice is remembered and applied live. |
| **Sensitivity ▸** | How far you must turn your head before focus moves: **High** (small turns), **Medium**, or **Low** (large turns). Pick **Low** if a big primary screen switches when you move within it. |
| **Invert left/right** | Flip the mapping if focus moves the opposite way to your head. |
| **Grant Accessibility access…** | Prompt + open the Accessibility settings pane. |
| **Camera privacy settings…** | Open the Camera settings pane. |
| **Quit Glance Switch** | Exit the app. |

The icon shows **`eye`** when active and **`eye.slash`** when paused.

> **Using an external webcam?** By default macOS picks the built-in camera. Open
> the menu → **Camera ▸** and select your external camera (e.g. *Brio 100*). The
> session switches to it immediately.

### Does it pick the right screen? (direction check)

- **Screen order** follows your **System Settings → Displays** arrangement exactly:
  focus maps across your screens left → right by their physical position, so a
  left head turn targets your left-most display and a right turn your right-most.
- **Turn direction** depends on your camera. The app pins the camera to a
  mirrored (selfie) view so this is consistent, but if you find focus goes the
  *opposite* way to your head, just toggle **Invert left/right** in the menu — the
  setting is remembered.
- To confirm quickly, run in debug mode and watch the arrows as you turn your head:

  ```bash
  GLANCE_DEBUG=1 ./GlanceSwitch.app/Contents/MacOS/GlanceSwitch
  ```
  ```
  head LEFT   yaw=-0.42 rad  -> display #0 (LEFT-most of 3)  [focused #1]
  head RIGHT  yaw=+0.45 rad  -> display #2 (RIGHT-most of 3) [focused #1]
  ```
  If "head LEFT" ever points at the RIGHT-most display, enable **Invert left/right**.

## Tuning

Behaviour is controlled by a few values in `Preferences.swift`:

- `dwellSeconds` (default `0.45`) — how long you must hold your gaze before focus
  moves. Raise it if focus switches too eagerly; lower it for snappier switching.
- `maxYaw` (default `0.85` rad) — how far you turn your head to reach the
  outermost display. **Larger = you must turn more** before an outer screen is
  selected (also set via the **Sensitivity** menu).
- `hysteresis` (default `0.10` rad ≈ 6°) — extra angle you must turn *past* a
  screen boundary before focus switches. This is what stops small head movements
  within one screen from flipping the selection. Increase it if focus still
  feels twitchy near the edges.
- `pitchLimit` (default `0.30` rad ≈ 17°) — if your head tilts up/down beyond
  this (e.g. glancing at the keyboard), the current screen is **held** and focus
  won't drift to the middle. Lower it if looking down still switches screens.
- `invert` — also toggleable from the menu.

Edit, then rebuild with `./build_app.sh`.

## Run automatically in the background (login item)

To have it start quietly every time you log in:

**System Settings → General → Login Items → “Open at Login”** → **+** → select
`GlanceSwitch.app`.

(Because `LSUIElement` is set in `Info.plist`, it launches straight to the menu
bar with no Dock icon or window.)

## Project layout

```
GlanceSwitch/
├── Package.swift                 # Swift Package manifest (SwiftPM, no Xcode)
├── Info.plist                    # LSUIElement + camera usage string
├── build_app.sh                  # build → bundle → ad-hoc sign
└── Sources/GlanceSwitch/
    ├── main.swift                # NSApplication bootstrap (accessory app)
    ├── AppDelegate.swift
    ├── MenuBarController.swift    # menu bar UI + dwell/debounce logic
    ├── GazeDetector.swift        # AVFoundation camera + Vision head-yaw
    ├── FocusController.swift      # Accessibility API: raise/focus a window
    ├── ScreenMapper.swift        # head-yaw → target display
    └── Preferences.swift         # persisted settings (UserDefaults)
```

## Limitations & notes

- This version switches focus **between displays** (which screen you face). It
  does not yet distinguish split panes *within* one screen.
- Head‑yaw is a robust, lightweight proxy for gaze; true eye‑tracking from a
  webcam is far less reliable, so this uses head orientation.
- Camera frames are processed **entirely on‑device**; nothing leaves your Mac.
- The app is **ad‑hoc signed** (local use). Distributing it to others would
  require a Developer ID signature + notarization.
```

## Contributing

Contributions are welcome! Feel free to open an issue to report a bug or suggest
a feature, or submit a pull request. For larger changes, please open an issue
first to discuss what you'd like to change.

## Acknowledgements

Inspired by [Glance Switch](https://glanceswitch.com/). This is an independent,
open-source take on the same idea, built from scratch and made freely available
to everyone.

## License

Released under the [MIT License](LICENSE) — free to use, modify, and distribute.
Copyright © 2026 Sampreeth Amith Kumar.
