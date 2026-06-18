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
| LACT GPU control (dual profile) | Active | `/etc/lact/config.yaml` |
| LACT systemd override (after CoolerControl) | Active | `/etc/systemd/system/lactd.service.d/override.conf` |
| Custom fan curve (30% min) | Active | LACT config (both profiles) |
| Default profile -30mV, 317W cap | Active | LACT config |
| FH6 profile 0mV (stock), 317W cap (auto-switch) | Active | LACT config |
| Zero RPM disabled | Active | LACT config |
| Setup script for friends | Available | `configs/gpu/setup-9070xt.sh` |

### Gaming

| Item | Status | Path |
|------|--------|------|
| MangoHud overlay | Active | `~/.config/MangoHud/MangoHud.conf` |
| MESA shader cache 12GB | Active | `~/.config/environment.d/gaming.conf` |
| Proton GE | Active | Installed via AUR |
| Steam launch options (FSR4) | Active | Per-game in Steam |

### AUR Security

| Item | Status | Path |
|------|--------|------|
| paru chroot builds | Active | `~/.config/paru/paru.conf` |
| fish alias (yay → paru) | Active | `~/.config/fish/config.fish` |

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
| Undervolt -70mV | Deprecated | Caused GPU reset / crash in Forza Horizon 6 |
| Undervolt -45mV | Superseded | Previous daily driver; replaced by -30mV Default |
| Undervolt -55mV (FH6) | Superseded | Was the FH6 profile; replaced by stock (0mV) after 4K RT crashes turned out to be driver bugs, not voltage. Still a valid choice on high-refresh unlocked displays |
| 258W power cap | Deprecated | Too restrictive, limited boost; bumped to VBIOS default 317W |
| 262W / 270W power caps | Deprecated | Manual caps removed; 317W VBIOS default is stable with proper undervolt |
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

- **Why dual profiles (-30mV / 0mV stock for FH6)?** After systematic FH6 benchmarking, -30mV was identified as the efficiency sweet spot (252W peak vs 284W stock, -11% power, +60MHz clocks) and is the active Default. FH6 was the only title that ever crashed (originally at -70mV). A later 4K RT test session produced new FH6 crashes that looked voltage-related but were actually **vkd3d-proton driver bugs** (descriptor heap OOB + compute shader watchdog timeout on RDNA 4) — they reproduce at stock voltage. Even so, FH6 runs at stock (0mV) for maximum stability headroom: on a 75Hz V-Sync display, CPU-bottlenecked at ~95 FPS overall, the ~60MHz clock difference between -55mV and stock is invisible. The -55mV FH6 setting (highest GPU FPS 120.4) remains a valid choice on high-refresh unlocked displays where every FPS counts — see `docs/gpu-tuning.md` for the full benchmark table.

- **Why 317W power cap?** Previous testing used manual caps (258W-270W) but the VBIOS default 317W provides the thermal headroom needed for aggressive undervolts to express their boost potential. The card draws 252-315W depending on the undervolt, and removing the cap improves stability.

- **Why disable CoolerControl for GPU?** Both CoolerControl and LACT tried to control the GPU fan simultaneously. CoolerControl had a bug where it reset zero RPM on every service restart, even when the GPU was set to "Unmanaged". Setting CoolerControl GPU to Unmanaged and letting LACT take full control solved the 0 RPM after reboot issue.
