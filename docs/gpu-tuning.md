# GPU Tuning

> RX 9070 XT (RDNA 4) configuration: undervolting, fan curves, LACT profile auto-switching, and a complete Forza Horizon 6 case study.

## Overview

The ASUS Prime RX 9070 XT (Navi 48, RDNA 4) uses **dual LACT profiles** — an efficient daily driver for everything and a stock-voltage profile for the crash-prone Forza Horizon 6 — with automatic switching via process detection.

### Current Configuration

| Parameter | Default Profile | FH6 Profile |
|-----------|----------------|-------------|
| **Undervolt** | -30mV | 0mV (stock) |
| **Power Cap** | 317W (VBIOS default) | 317W (VBIOS default) |
| **Min Fan** | 30% | 30% |
| **Zero RPM** | Disabled | Disabled |
| **Trigger** | Default (always active) | `forzahorizon6.exe` process detected |

> **Why stock for FH6?** FH6 was the only title that ever crashed (originally at -70mV). Later 4K testing with Ray Tracing revealed the RT crashes were **vkd3d-proton driver bugs** (descriptor heap OOB + compute shader watchdog timeout), not voltage-related — they hit at any offset. Even so, FH6 is the crash-prone title in this library, so it now runs at full stock for maximum stability headroom. On a 75Hz V-Sync display, the ~60MHz clock difference between -55mV and stock is invisible (GPU FPS ~120 either way, capped by both the CPU bottleneck ~95 and the 75Hz lock). The efficiency win from -30mV is kept for every other game where it's a proven free win.

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

### Forza Horizon 6 Profile (0mV / Stock)

Runs the GPU at full stock voltage — no undervolt — for maximum stability headroom. Automatically activates when `forzahorizon6.exe` is running via process rule:

```yaml
profiles:
  forzahorizon6:
    rule:
      type: process
      filter:
        name: forzahorizon6.exe
```

FH6 is the only title in this library that has ever crashed (originally at -70mV). Although later investigation showed the 4K RT crashes were driver bugs rather than voltage instability (see [RT section](#ray-tracing-on-rdna-4-known-driver-bugs)), running FH6 at stock costs nothing visible at 75Hz V-Sync and removes voltage from the list of crash variables.

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

### Phase 4: -30mV Default + -55mV FH6 (Superseded)

After systematic benchmark testing, split into two profiles:

| Profile | Why |
|---------|-----|
| **-30mV** | Best **efficiency** — lowest peak power (252W), good clock gain (+60MHz), stable frametimes, best 1% lows in most games |
| **-55mV** | Best **performance** for FH6 — highest GPU FPS (120.4), highest avg clocks (~3325MHz), still 15mV above the known crash point |

This was the active setup from June through August 2026.

### Phase 5: -30mV Default + 0mV FH6 (Current)

A follow-up 4K RT testing session on the TV output produced new crashes in FH6. Investigation revealed these were **vkd3d-proton driver bugs** (descriptor heap out-of-bounds + compute shader watchdog timeout on RDNA 4), not undervolt instability — they reproduced at any voltage offset, including stock. See [Ray Tracing on RDNA 4](#ray-tracing-on-rdna-4-known-driver-bugs).

That finding prompted a rethink of the FH6 profile. Since FH6 is the only crash-prone title in the library and the system runs on a 75Hz V-Sync display (CPU-bottlenecked at ~95 FPS overall, GPU capable of ~120), the ~60MHz clock advantage of -55mV over stock is **invisible**. Running FH6 at stock removes voltage from the crash variables at zero perceptible cost.

The Default profile stays at **-30mV** — the efficiency win (−32W peak, +60MHz, 1°C cooler) is real and proven stable across every other title.

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
3. **-55mV is the performance pick** (highest GPU FPS 120.4, highest clocks ~3325MHz, best 1% low 97.3) — a valid choice on high-refresh unlocked displays.
4. **Power cap matters**: Removing the manual 262W cap (using VBIOS default 317W) improved stability at aggressive undervolts.
5. **All tests passed**: No crashes during any of the 4 benchmark runs. The -55mV profile is 15mV above the known -70mV crash point.
6. **Stock for FH6 is a pragmatic choice**: On a 75Hz V-Sync display, the clock/FPS difference between -55mV and stock is invisible, and FH6 is the only crash-prone title — so stock removes voltage from the crash variables for free.

### Why Dual Profiles?

- **-30mV** is ideal for most games — same FPS, lower power, lower temps, quieter fans. A proven free win.
- **0mV (stock)** for FH6 — the one crash-prone title gets full voltage headroom. At 75Hz V-Sync the performance difference vs -55mV is invisible.
- **Auto-switch via LACT** means zero manual intervention: launch FH6, get the stable stock profile; quit FH6, back to the efficient one.

> **Note on the -55mV FH6 history:** Earlier testing showed -55mV was stable in FH6's built-in benchmark and delivered the highest GPU FPS (120.4). It was retired in favor of stock not because it was unstable, but because (a) later 4K RT crashes turned out to be driver bugs unrelated to voltage, and (b) on a 75Hz V-Sync display the extra clocks buy nothing visible. If you're on a high-refresh unlocked display where every FPS counts, -55mV for FH6 remains a valid choice — see the benchmark table above.

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

## Ray Tracing on RDNA 4: Known Driver Bugs

A follow-up 4K RT testing session on the TV output (3840x2160) produced new FH6 crashes that looked like undervolt instability but were not. This section documents them so the undervolt isn't blamed for a driver problem.

### Crash 1: Descriptor heap out-of-bounds

RT Reflections at 4K crashed within minutes. The root cause is a buggy RT memory allocator in FH6 that writes past the end of a descriptor heap buffer. On NVIDIA this works by luck (larger pages); on RDNA 4 it hits unmapped memory and kills the amdgpu driver.

- **Fix (vkd3d-proton side):** `PROTON_VKD3D_HEAP=1` in Steam launch options enables the descriptor heap workaround (vkd3d-proton PR #3033). Not enabled by default in proton-cachyos-slr.
- **Fix (Mesa side):** `radv_force_64_byte_sampled_image` and `radv_wait_for_vm_map_updates` — already baked into Mesa 26.1.2+ automatically.

### Crash 2: Compute shader watchdog timeout

With the heap workaround applied, RT Reflections Low at 4K ran for ~28 minutes then crashed with `DXI_ERROR_DEVICE_REMOVED` (`ACCESS_VIOLATION_WRITE`). FH6's RT compute shaders run too long on RDNA 4 and trip the GPU watchdog timeout. This reproduces at **any** voltage offset, including stock — it is not undervolt-related.

### Verdict

RT in FH6 on RDNA 4 is not stable enough as of Mesa 26.1.2 / vkd3d-proton 11.0.20260601. Disable both **RT Reflections** and **RTGI** in-game and use the non-RT fallbacks instead:

| Setting (RT off) | Value | Replaces |
|------------------|-------|----------|
| Screen Space Reflections | High | RT Reflections |
| Screen Space GI | High | RTGI |
| Car Reflection Quality | High | (Extreme is bugged per Digital Foundry) |

You get the same visual benefit at a fraction of the cost and zero crash risk. The undervolt settings are not the cause and do not need to be changed for RT crashes.

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
1. **Different games have different voltage stability thresholds** — FH6 is particularly sensitive to undervolt instability due to sustained GPU load.
2. Create a separate LACT profile with a milder undervolt (or stock) for the crash-prone title.
3. Set up auto-switch via process detection so the game uses its own profile.
4. Run the game's built-in benchmark (if available) to test quickly.
5. **Rule out driver bugs before blaming the undervolt.** FH6 RT crashes on RDNA 4 are vkd3d-proton/Mesa issues (see [Ray Tracing on RDNA 4](#ray-tracing-on-rdna-4-known-driver-bugs)) that reproduce at stock voltage — don't sacrifice your efficiency undervolt chasing a fix for a driver problem.

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
2. Ask for voltage offsets (or use defaults: -30mV default / 0mV FH6)
3. Generate the LACT config
4. Backup existing config
5. Apply and restart LACT
