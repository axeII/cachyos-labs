# Active Tweaks vs. Tested/Deprecated

This document separates what's **actively running** on the system from what was **tested, tried, or deprecated**.

## Actively Used (Production)

These configs and scripts are running right now and are considered stable.

### Power Management

| Item | Status | Path |
|------|--------|------|
| Game Profile Monitor (auto-switch tuned) | Active | `~/.local/bin/game-profile-monitor.py` |
| Tuned boot reset to powersave | Active | `/etc/systemd/system/tuned.service.d/boot-reset.conf` |
| Manual profile launchers | Active | `~/.local/share/applications/cachyos-*.desktop` |

### Display

| Item | Status | Path |
|------|--------|------|
| Display reset on KDE login | Active | `~/.local/bin/reset-display.sh` + autostart |

### GPU Tuning

| Item | Status | Path |
|------|--------|------|
| LACT GPU control | Active | `/etc/lact/config.yaml` |
| LACT systemd override (after CoolerControl) | Active | `/etc/systemd/system/lactd.service.d/override.conf` |
| Custom fan curve (30% min) | Active | LACT config |
| Undervolt -45mV | Active | LACT config |
| 270W power cap | Active | LACT config |
| Zero RPM disabled | Active | LACT config |

### Gaming

| Item | Status | Path |
|------|--------|------|
| MangoHud overlay | Active | `~/.config/MangoHud/MangoHud.conf` |
| MESA shader cache 12GB | Active | `~/.config/environment.d/gaming.conf` |
| Proton GE | Active | Installed via AUR |
| Steam launch options (FSR4) | Active | Per-game in Steam |

### Desktop

| Item | Status | Path |
|------|--------|------|
| WezTerm config | Active | `~/.config/wezterm/wezterm.lua` |
| Clonky system monitor | Active | `~/.config/clonky/` (weather disabled, English locale) |

### Game Tools

| Item | Status | Path |
|------|--------|------|
| OptiScaler Manager | Active | `~/.config/optiscaler/optiscaler-manager.py` |

---

## Tested / Experimental / Deprecated

These were tried, tested, or temporarily used but are NOT currently active.

### GPU Tuning (Tested)

| Item | Status | Notes |
|------|--------|-------|
| Undervolt -60mV | Deprecated | Too aggressive, limited boost clocks at 3840x1600 |
| Undervolt -70mV | Deprecated | Even more aggressive, used temporarily during initial tuning |
| 258W power cap | Deprecated | Bumped to 270W after analysis showed thermal headroom |
| CoolerControl GPU management | Deprecated | Conflicts with LACT; set to "Unmanaged" |

### Gaming (Tested)

| Item | Status | Notes |
|------|--------|-------|
| `ENABLE_LAYER_MESA_ANTI_LAG=1` | Tested / Not recommended | Analyzed as not beneficial for GPU-bound 3840x1600 setup; only helps CPU-bound competitive scenarios |
| `gamemoderun` for Beyond All Reason | Tested / Not used | Did not improve native Linux AppImage performance |
| BG3 native Linux OptiScaler | Tested / Impossible | OptiScaler is Windows DLL hook; incompatible with native Linux ELF |

### Power Management (Tested)

| Item | Status | Notes |
|------|--------|-------|
| `cachyos-balanced-battery` profile | Tested | Not used on desktop (no battery) |
| `desktop-powersave` profile | Tested / Previous default | Replaced by `cachyos-powersave` |

### CPU / Server (Planned but not yet executed)

| Item | Status | Notes |
|------|--------|-------|
| 5600X ↔ 5600 swap | Planned | Migration checklist created, not yet executed |
| Server PBO undervolting | Planned | PPT 80W, CO -25 to -30, -0.05V offset |
| Proxmox server tuning | Planned | Will apply after CPU swap |

### Display (Tested)

| Item | Status | Notes |
|------|--------|-------|
| Steam Big Picture on TV only | Tested | Works but manually managing display layout is tedious; auto-reset script is the preferred solution |

### Desktop (Tested)

| Item | Status | Notes |
|------|--------|-------|
| Weather in Clonky | Disabled | API broken / inaccurate; disabled in `local.conf` |
| Conky full-height right panel | Tested / Not used | Clonky (lean-conky-config) chosen instead |

---

## Notes

- **Why not Anti-Lag?** At 3840x1600 (near-4K ultrawide), the RX 9070 XT is heavily GPU-bound in single-player games. Anti-Lag only reduces input lag when the CPU runs ahead of the GPU (competitive, high-FPS scenarios). For this setup, `PROTON_FSR4_UPGRADE=1` and `game-performance %command%` are far more impactful.

- **Why -45mV undervolt?** Started at -60mV, then -70mV during early tuning. After analyzing LACT CSV stats, found the GPU was only drawing 99-132W of its 260W cap at 70% usage. -45mV provides stability while allowing better boost behavior.

- **Why disable CoolerControl for GPU?** Both CoolerControl and LACT tried to control the GPU fan simultaneously. CoolerControl had a bug where it reset zero RPM on every service restart, even when the GPU was set to "Unmanaged". Setting CoolerControl GPU to Unmanaged and letting LACT take full control solved the 0 RPM after reboot issue.
