# GPU Tuning

> RX 9070 XT (RDNA 4) configuration: undervolting, fan curves, and LACT setup.

## Overview

The ASUS Prime RX 9070 XT (Navi 48, RDNA 4) is tuned for a balance of performance, thermals, and noise. The tuning evolved over time from aggressive undervolts to a more conservative, stable configuration.

| Parameter | Current Value | History |
|-----------|--------------|---------|
| Undervolt | -45mV | Started at -60mV, then -70mV, settled on -45mV for stability + boost |
| Power Cap | 270W | Started at 258W, bumped to 270W after thermal headroom analysis |
| VRAM Max | 2718 MHz | Default-ish; not modified |
| Min Fan | 30% | Prevents 0 RPM bug; keeps GPU cool at idle |
| Zero RPM | Disabled | Prevents fan stop/spin-up oscillation |

---

## Tool: LACT (Linux AMDGPU Control Tool)

[LACT](https://github.com/ilya-zlobintsev/LACT) is used for GPU monitoring and fan control. It's preferred over CoolerControl for GPU management due to a bug in CoolerControl that reset zero RPM settings on every service restart.

### Installation

```bash
yay -S lact
sudo systemctl enable --now lactd
```

### Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/gpu/lact-config.yaml` | `/etc/lact/config.yaml` | LACT configuration |
| `configs/gpu/lactd-override.conf` | `/etc/systemd/system/lactd.service.d/override.conf` | systemd dependency fix |

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

### Key Settings

```yaml
fan_control_enabled: true
mode: curve
temperature_key: edge        # Use edge temp (not junction)
interval_ms: 500             # 500ms polling
spindown_delay_ms: 5000      # 5s delay before slowing down
change_threshold: 2            # 2°C change threshold
static_speed: 0.3             # Fallback 30% if curve fails
pmfw_options:
  zero_rpm: false             # IMPORTANT: prevents 0 RPM bug
power_cap: 270.0              # Watts
voltage_offset: -45           # mV
performance_level: auto
max_memory_clock: 1350        # MHz (actual max is 2718, this may be a LACT quirk)
```

### Installation (requires sudo)

```bash
# Backup existing config
sudo cp /etc/lact/config.yaml /etc/lact/config.yaml.backup.$(date +%Y%m%d)

# Copy new config
sudo cp configs/gpu/lact-config.yaml /etc/lact/config.yaml

# Install systemd override
sudo mkdir -p /etc/systemd/system/lactd.service.d
sudo cp configs/gpu/lactd-override.conf /etc/systemd/system/lactd.service.d/override.conf

# Reload and restart
sudo systemctl daemon-reload
sudo systemctl restart lactd
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

## Undervolt Evolution

### Phase 1: -60mV

Initial undervolt was -60mV. After analyzing LACT CSV stats, discovered the GPU was only using 99-132W of its 260W power cap at 70% GPU usage. This indicated the undervolt was too aggressive and limiting boost clocks.

### Phase 2: -70mV

Temporarily tested -70mV during initial tuning phase. Even more aggressive.

### Phase 3: -45mV (Current)

Settled on -45mV as the sweet spot:
- Stable across all games
- Allows better boost behavior at 3840x1600
- Power cap bumped to 270W to use available thermal headroom

### Analysis Method

To check if your undervolt is limiting performance:

```bash
# Check power draw while gaming
lact cli -g "<GPU_PCI_ID>" stats

# Look for:
# - Power draw vs. power cap (should be close to cap under load)
# - GPU clock vs. expected max
# - Voltage under load
```

If power draw is significantly below the cap while GPU usage is high, your undervolt may be too aggressive.

---

## GPU Migration Notes (6800 → 9070 XT)

When migrating from RX 6800 (RDNA2) to RX 9070 XT (RDNA4):

1. **Update `linux-firmware`**: Critical for RDNA4 firmware blobs
   ```bash
   sudo pacman -Syu linux-firmware
   ```
2. **Kernel**: CachyOS default (6.12+) is sufficient
3. **Mesa**: 26.0+ required for RDNA4 support (CachyOS ships 26.1.0)
4. **No proprietary driver needed** for gaming
5. **LACT supports RDNA4** out of the box

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

## Troubleshooting

### Fans stuck at 0 RPM after reboot
1. Check CoolerControl isn't managing GPU: set to "Unmanaged"
2. Check LACT has `zero_rpm: false`
3. Check LACT service started after CoolerControl: `systemctl status lactd`
4. Check override is installed: `cat /etc/systemd/system/lactd.service.d/override.conf`

### GPU not boosting properly
1. Check power draw vs. cap in LACT stats
2. Try less aggressive undervolt (-40mV or -30mV)
3. Verify power cap is set correctly

### High temperatures under load
1. Check fan curve is active (not zero RPM)
2. Verify case airflow
3. Consider case fan curve adjustments in CoolerControl (CPU fans only)
