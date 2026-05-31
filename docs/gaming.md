# Gaming

> Gaming optimizations for CachyOS: MangoHud, Proton, environment variables, and Steam configuration.

## Overview

This system is optimized for single-player gaming at 3840x1600 (ultrawide, near-4K) using an RX 9070 XT. The focus is on visual quality and stable performance rather than competitive low-latency tuning.

---

## MangoHud Overlay

[MangoHud](https://github.com/flightlessmango/MangoHud) provides an in-game overlay showing FPS, frametime, GPU/CPU stats, and more.

### Current Configuration

Shows:
- **FPS** and **frametime**
- **GPU stats** (usage, temp if enabled)
- **CPU stats** (usage)
- **Throttling status** (power/temp/current throttling warnings)
- **Frame timing graph**

### Key Settings

```ini
fps
frametime
throttling_status
frame_timing
gpu_stats
cpu_stats
text_outline
```

### Toggle Presets

Press `Shift_R + F10` to cycle through presets:
- Default (current: FPS + frametime + stats)
- Other presets can be configured

### Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/gaming/MangoHud.conf` | `~/.config/MangoHud/MangoHud.conf` | Overlay configuration |

### Installation

```bash
# MangoHud is usually installed with cachyos-gaming-meta
# If not:
sudo pacman -S mangohud

# Copy config
mkdir -p ~/.config/MangoHud
cp configs/gaming/MangoHud.conf ~/.config/MangoHud/
```

### Global vs Per-Game

The config at `~/.config/MangoHud/MangoHud.conf` is the **global default**. You can override per-game with:

```bash
# In Steam launch options
MANGOHUD_CONFIG="fps_only" mangohud %command%
```

---

## Proton

### GloriousEggroll Proton (GE-Proton)

GE-Proton is preferred over Valve's stable Proton for most games due to faster upstream patches for anti-cheat, DXVK, and VKD3D.

### Installation

```bash
yay -S proton-ge-custom-bin
```

After installation, restart Steam and select GE-Proton from the compatibility dropdown.

### Proton Versions Available

| Proton | Source | Use Case |
|--------|--------|----------|
| GE-Proton | AUR (`proton-ge-custom-bin`) | **Recommended** for most games |
| Proton Experimental | Steam | Latest Valve patches |
| Proton 9 (Stable) | Steam | Conservative choice |

### Proton CachyOS (if available)

Some CachyOS-specific Proton builds may exist in the repos. Check:

```bash
pacman -Ss proton | grep cachyos
```

---

## Environment Variables

### Global Gaming Environment

File: `~/.config/environment.d/gaming.conf`

```bash
MESA_SHADER_CACHE_MAX_SIZE=12G
```

This increases Mesa's shader cache from the default to 12GB, reducing shader compilation stutter in games.

### How It Works

`environment.d` files are sourced by systemd user services and modern desktop sessions. They're cleaner than `.bashrc` exports because they apply to GUI apps too.

### Installation

```bash
mkdir -p ~/.config/environment.d
cp configs/gaming/gaming.conf ~/.config/environment.d/

# Log out and back in for changes to take effect
# Or restart the specific application
```

### Other Variables Tested

| Variable | Status | Notes |
|----------|--------|-------|
| `MESA_SHADER_CACHE_MAX_SIZE=12G` | Active | Prevents shader recompilation |
| `ENABLE_LAYER_MESA_ANTI_LAG=1` | **Not recommended** | Only helps CPU-bound competitive scenarios; this system is GPU-bound at 3840x1600 |
| `PROTON_FSR4_UPGRADE=1` | Recommended per-game | Enables FSR 4 for supported games on RDNA4 |
| `PROTON_FSR4_RDNA3_UPGRADE=1` | Recommended per-game | Backward compatibility flag |
| `game-performance %command%` | Recommended per-game | CachyOS helper for CPU governor/gamemode |
| `VKD3D_CONFIG=dxr` | Per-game | For DX12 ray tracing games |

---

## Steam Configuration

### Launch Options Template

For a typical demanding game on this system:

```bash
PROTON_FSR4_UPGRADE=1 game-performance %command%
```

### Steam Settings

1. **Disable shader pre-caching** (optional):
   - Steam → Settings → Downloads → Shader Pre-Caching
   - With 12GB Mesa cache, pre-caching is less critical
   - Can save disk space

2. **Keep Experimental Proton**:
   - Some games need it for latest fixes
   - Auto-downloads can be disabled per-game

3. **Collections for organization**:
   - Use Steam collections to manage large libraries
   - Group by: Completed, Playing, Backlog, Multiplayer

### Steam Big Picture on TV

See [Display & Audio](display-audio.md) for multi-monitor setup. To launch a game on a specific monitor:

```bash
# Not always reliable; some games ignore this
STEAM_COMPAT_LAUNCH_ON_MONITOR_ID=1 %command%
```

The more reliable approach is to set the TV as primary before launching Steam Big Picture.

---

## Game-Specific Notes

### Baldur's Gate 3

- **Native Linux build**: Works but has some performance quirks
- **OptiScaler**: Incompatible with native Linux ELF binary (it's a Windows DLL hook)
- **To use OptiScaler**: Switch to Windows version in Steam properties → Proton
- **Performance**: GPU-bound at 3840x1600; CPU rarely the bottleneck

### Beyond All Reason (BAR)

- **Native Linux AppImage**: Can be laggy
- **gamemoderun**: Did not help in testing
- **Settings reduced**: MSAA 8→2, ShadowQuality 3→1 for better performance
- **Launch script**: `~/games/beyond-all-reason/launch-bar.sh`

### Forza Horizon 6

- **Mesa 26.0.8**: Known issues; workaround or driver downgrade may be needed
- See [CHANGELOG](../CHANGELOG.md) for details

---

## ananicy-cpp Note

If `ananicy-cpp` is running, it may conflict with `gamemode` (used by `game-performance`). Check:

```bash
systemctl status ananicy-cpp
```

If active and causing issues, consider disabling it for gaming sessions.

---

## Troubleshooting

### Low FPS despite low GPU/CPU usage
- Check if game is CPU single-thread bound
- Try `game-performance %command%` for CPU governor boost
- Check if ananicy-cpp is throttling the game process
- Verify Proton version (GE-Proton often fixes such issues)

### Shader compilation stutter
- Verify `MESA_SHADER_CACHE_MAX_SIZE=12G` is active
- Check cache directory: `~/.cache/mesa_shader_cache/`

### MangoHud not showing
- Verify `mangohud` is installed
- Try running game from terminal with `mangohud %command%`
- Check MangoHud config for `no_display` being set
