# Daftar Fitur IkiNotch

Dokumentasi lengkap fitur **IkiNotch** — aplikasi virtual notch native untuk macOS (Swift + AppKit + SwiftUI) yang dirancang ringan dengan konsumsi CPU mendekati **0% saat idle**.

---

## 1. Virtual Notch & Perilaku Layar

| Fitur | Deskripsi |
|---|---|
| **Authentic Notch Silhouette** | Bentuk notch hitam dengan lengkungan telinga cekung (*concave top ears*) yang menyatu mulus ke tepi atas layar tanpa garis tepi atas. |
| **Auto Menu Bar Height** | Saat *idle (collapsed)*, tinggi notch otomatis mengikuti batas bawah menu bar macOS (`Compact`, `Standard`, `Wide`), dengan opsi `Custom` untuk lebar & tinggi manual. |
| **Auto-Hide di Fullscreen** | Otomatis menghilang saat masuk Fullscreen Space / video fullscreen melalui deteksi `CGWindowList` (layer menu bar & jendela fullscreen normal), tetap 0% polling. |
| **Non-Activating Panel** | Membuka/mengklik kontrol di notch tidak mencuri fokus dari aplikasi yang sedang dipakai (kecuali saat mengetik di tab `Notes`). |
| **Menu Bar Utility (`LSUIElement`)** | Berjalan ringan tanpa ikon di Dock maupun `Cmd+Tab`, dilengkapi menu cepat di Menu Bar (*Show/Hide*, *Expand*, *Center*, *Settings*, *Quit*). |

---

## 2. Mode Idle (Collapsed)

Semua mode *idle* berjalan dengan **0 timer aktif**:

- **Smart Status (Default)** — prioritas otomatis di sisi kiri:
  1. **Timer Countdown** (`⏱ 24:59`) jika timer sedang berjalan.
  2. **Now Playing** (judul lagu/video dari Browser YouTube, Spotify, Apple Music, VLC).
  3. **Calendar Up Next** (event terdekat jika kalender terhubung).
  4. **Nama Wi-Fi (SSID)** yang terhubung.
  5. **`Offline`** (teks polos tanpa ikon jika Wi-Fi terputus).
- **Custom** — menampilkan teks custom buatan sendiri (mis. `Focus`, nama, atau emoji) dengan opsi tampil bersama baterai atau teks saja di tengah.
- **Pure Black** — hitam polos bersih menyerupai notch fisik MacBook.

### Indikator Event-Driven di Mode Idle
- **Baterai Proporsional Real-Level** — ikon baterai custom yang mengisi bar 0–100% sesuai persentase asli, lengkap dengan warna status (putih normal, hijau + petir `⚡` saat charging, kuning ≤ 25%, merah ≤ 15%).
- **Caps Lock (`⇪`)** — ikon amber otomatis muncul berdampingan saat Caps Lock aktif (bisa di-on/off di Settings).
- **Keep Awake (`☕`)** — ikon kopi amber otomatis muncul berdampingan saat fitur *Keep Awake* sedang aktif.

---

## 3. Panel Expanded (7 Tab)

Header atas terkunci rapi di tengah dengan tinggi tetap `28 pt`: **Jam & Tanggal · 7 Ikon Tab ukuran tetap · Baterai (+ estimasi waktu) · `☕` Keep Awake · `⚙` Settings**.

| Tab | Ikon | Fitur |
|---|---|---|
| **Home** | 🏠 | **Dashboard Gabungan:** Mini Media (thumbnail + Play/Pause & Next), ringkasan Calendar & Tray, serta **4 Quick Controls 1-klik** (**Wi-Fi**, **Bluetooth**, **Dark/Light Theme**, **Sound/Mute**). |
| **Media** | 🎵 | **Now Playing Penuh:** album art / thumbnail YouTube (`72×72 pt`, di-cache & di-downsample 128px), teks rata tengah, dan kontrol sistem-wide (**Prev / Play-Pause / Next**) via `MediaRemote` untuk Brave, Chrome, Safari, Spotify, Apple Music, dan VLC. |
| **Tray** | 📥 | **File Drop Shelf:** drag-and-drop file ke arah notch (otomatis membuka tab Tray), simpan referensi URL tanpa copy disk, drag keluar ke aplikasi lain, klik untuk *Reveal in Finder*, dan tombol **AirDrop**. |
| **Notes** | 📝 | **Quick Scratchpad:** catatan kilat *auto-save* di `UserDefaults`, otomatis mengaktifkan input keyboard saat dibuka, plus tombol **Copy** & **Clear** 1-klik. |
| **Timer** | ⏱ | **Pomodoro / Countdown:** preset `5m · 15m · 25m · 45m`, progress bar, bunyi lembut saat selesai (`Glass`), **0% CPU saat tidak aktif**, dan countdown otomatis tampil di notch saat *idle*. |
| **Stats** | 📊 | **System Snapshot (On-Demand):** menampilkan **Memory**, **Disk Free**, **Local IP**, dan **System Uptime** — hanya dibaca saat tab dibuka atau tombol Refresh diklik (**0% idle CPU**). |
| **Tools** | 🛠 | **Utilitas 1-Klik:** **Screenshot (Clipboard)**, **Color Picker (`#HEX` otomatis copy)**, **Terminal**, **Downloads**, **Activity Monitor**, dan **Sleep Screen**. |

---

## 4. Interaksi, Animasi & Pengaturan (Settings)

- **Trigger Mode:** `Expand on Hover` (otomatis tutup kembali ke idle di semua tab saat pointer keluar) atau `Click Only`.
- **Animation Style (Simetris In / Out):** `Snappy` · `Smooth (Default)` · `Bouncy` · `Instant (Off)`.
- **Hover Delay (In / Out):** `50 ms` · `100 ms` · `150 ms` · `200 ms`.
- **Notch Size & Position:** `Compact` · `Standard` · `Wide` · `Custom` + slider *Horizontal Offset* & tombol *Center*.
- **Widgets Toggles:** nyalakan/matikan *Clock & Date*, *Battery*, *Now Playing*, *Calendar*, *File Drop Shelf*, dan *Caps Lock Indicator* (monitor OS yang dimatikan ikut di-`stop()`).
- **Launch at Login:** native macOS 13+ `SMAppService.mainApp`.
- **Zero-Idle Efficiency Monitor:** pembacaan langsung penggunaan RAM proses (`phys_footprint`) di bagian bawah Settings.

---

## 5. Arsitektur Zero-Idle Consumption

- **0 polling timer saat idle:** seluruh pemantauan menggunakan notifikasi native OS (`NSTrackingArea`, `IOPSNotificationCreateRunLoopSource` di `.commonModes`, `MediaRemote`, `CoreWLAN CWEventDelegate`, `EKEventStoreChanged`, `NSEvent.flagsChanged`).
- **On-demand refresh:** `IOBluetooth`, `SystemStats`, dan `TimelineView` jam hanya bekerja saat panel *Expanded* dibuka.
- **Window shrinking:** frame `NSPanel` menyusut kembali ke ukuran minimum notch saat *collapsed*, sehingga meminimalkan beban WindowServer & tidak menghalangi klik di Menu Bar.
- **App Nap aktif penuh** & **0 dependensi pihak ketiga**.
