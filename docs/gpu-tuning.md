# GPU Tuning

> RX 9070 XT (RDNA 4) configuration: undervolting, fan curves, LACT profile auto-switching, and a complete Forza Horizon 6 case study.

## Overview

The ASUS Prime RX 9070 XT (Navi 48, RDNA 4) uses **dual LACT profiles** — a conservative daily driver and a more aggressive game-specific profile for Forza Horizon 6 — with automatic switching via process detection.

### Current Configuration

| Parameter | Default Profile | FH6 Profile |
|-----------|----------------|-------------|
| **Undervolt** | -30mV | -55mV |
| **Power Cap** | 317W (VBIOS default) | 317W (VBIOS default) |
| **Min Fan** | 30% | 30% |
| **Zero RPM** | Disabled | Disabled |
| **Trigger** | Default (always active) | `forzahorizon6.exe` process detected |

---

## Tool: LACT (Linux AMDGPU Control Tool)

[LACT](https://github.com/ilya-zlobintsev/LACT) v0.9.0+ handles all GPU tuning. It supports RDNA 4 out of the box.

### Installation

```bash
yay -S lact
sudo systemctl enable --now lactd
```

### Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/gpu/lact-config.yaml` | `/etc/lact/config.yaml` | Dual-profile LACT configuration |
| `configs/gpu/lactd-override.conf` | `/etc/systemd/system/lactd.service.d/override.conf` | Delay LACT until CoolerControl releases GPU |
| `configs/gpu/setup-9070xt.sh` | (standalone) | Interactive script for friends to replicate this setup |

---

## LACT Configuration

### Fan Curve

A 5-point custom curve to balance noise and cooling:

```yaml
curve:
  30: 0.3   # 30% at 30°C — prevents 0 RPM
  45: 0.35  # 35% at 45°C
  60: 0.45  # 45% at 60°C
  78: 0.7   # 70% at 78°C
  92: 1.0   # 100% at 92°C
```

### Default Profile (-30mV)

Safe daily driver. Lowers power draw significantly (~252W peak vs 284W stock) while gaining ~60MHz on GPU clock.

```yaml
voltage_offset: -30
power_cap: 317.0
performance_level: auto
```

### Forza Horizon 6 Profile (-55mV)

More aggressive — maximum GPU boost clocks (~3325MHz avg) and highest GPU FPS (120.4). Automatically activates when `forzahorizon6.exe` is running via process rule:

```yaml
profiles:
  forzahorizon6:
    rule:
      type: process
      filter:
        name: forzahorizon6.exe
```

### Installation

```bash
# Backup existing config
sudo cp /etc/lact/config.yaml /etc/lact/config.yaml.backup.$(date +%Y%m%d)

# Copy new config
sudo cp configs/gpu/lact-config.yaml /etc/lact/config.yaml

# Restart LACT
sudo systemctl restart lactd

# Verify
lact cli profile list
```

---

## Undervolt Evolution

### Phase 1: -60mV (Deprecated)

Initial undervolt on the RX 6800-era config. Too aggressive for RDNA 4 at 3840x1600.

### Phase 2: -70mV (Deprecated / Crashed FH6)

Temporary aggressive undervolt. Caused a full GPU reset in Forza Horizon 6 after ~20 minutes — GFX ring timeout, MES firmware failure. Used with a 262W power cap, which further limited boost.

### Phase 3: -45mV (Previous Default)

Settled on -45mV after earlier testing. Good balance of stability and performance. Was the active profile before the June 2026 FH6 deep-dive.

### Phase 4: -30mV Default + -55mV FH6 (Current)

After systematic benchmark testing, split into two profiles:

| Profile | Why |
|---------|-----|
| **-30mV** | Best **efficiency** — lowest peak power (252W), good clock gain (+60MHz), stable frametimes, best 1% lows in most games |
| **-55mV** | Best **performance** for FH6 — highest GPU FPS (120.4), highest avg clocks (~3325MHz), still 15mV above the known crash point |

---

## Forza Horizon 6 Case Study

### The Problem

After updating `proton-cachyos-slr` to v11.0.20260601-1, Forza Horizon 6 crashed after ~20 minutes of gameplay with a full GPU reset:

```
amdgpu 0000:0c:00.0: ring gfx_0.0.0 timeout
amdgpu 0000:0c:00.0: MES failed to respond (no message ack)
amdgpu 0000:0c:00.0: GPU reset begin...
```

The crash was caused by **-70mV undervolt + 262W power cap** — voltage instability under sustained load. Raising the voltage (from -70mV to -55mV) and removing the power cap (317W VBIOS default) resolved it.

### Benchmark Results

Four back-to-back FH6 built-in benchmarks at 3840x1600, Ultra preset (no FSR), V-Sync off:

| Test | Offset | Overall FPS | GPU FPS | 1% Low | Max Junc Temp | Peak Power | Avg Clock |
|------|--------|-------------|---------|--------|---------------|------------|-----------|
| Stock | 0mV | 95.0 | 119.2 | 82.6 | 67°C | 284W | ~3240MHz |
| A | -30mV | 94.0 | 119.9 | 81.3 | 66°C | 252W | ~3300MHz |
| B | -45mV | 94.0 | 120.1 | 85.6 | 67°C | 315W | ~3310MHz |
| C | -55mV | 95.0 | 120.4 | 97.3 | 67°C | ~267W | ~3325MHz |

### Key Takeaways

1. **CPU bottleneck**: Overall FPS (~95) is capped by the Ryzen 5 5600. GPU FPS reaches ~120, meaning the GPU has ~25% headroom the CPU can't feed.
2. **-30mV is the efficiency sweet spot**: Peak power drops from 284W to **252W** (-11%) with a clock gain of +60MHz.
3. **-55mV is the FH6 performance pick**: Highest GPU FPS (120.4), highest clocks (~3325MHz), best 1% low (97.3).
4. **Power cap matters**: Removing the manual 262W cap (using VBIOS default 317W) improved stability at aggressive undervolts.
5. **All tests passed**: No crashes during any of the 4 benchmark runs. The -55mV profile is 15mV above the known -70mV crash point.

### Why Dual Profiles?

- **-30mV** is ideal for most games — same FPS, lower power, lower temps, quieter fans.
- **-55mV** pushes FH6 to its peak — the GPU extracts every last MHz for the best 1% lows.
- **Auto-switch via LACT** means zero manual intervention: launch FH6, get the aggressive profile; quit FH6, back to the efficient one.

### Reproducing the Tests

To benchmark your own RX 9070 XT undervolt:

```bash
# Setup MangoHud with logging
mangohud --dlsym --log-file ~/fh6-test-%N.csv \
  %command%

# In LACT, create a profile for each voltage, then:
lact cli profile switch <profile-name>

# Run the FH6 built-in benchmark (Settings → Graphics → Run Benchmark)
# Check the CSV for: gpuUsage, gpuFreq, gpuPower, gpuTemp
# Compare overall FPS vs GPU FPS to identify CPU bottlenecks
```

---

## LACT vs CoolerControl Conflict Fix

### Problem

Both CoolerControl and LACT were trying to manage the GPU fan simultaneously. CoolerControl had a bug where it reset the "Zero RPM" setting on every service restart, even when the GPU was set to "Unmanaged" in CoolerControl.

This caused GPU fans to stick at 0 RPM after reboot.

### Solution

1. **CoolerControl**: Set GPU to "Unmanaged" (profile "0")
2. **LACT**: Takes full control with custom fan curve
3. **Systemd override**: Ensures LACT starts after CoolerControl, with a 12-second delay before restarting LACT to apply settings

The systemd override:

```ini
[Unit]
After=coolercontrold.service
Requires=coolercontrold.service

[Service]
ExecStartPost=/bin/bash -c 'sleep 12 && nohup systemctl restart lactd &'
```

---

## Temperature Stability

### Problem

Temperature fluctuated between 40-42°C at idle, causing fan speed oscillation.

### Settings That Help

- **Asymmetric step sizes**: Increase slowly (1-2%), decrease faster (2-3%)
- **Minimum step**: 2%
- **Maximum step**: 5%
- **Hysteresis**: Threshold 2.0°C, delay 5s
- **Minimum fan**: 30% — prevents stop/spin-up cycles

---

## GPU Migration Notes (6800 → 9070 XT)

When migrating from RX 6800 (RDNA2) to RX 9070 XT (RDNA4):

1. **Update `linux-firmware`**: Critical for RDNA4 firmware blobs
   ```bash
   sudo pacman -Syu linux-firmware
   ```
2. **Kernel**: CachyOS default (6.12+) is sufficient
3. **Mesa**: 26.0+ required for RDNA4 support (CachyOS ships 26.1+)
4. **No proprietary driver needed** for gaming
5. **LACT supports RDNA4** out of the box

---

## Troubleshooting

### Fans stuck at 0 RPM after reboot
1. Check CoolerControl isn't managing GPU: set to "Unmanaged"
2. Check LACT has `zero_rpm: false`
3. Check LACT service started after CoolerControl: `systemctl status lactd`
4. Check override is installed: `cat /etc/systemd/system/lactd.service.d/override.conf`

### GPU not boosting properly
1. Check power draw vs. cap in LACT stats
2. Try less aggressive undervolt (e.g., -20mV)
3. Verify power cap is set correctly (317W VBIOS default recommended)

### Game-Specific Crashes (like FH6)
1. **Different games have different voltage stability thresholds** — FH6 is particularly sensitive to undervolt instability due to sustained GPU load
2. Create a separate LACT profile with a milder undervolt
3. Set up auto-switch via process detection so the game uses its own profile
4. Run the game's built-in benchmark (if available) to test quickly

### High temperatures under load
1. Check fan curve is active (not zero RPM)
2. Verify case airflow
3. Consider case fan curve adjustments in CoolerControl (CPU fans only)

---

## Auto-Switch Script

For friends who want to replicate this setup without manually editing YAML, use:

```bash
curl -O https://raw.githubusercontent.com/<your-username>/cachyos-labs/main/configs/gpu/setup-9070xt.sh
chmod +x setup-9070xt.sh
./setup-9070xt.sh
```

The script will:
1. Detect your RX 9070 XT
2. Ask for voltage offsets (or use defaults: -30mV / -55mV)
3. Generate the LACT config
4. Backup existing config
5. Apply and restart LACT
