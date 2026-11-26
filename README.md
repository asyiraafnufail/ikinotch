# IkiNotch

Aplikasi virtual notch native untuk macOS (tanpa notch fisik) yang dibangun dengan **Swift + AppKit + SwiftUI**, dirancang untuk **near-zero idle consumption** (0% background polling saat collapsed).

## Fitur Utama

- **Menu Bar Flush Virtual Notch** — siluet notch autentik dengan telinga cekung yang otomatis mengikuti batas tinggi menu bar saat idle, dan otomatis hilang di **Fullscreen Spaces**.
- **3 Mode Idle Content** (semuanya 0 timer saat idle):
  - **Smart Status** — otomatis menampilkan Media (Browser YouTube, Spotify, Apple Music, VLC) → Event Calendar → Nama Wi-Fi (SSID) → Custom Text + Baterai.
  - **Custom** — teks pilihan sendiri (+ opsional baterai).
  - **Pure Black** — hitam polos ala notch fisik MacBook.
- **Indikator Event-Driven** — ikon **Caps Lock (`⇪`)** dan **Keep Awake (`☕`)** muncul otomatis saat aktif.
- **Panel Expanded (`Home` · `Media` · `Tray`)**:
  - **Home:** Dashboard gabungan (Mini Media, Calendar & Tray summary, serta 4 Quick Controls: **Wi-Fi**, **Bluetooth**, **Dark/Light Theme**, **Mute**).
  - **Media:** Now Playing lengkap dengan album art / thumbnail & kontrol sistem-wide via `MediaRemote`.
  - **Tray:** File Drop Shelf (drag-and-drop titip file tanpa copy disk + AirDrop).
  - **Keep Awake (`☕`):** cegah Mac sleep 1-klik via `IOPMAssertion`.
- **Simetris & Customizable:** pilihan *Trigger Mode* (`Expand on Hover` / `Click Only`), *Animation Style* (`Snappy`, `Smooth`, `Bouncy`, `Instant`), *Hover Delay* (`50 / 100 / 150 / 200 ms`), ukuran notch, dan *Launch at Login* (`SMAppService`).

## Arsitektur Zero-Idle

- **0 polling timer saat collapsed** — seluruh monitor menggunakan event OS (`NSTrackingArea`, `IOPSNotificationCreateRunLoopSource`, `MediaRemote`, `CWEventDelegate`, `EKEventStoreChanged`, `NSEvent.flagsChanged`).
- **App Nap aktif penuh** & frame `NSPanel` menyusut ke ukuran minimum saat collapsed.
- **Zero third-party dependencies** — ukuran app bundle ~1.9 MB.

## Build & Jalankan

Persyaratan: **macOS 13.0+** dan **Xcode 15+ / Swift 5.9+**.

```bash
# Jalankan unit test
swift test

# Build release & package menjadi build/IkiNotch.app
./scripts/build_app.sh

# Jalankan aplikasi
open build/IkiNotch.app
```

Untuk pemakaian harian dan mengaktifkan **Launch at Login**, pindahkan `build/IkiNotch.app` ke folder `/Applications`.
