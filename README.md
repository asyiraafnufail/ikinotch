# IkiNotch

A lightweight, native macOS virtual notch app for non-notch Macs built with **Swift, AppKit, and SwiftUI** — engineered for **near-zero idle consumption** (0% background polling when collapsed).

## Key Features

- **Notch & Pill (Dynamic Island) Styles** — switch live between a menu-bar flush **Notch** (concave ears) and a floating **Pill** capsule; auto-hides in **Fullscreen Spaces**.
- **3 Zero-Timer Idle Modes**:
  - **Smart Status** — automatically displays Active Timer → Now Playing (Browser YouTube, Spotify, Apple Music, VLC) → Calendar Up Next → Connected Wi-Fi (SSID) → `Offline` + proportional real-level Battery.
  - **Custom** — custom text (+ optional battery).
  - **Pure Black** — solid black MacBook-style notch.
- **Event-Driven Indicators** — subtle **Caps Lock (`⇪`)** and **Keep Awake (`☕`)** icons appear automatically when active.
- **Expanded Panel (`Home` · `Media` · `Tray` · `Notes` · `Timer` · `Stats` · `Tools`)**:
  - **Home:** Combined dashboard (Mini Media, Calendar & Tray summary, plus 4 Quick Controls: **Wi-Fi**, **Bluetooth**, **Dark/Light Theme**, **Mute**).
  - **Media:** Full Now Playing card with cached 128px album art / YouTube thumbnail & system-wide `MediaRemote` controls.
  - **Tray:** File Drop Shelf (zero-copy drag-and-drop holding tray + AirDrop).
  - **Notes:** Auto-saving quick scratchpad with one-click Copy & Clear.
  - **Timer:** Multi-mode **Timer** (`1m/5m/10m/25m/45m` + `±1m`), **Pomodoro** (*Focus / Break / Long Break* cycles), and **Stopwatch** (*Mark Lap*) with live idle notch display.
  - **Stats:** Live-while-visible CPU %, RAM, Disk Free, Network Down/Up speed, Thermal state, clickable Local IP, and Uptime (0% CPU when closed).
  - **Tools:** Screenshot (Clipboard), Color Picker (`#HEX`), Terminal, Downloads, Activity Monitor, and Sleep Screen.
  - **Keep Awake (`☕`):** one-click sleep prevention via `IOPMAssertion`.
- **Customizable & Symmetrical:** choose *Trigger Mode* (`Expand on Hover` / `Click Only`), *Animation Style* (`Snappy`, `Smooth`, `Bouncy`, `Instant`), *Hover Delay* (`50 / 100 / 150 / 200 ms`), notch size, and *Launch at Login* (`SMAppService`).

See the full feature breakdown in [FEATURES.md](FEATURES.md).

## Zero-Idle Architecture

- **0 polling timers when collapsed** — backed by native OS events (`NSTrackingArea`, `IOPSNotificationCreateRunLoopSource`, `MediaRemote`, `CWEventDelegate`, `EKEventStoreChanged`, `NSEvent.flagsChanged`).
- **Full App Nap support** & dynamic `NSPanel` frame shrinking when collapsed.
- **Zero third-party dependencies** — compact ~2.5 MB `.app` bundle.

## Build & Run

Requirements: **macOS 13.0+** and **Xcode 15+ / Swift 5.9+**.

```bash
# Run unit tests
swift test

# Build release binary and package build/IkiNotch.app
./scripts/build_app.sh

# Launch the app
open build/IkiNotch.app
```

For daily use and **Launch at Login**, move `build/IkiNotch.app` into `/Applications`.
