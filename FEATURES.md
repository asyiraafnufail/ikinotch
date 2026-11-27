# IkiNotch Features

Complete feature overview of **IkiNotch** — a lightweight, native macOS virtual notch utility built with **Swift, AppKit, and SwiftUI**, engineered for **near-zero idle consumption** (0% background polling when collapsed).

---

## 1. Virtual Notch & Display Behavior

| Feature | Description |
|---|---|
| **Notch & Pill (Dynamic Island) Styles** | Switch seamlessly in real time between **Notch** (concave top ears flush with the top bezel) and **Pill (Dynamic Island)** (floating rounded capsule with soft shadow). |
| **Auto Menu Bar Height** | In the idle (*collapsed*) state, the notch height automatically matches the exact macOS menu bar boundary (`Compact`, `Standard`, `Wide`), with a `Custom` preset for manual width & height. |
| **Auto-Hide in Fullscreen** | Automatically hides when entering Fullscreen Spaces or fullscreen video via on-screen `CGWindowList` detection (menu bar layer & normal fullscreen windows), with 0% polling. |
| **Non-Activating Panel** | Hovering and clicking controls inside the notch never steals focus from your active app (keyboard focus is only enabled while typing in the `Notes` tab). |
| **Menu Bar Utility (`LSUIElement`)** | Runs quietly with no Dock icon or `Cmd+Tab` clutter, providing quick Menu Bar actions (*Show/Hide*, *Expand*, *Center*, *Settings*, *Quit*). |

---

## 2. Idle Mode (Collapsed)

All idle modes run with **zero active timers**:

- **Smart Status (Default)** — automatic priority display on the left:
  1. **Active Timer Countdown** (`⏱ 24:59`) while a timer is running.
  2. **Now Playing** (track/video title from Browser YouTube, Spotify, Apple Music, VLC).
  3. **Calendar Up Next** (upcoming event when Calendar is connected).
  4. **Connected Wi-Fi Name (SSID)**.
  5. **`Offline`** (clean text without icon when Wi-Fi is disconnected).
- **Custom** — displays your own custom text (e.g., `Focus`, name, or emoji), with an option to show alongside the battery or centered by itself.
- **Pure Black** — clean solid black silhouette resembling a physical MacBook notch.

### Event-Driven Idle Indicators
- **Real-Level Proportional Battery** — custom battery icon that fills proportionally from 0–100% matching the actual battery level, with status colors (white normal, green + `⚡` bolt while charging, amber ≤ 25%, red ≤ 15%).
- **Caps Lock (`⇪`)** — subtle amber icon automatically appears alongside idle content when Caps Lock is on (toggleable in Settings).
- **Keep Awake (`☕`)** — subtle amber coffee icon automatically appears when *Keep Awake* is active.

---

## 3. Expanded Panel (7 Tabs)

The top header stays centered and locked at a fixed `28 pt` height with zero layout shift when switching tabs: **Clock & Date · 7 Fixed-Size Icon Tabs · Battery (+ time remaining) · `☕` Keep Awake · `⚙` Settings**.

| Tab | Icon | Features |
|---|---|---|
| **Home** | 🏠 | **Combined Dashboard:** Mini Media strip (artwork + Play/Pause & Next), Calendar & Tray summary, plus **4 one-click Quick Controls** (**Wi-Fi**, **Bluetooth**, **Dark/Light Theme**, **Sound/Mute**). |
| **Media** | 🎵 | **Full Now Playing:** `72×72 pt` cached & downsampled (128px) album art / YouTube thumbnail, centered track metadata, and system-wide **Prev / Play-Pause / Next** controls via `MediaRemote` for Brave, Chrome, Safari, Spotify, Apple Music, and VLC. |
| **Tray** | 📥 | **File Drop Shelf:** drag-and-drop files onto the notch (automatically expands to Tray), holds file URL references with zero disk copying, drag out to any app, click to *Reveal in Finder*, and one-click **AirDrop**. |
| **Notes** | 📝 | **Quick Scratchpad:** auto-saving quick notes stored in `UserDefaults`, automatically enables keyboard input when selected, plus one-click **Copy** & **Clear**. |
| **Timer** | ⏱ | **Multi-Mode Timer:** switch between **Timer** (`1m · 5m · 10m · 25m · 45m` + `-1m`/`+1m` adjust), **Pomodoro** (auto-cycling *Focus 25m → Break 5m → Long Break 15m* with session counter), and **Stopwatch** (count-up with *Mark Lap*). Plays a gentle `Glass` sound on completion, runs with **0% CPU when inactive**, and shows live time in the idle notch while running. |
| **Stats** | 📊 | **Live System Monitor (Visible-Only):** displays **CPU %**, **RAM**, **Disk Free**, **Network Speed (↓ Down / ↑ Up)**, **Thermal State**, **Local IP (click to copy)**, and **System Uptime** — sampled natively via Mach/Darwin APIs every 2s *only while the Stats tab is open* (**0% idle CPU** when closed or on other tabs). |
| **Tools** | 🛠 | **One-Click Utilities:** **Screenshot (Clipboard)**, **Color Picker (auto-copies `#HEX`)**, **Terminal**, **Downloads**, **Activity Monitor**, and **Sleep Screen**. |

---

## 4. Interaction, Animation & Settings

- **Trigger Mode:** `Expand on Hover` (automatically collapses back to idle across all tabs when the pointer leaves) or `Click Only`.
- **Symmetrical Animation Style (In / Out):** `Snappy` · `Smooth (Default)` · `Bouncy` · `Instant (Off)`.
- **Hover Delay (In / Out):** `50 ms` · `100 ms` · `150 ms` · `200 ms`.
- **Notch Size & Position:** `Compact` · `Standard` · `Wide` · `Custom` + *Horizontal Offset* slider & *Center* button.
- **Widget Toggles:** toggle *Clock & Date*, *Battery*, *Now Playing*, *Calendar*, *File Drop Shelf*, and *Caps Lock Indicator* individually (disabled OS monitors are stopped automatically).
- **Launch at Login:** native macOS 13+ `SMAppService.mainApp`.
- **Zero-Idle Efficiency Monitor:** live process memory footprint (`phys_footprint`) readout inside Settings.

---

## 5. Zero-Idle Consumption Architecture

- **0 polling timers when idle:** all monitors are purely OS event-driven (`NSTrackingArea`, `IOPSNotificationCreateRunLoopSource` on `.commonModes`, `MediaRemote`, `CoreWLAN CWEventDelegate`, `EKEventStoreChanged`, `NSEvent.flagsChanged`).
- **On-demand refresh:** `IOBluetooth`, `SystemStats`, and the `TimelineView` clock only run when the expanded panel is open.
- **Dynamic window shrinking:** `NSPanel` shrinks back to the tight collapsed notch bounds after closing, minimizing WindowServer overhead and preventing menu bar click blocking.
- **Full App Nap support** & **zero third-party dependencies**.
