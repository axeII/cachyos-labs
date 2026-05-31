# CachyOS Tweaks & Configuration

> A curated collection of tweaks, scripts, and configurations for optimizing CachyOS (Arch-based) on a gaming-focused desktop with AMD hardware.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## System Overview

| Component | Details |
|-----------|---------|
| **OS** | CachyOS (Arch Linux based) |
| **Kernel** | 7.0.8-1-cachyos (performance-tuned) |
| **CPU** | AMD Ryzen 5 5600X (6-Core) |
| **GPU** | AMD Radeon RX 9070 XT (Navi 48, RDNA 4) |
| **Mesa** | 26.1.0 |
| **Display** | Wayland, 3840x1600 Ultrawide (DP-1) + 4K TV (HDMI-A-1) |
| **DE** | KDE Plasma |
| **AUR Helper** | `yay` |

---

## What's Inside

This repository documents every tweak, script, and configuration change made to the system. It serves two purposes:

1. **Documentation** — A complete history of changes with reasoning and commands
2. **Backup / Reproducibility** — All configs and scripts are portable and can be applied to a fresh install

### Quick Navigation

| Topic | Description |
|-------|-------------|
| [Power Management](docs/power-management.md) | Auto-switching `tuned` profiles (powersave ↔ gaming) with KDE notifications |
| [Display & Audio](docs/display-audio.md) | Multi-monitor reset script, HDMI audio fix |
| [GPU Tuning](docs/gpu-tuning.md) | LACT undervolt, fan curves, RDNA 4 specific tweaks |
| [CPU & Cooling](docs/cpu-cooling.md) | CoolerControl settings, PBO planning, swap disabled |
| [Gaming](docs/gaming.md) | MangoHud, Proton GE, environment variables, Steam tips |
| [Game Tools](docs/game-tools.md) | OptiScaler manager for DLSS/FSR across multiple games |
| [Desktop](docs/desktop.md) | WezTerm, Clonky fixes, notification sounds |

---

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/<your-username>/cachyos-tweaks.git
cd cachyos-tweaks
```

### 2. Review what you want

Check [ACTIVE-vs-TEST.md](ACTIVE-vs-TEST.md) to see what's actively used vs. what was experimental.

### 3. Install everything (or pick parts)

```bash
# Install all active tweaks
./install.sh

# Or install specific parts
./install.sh --power      # Power management only
./install.sh --display    # Display reset only
./install.sh --gaming     # Gaming configs only
./install.sh --gpu        # GPU tuning only
```

> **Warning:** Always review scripts before running. Some configs require root (sudo).

### 4. Backup first!

The install script automatically creates backups at `~/.config/cachyos-tweaks-backup/$(date +%Y%m%d_%H%M%S)/`.

---

## Active vs. Tested Tweaks

See [ACTIVE-vs-TEST.md](ACTIVE-vs-TEST.md) for a full breakdown.

**Highlights of what's actively running:**

- Auto game-mode profile switcher (tuned daemon)
- Display reset on KDE login
- LACT GPU undervolting (-45mV) + custom fan curve
- MangoHud overlay (FPS, frametime, throttling)
- Proton GE for Steam
- MESA shader cache 12GB
- WezTerm with Tokyo Night theme
- Clonky system monitor (with weather disabled)

---

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for a chronological history of all changes.

---

## Documentation Hosting

This repo is configured for **GitHub Pages** using MkDocs. View the live docs at:

`https://<your-username>.github.io/cachyos-tweaks/`

To serve locally:

```bash
pip install mkdocs mkdocs-material
mkdocs serve
```

---

## Contributing

This is a personal configuration repo, but if you have improvements or CachyOS-specific tips, feel free to open an issue or PR.

## License

MIT — Do whatever you want, but don't blame me if your system explodes. Always backup first.
