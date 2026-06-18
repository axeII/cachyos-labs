# Changelog

All notable changes and tweaks to this CachyOS system are documented here.

The format is: `YYYY-MM-DD — Brief description`

---

## 2026-06

### 2026-06-18 — GPU: FH6 Profile Reverted to Stock (0mV)
- **Changed** FH6 LACT profile from -55mV → **0mV (stock)** for maximum stability headroom
- **Rationale**: A 4K RT testing session on the TV output produced new FH6 crashes. Investigation showed these were **vkd3d-proton driver bugs**, not undervolt instability:
  - Crash 1: descriptor heap out-of-bounds in FH6's RT memory allocator (fix: `PROTON_VKD3D_HEAP=1`, vkd3d-proton PR #3033; Mesa-side `radv_force_64_byte_sampled_image` already in 26.1.2)
  - Crash 2: compute shader watchdog timeout ~28 min in (reproduces at any voltage offset, including stock)
- **Decision**: FH6 is the only crash-prone title in the library. On a 75Hz V-Sync display (CPU-bottlenecked at ~95 FPS overall, GPU capable of ~120), the ~60MHz clock advantage of -55mV over stock is invisible. Running FH6 at stock removes voltage from the crash variables at zero perceptible cost.
- **Kept** Default profile at -30mV (proven efficiency win: -32W peak, +60MHz, 1°C cooler, stable across all other titles)
- **Added** `docs/gpu-tuning.md`: "Ray Tracing on RDNA 4: Known Driver Bugs" section, Phase 5 evolution entry, updated dual-profile rationale
- **Updated** `configs/gpu/lact-config.yaml`, `configs/gpu/setup-9070xt.sh` (defaults: -30mV / 0mV), `ACTIVE-vs-TEST.md`, `README.md`, `docs/gaming.md` FH6 section
- **Moved** -55mV (FH6) to superseded in ACTIVE-vs-TEST — still a valid choice on high-refresh unlocked displays
- **RT verdict**: Disable RT Reflections + RTGI in FH6; use SSR High + SSGI High + Car Reflection High instead

### 2026-06-12 — AUR Security: Chroot-Isolated Builds
- **Migrated** from `yay` to `paru` with chroot builds for AUR package isolation
- **Configured** `paru` with `Chroot`, `CombinedUpgrade`, `CleanAfter` in `~/.config/paru/paru.conf`
- **Added** fish alias `abbr yay paru` — muscle memory preserved, command expands in-place
- **Removed** orphaned/unused AUR packages: `accounts-qml-module`, `plasma5-wallpapers-dynamic`
- **Context:** June 2026 AUR compromise — ~408 packages infected with `npm install atomic-lockfile`
  in `.install`/`.hook` files. Chroot builds contain these payloads inside the container.
- **Created** `configs/aur-security/secure-aur.sh` — replicable setup script for other machines
- **Created** `docs/aur-security.md` — full documentation with threat model and troubleshooting

---

## 2026-05

### 2026-05-23 — Auto Game Mode with Tuned Profiles
- **Created** `~/.local/bin/game-profile-monitor.py` — Python daemon that auto-switches `tuned-adm` profiles
  - Detects game processes: `steam.exe`, `heroic`, `GamesExplorer`, `legendary`, `reaper(SteamLaunch)`, `Beyond-All-Reason.AppImage`
  - Switches to `cachyos-gaming` when games start
  - Switches back to `cachyos-powersave` after 60s idle
  - Sends KDE notifications on every switch
- **Created** systemd user service `game-profile-monitor.service` + path unit
- **Created** manual override `.desktop` launchers for KDE Spotlight search
- **Created** `/etc/systemd/system/tuned.service.d/boot-reset.conf` — forces powersave profile on every boot

### 2026-05-23 — Display Reset on KDE Login
- **Created** `~/.local/bin/reset-display.sh` — Forces ultrawide (DP-1, 3840x1600@75) as primary, disables TV (HDMI-A-1)
- **Created** KDE autostart desktop entry

### 2026-05-31 — Clonky English Locale Fix
- **Fixed** month/day names showing in Czech by setting `LC_ALL=en_US.UTF-8` in `clonky.service`
- `LANG=en_US.UTF-8` alone was insufficient because systemd user session had individual `LC_*` vars set to `cs_CZ.UTF-8`

### 2026-05-30 — Clonky Startup Fix + Weather Disabled
- **Fixed** `clonky.service` race condition with graphical session (changed `WantedBy` to `graphical-session.target`)
- **Fixed** `start.sh` exit code propagation so systemd `Restart=on-failure` actually works
- **Disabled** weather component in Clonky (`local.conf`)

### 2026-05-30 — LACT GPU Fan Fix
- **Created** `/etc/systemd/system/lactd.service.d/override.conf` — ensures LACT starts after CoolerControl
- **Created** post-boot fan fix with 12s delay restart to prevent 0 RPM bug
- **Tuned** LACT config: 30% minimum fan curve, -70mV undervolt, 258W power cap

### 2026-05-23 — Notification Sounds (Discord, Slack)
- Investigated per-app notification sounds on Apple Watch and iOS
- Confirmed Apple Watch has universal notification sound; differentiation only possible on iPhone

---

## 2026-04

### 2026-04-21 — GPU Temperature Stability Tuning
- Analyzed CoolerControl settings for RX 9070 XT temperature fluctuation (40-42°C jumping)
- Recommended asymmetric step sizes, hysteresis thresholds, and 5-point fan curve
- Current settings: -70mV undervolt, 258W PT, 2718 MHz VRAM max

### 2026-04-16 — LACT/CoolerControl Conflict Resolution
- Discovered conflict: both services tried to control GPU fan simultaneously
- CoolerControl had bug resetting zero RPM on every restart even when GPU set to "Unmanaged"
- Fix: CoolerControl GPU → Unmanaged, LACT takes full control with 30% min curve

### 2026-04-10 — MangoHud Default Profile
- **Created** `~/.config/MangoHud/MangoHud.conf`
- Set to show FPS + frametime + throttling_status by default
- `Shift_R+F10` toggles presets

### 2026-04-10 — Proton CachyOS Installation
- Installed GloriousEggroll Proton via AUR: `yay -S proton-ge-custom-bin`
- GE-Proton10-34 available in Steam compatibility dropdown

### 2026-04-10 — MESA Anti-Lag Analysis
- Researched `ENABLE_LAYER_MESA_ANTI_LAG=1` for RX 9070 XT
- **Conclusion:** NOT beneficial for this setup (GPU-bound at 3840x1600 ultrawide)
- Better params: `PROTON_FSR4_UPGRADE=1`, `game-performance %command%`

### 2026-04-09 — Forza Horizon 6 Mesa 26.0.8 Workaround
- Investigated Forza Horizon 6 performance issues with Mesa 26.0.8
- Driver downgrade discussed as potential fix

---

## 2026-03

### 2026-03-28 — VKD3D-Proton Versioning
- Guidance on VKD3D-Proton installation and versioning

### 2026-03-28 — Steam Collections Best Practices
- Organized Steam library collections for managing large game libraries

### 2026-03-28 — Clonky Systemd Service (Initial)
- **Created** systemd user service to start Clonky from `~/.config/clonky/start.sh`
- Later found race condition and fixed (see May 2026)

### 2026-03-23 — CPU Cooler Control Tuning
- Tuned CoolerControl for DeepCool DH-12 G2 on Ryzen 5 5600X
- Settings: asymmetric step (increase 5-8%, decrease 2-3%), min step 3-5%, hysteresis 3-5°C
- Recommendation: keep minimum duty 25-30% so fan never stops

### 2026-03-23 — Multi-Monitor Setup (External TV)
- Planned HDMI TV + DP ultrawide dual-monitor configuration
- Steam Big Picture targeted for TV output
- Later evolved into the auto-reset-display script (see May 2026)

### 2026-03-23 — Noctua NH-D15 Gen 2 Mounting
- Researched CPU cooler mounting offset choice for AM4 socket

### 2026-03-23 — Steam Big Picture TV Setup
- Investigated making TV (HDMI) the main screen for Steam Big Picture
- Found KDE display configuration approach

### 2026-03-23 — OptiScaler Update Manager
- **Created** `~/.config/optiscaler/optiscaler-manager.py` — Full Python CLI/TUI
- Features: auto-detect games, fetch GitHub releases, install per-game, DLSS spoofing, backup/restore
- Games managed: Dead Island 2, Spider-Man Remastered, Control, HITMAN 3, Pacific Drive, Cyberpunk 2077, Forza Horizon 6

---

## 2026-02

### 2026-02-15 — FSR3 + OptiScale for Baldur's Gate 3
- Attempted OptiScaler setup for BG3 native Linux build
- **Discovered:** OptiScaler is a Windows DLL hook incompatible with native Linux ELF binaries
- To use: must switch BG3 to Windows version via Proton in Steam

### 2026-02-10 — GPU Undervolting Analysis (9070 XT)
- Analyzed LACT stats CSV for RX 9070 XT
- Found -60mV undervolt left performance on table at 3840x1600
- Power draw only 99-132W of 260W cap at 70% GPU usage
- Recommended: try -40 to -45mV instead, bump power cap to 270-280W

### 2026-02-10 — WezTerm Configuration
- **Created** `~/.config/wezterm/wezterm.lua`
- Tokyo Night Storm theme, JetBrains Mono, 92% opacity, WebGpu frontend
- Fixed stable-version Lua errors (kde_window_background_blur removed, selection table flattened)

### 2026-02-05 — BG3 Proton Wayland Issues
- Investigated Baldur's Gate 3 on SteamOS with Proton Wayland
- Native Linux build performance issues noted

### 2026-02-05 — CPU Bottleneck Analysis
- Analyzed Ryzen 5600 + RX 9070 XT bottleneck at 2K/3840x1600 resolution
- Confirmed CPU can be a bottleneck in CPU-heavy scenarios despite strong GPU

---

## 2026-01

### 2026-01-31 — WiFi Stability Check
- Checked CachyOS settings and kernel config for WiFi stability improvements

### 2026-01-31 — AMD 5600 Gaming Temperatures
- Researched normal gaming temperature ranges for Ryzen 5 5600

### 2026-01-31 — CPU Repaste Recommendations
- Researched thermal paste reapplication frequency recommendations

### 2026-01-31 — Gaming Performance Tuning Overview
- Comprehensive review of Linux gaming performance with 5600/9070XT and Proton
- Covered kernel params, Mesa env vars, and CachyOS-specific optimizations

### 2026-01-29 — GPU + PSU Compatibility
- Verified ASUS Prime RX 9070 XT compatibility with 760W PSU
- Confirmed sufficient power headroom

### 2026-01-29 — GPU/CPU Underutilization Diagnosis
- Diagnosed low FPS despite low GPU/CPU utilization in some games
- Identified game engine or API overhead as potential cause

---

## 2025-12

### 2025-12-24 — GPU Migration: 6800 → 9070XT
- Full migration checklist from RX 6800 (RDNA2) to RX 9070 XT (RDNA4)
- Updated `linux-firmware` (critical for RDNA4 blobs)
- Kernel 6.12+ requirement (CachyOS default fine)
- Mesa handles 9070 XT out of the box

### 2025-12-15 — GPU Upgrade Choice Research
- Compared 9070 XT vs 5070 Ti for Baldur's Gate 3 on Linux
- Researched Linux DX12 limitations and vendor driver differences

---

## 2025-11

### 2025-11-28 — WezTerm Initial Setup
- First WezTerm config with 89% opacity, Meslo Nerd Font for Starship compatibility
- Fixed `cursor_style` typo → `default_cursor_style`

### 2025-11-28 — CachyOS Window Shortcuts
- Configured left/right half and fullscreen window shortcuts

### 2025-11-22 — FSR3 + OptiScale Setup
- Initial OptiScaler research for Baldur's Gate 3 on CachyOS

### 2025-11-21 — Brightness Issue Fix
- Fixed brightness not working while sound worked on CachyOS

---

## 2025-10

### 2025-10-19 — CPU Temp Sensor Choice
- Researched Tctl vs TCCD1 for AMD GPU monitoring fan control
- Tctl recommended for fan control (includes offset)

### 2025-10-19 — AGENTS.md Update
- Updated `~/.config/opencode/AGENTS.md` with current system data and Mesa driver info

### 2025-10-18 — Firefox Auto-Translation Disable
- Created guide to disable Firefox auto-translation notifications

### 2025-10-17 — Proxmox Migration Plan
- Planned 5600X → 5600 CPU swap between gaming PC and Proxmox server
- Server undervolting: PBO + PPT 80W cap, Curve Optimizer -25 to -30, -0.05V offset
- Gaming PC: new cooler for 5600X, PBO enabled

---

## 2025-09

### 2025-09-22 — CoolerControl Password Prompt Fix
- Fixed CoolerControl prompting for password after reboot
- Added polkit rule for passwordless service management

### 2025-09-22 — PBO, Undervolting, and Cooling Impact
- Analyzed PBO, undervolting, and cooling impact on 5600 CPU performance

### 2025-09-22 — GPU Fans Stuck at 0 RPM
- Initial diagnosis of GPU fans stuck at 0 RPM after reboot
- Later resolved via LACT/CoolerControl conflict fix (see Apr 2026)

### 2025-09-22 — Disable Swap Persistently
- Disabled zram swap on CachyOS permanently
- Masked `dev-zram0.swap` and optionally removed `zram-generator`

### 2025-09-21 — Best AM4 CPU Pairing for 9070XT
- Researched optimal AM4 CPU to pair with RX 9070 XT
- Confirmed Ryzen 5 5600 is viable but may bottleneck in CPU-heavy scenarios

### 2025-09-21 — PCIe 5.0 GPU in PCIe 4.0 Slot
- Verified minimal power loss running PCIe 5.0 GPU in PCIe 4.0 x16 slot

### 2025-09-20 — Raytracing: CPU vs GPU Workload
- Discussion on raytracing workload distribution between CPU and GPU

---

## 2025-08

### 2025-08-15 — GPU Temperature Stability
- Initial research on GPU temperature stability and undervolt tuning tips
- Led to later LACT config refinements

---

## 2025-07

### 2025-07-19 — Performance Tuning 9070XT on CachyOS
- Checked CachyOS gaming wiki and system status
- Confirmed kernel and Mesa up to date
- Recommended `cachyos-gaming-meta` and `cachyos-gaming-applications`
- **Created** `~/.config/environment.d/gaming.conf` with `MESA_SHADER_CACHE_MAX_SIZE=12G`
- Steam launch options: `ENABLE_LAYER_MESA_ANTI_LAG=1 PROTON_FSR4_RDNA3_UPGRADE=1 PROTON_FSR4_UPGRADE=1 game-performance %command%`
- Later revised: dropped Anti-Lag for this GPU-bound setup

### 2025-07-18 — MangoHud Default Profile
- Cleaned up broken MangoHud config with display issues
- Set `fps_only` as default with toggle preset functionality

### 2025-07-16 — CachyOS Shortcut Configuration
- Configured left/right half and fullscreen window shortcuts for KDE

### 2025-07-16 — CPU Temp Monitoring Choices
- Research on TMP vs TCCD1 sensor choices for fan control

### 2025-07-14 — OptiScale + FSR3 for BG3
- Full setup guide for OptiScaler on CachyOS for Baldur's Gate 3

---

## Archive

For the full raw chat history, see the [opencode session database](.local/share/opencode/opencode.db) on the source system.
