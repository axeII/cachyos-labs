# CPU & Cooling

> CPU tuning, cooling control, and system-level optimizations for CachyOS.

## Overview

This system runs an AMD Ryzen 5 5600 (6C/12T, 65W TDP) cooled by a DeepCool DH-12 G2 air cooler. The cooling strategy focuses on quiet operation with minimal temperature spikes.

---

## CoolerControl Tuning

[CoolerControl](https://gitlab.com/coolercontrol/coolercontrol) manages CPU and case fans. The GPU is set to "Unmanaged" (see [GPU Tuning](gpu-tuning.md)) to avoid conflicts with LACT.

### Recommended Settings for Air Cooler

| Setting | Value | Reason |
|---------|-------|--------|
| Step Size | Asymmetric | Different ramp up/down speeds |
| Increase Step | 5-8% | Gradual ramp up to avoid noise spikes |
| Decrease Step | 2-3% | Faster ramp down when load drops |
| Minimum Step | 3-5% | Prevents tiny oscillations |
| Maximum Step | 10-15% | Limits sudden speed jumps |
| Hysteresis Threshold | 3-5°C | Ignores small temp fluctuations |
| Hysteresis Delay | 3-5s | Brief delay before reacting |
| Only Downward | Enabled | Only apply hysteresis when temp drops |
| Minimum Duty | 25-30% | Fan never stops (prevents start/stop cycles) |

### Step Override Settings

- **Threshold Hopping**: ON
- **Always Apply 0/100%**: ON
- **Important**: Keep profile minimum duty > 0% so fan never actually stops

### CoolerControl Config Location

```bash
/etc/coolercontrol/config.toml
```

> **Note**: The exact config is not included in this repo because it's mostly GUI-managed. The settings above are documented for reproducibility.

---

## Swap Disabled (zram)

CachyOS uses `zram-generator` to create compressed swap in RAM. For a desktop with 32GB+ RAM, swap is often unnecessary and can be disabled.

### Check Current Swap

```bash
swapon --show
# or
free -h
```

### Disable zram Swap

```bash
# Turn off swap
sudo swapoff /dev/zram0

# Mask the unit so it doesn't start on boot
sudo systemctl mask dev-zram0.swap

# Optional: prevent zram-generator from running
sudo chmod -x /usr/lib/systemd/system-generators/zram-generator

# Optional: fully remove the package
sudo pacman -Rns zram-generator
```

### Re-enable if Needed

```bash
sudo systemctl unmask dev-zram0.swap
sudo chmod +x /usr/lib/systemd/system-generators/zram-generator
sudo reboot
```

---

## PBO and Undervolting (Planned)

### Context

A CPU swap is planned between the gaming PC (5600 → 5600X) and a Proxmox server (5600X → 5600). The server will be tuned for 24/7 efficiency.

### Server Plan (Proxmox + 5600)

| Setting | Value | Reason |
|---------|-------|--------|
| PBO | Enabled | Allows curve optimizer |
| PPT Cap | 80W | Limits max power for efficiency |
| Curve Optimizer | -25 to -30 | Per-core undervolt |
| Global Voltage Offset | -0.05V to -0.075V | Additional undervolt |
| C6 States | Enabled | Idle power savings |

### Gaming PC Plan (5600X)

- New cooler for 5600X (higher peak PPT ~142W)
- PBO enabled
- No undervolt needed (gaming focus)

### Tools

- `ryzenadj` — For PPT/TDC/EDC limits from Linux
- BIOS — For Curve Optimizer and voltage offset

---

## CPU Temperature Sensors

### Tctl vs TCCD1

| Sensor | Description | Use Case |
|--------|-------------|----------|
| **Tctl** | Control temperature with +27°C offset | **Fan control** (default for AMD) |
| **TCCD1** | Actual CCD die temperature | Monitoring, diagnostics |

For fan control, **Tctl is recommended** because it includes AMD's offset and is what the CPU expects for thermal management.

---

## CPU Repaste Recommendations

- **Thermal paste**: Replace every 2-3 years or when temperatures degrade
- **Method**: Pea-sized dot in center for AM4
- **Paste options**: Noctua NT-H2, Thermal Grizzly Kryonaut, Arctic MX-6

---

## Proxmox Migration Checklist

When swapping 5600X ↔ 5600:

1. **Document current BIOS settings** (screenshot)
2. **Export PBO/CO settings** if any
3. **Shutdown both systems**
4. **Swap CPUs** (clean old paste, apply new)
5. **Gaming PC**: Update AGENTS.md with new CPU info
6. **Server**: Apply PBO undervolt plan (see above)
7. **Verify**: `lscpu`, `sensors`, stress test

---

## Troubleshooting

### CoolerControl asks for password
Add a polkit rule for passwordless service management:

```bash
# Create file: /etc/polkit-1/rules.d/49-wheel-services.rules
sudo tee /etc/polkit-1/rules.d/49-wheel-services.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("wheel")) {
        return polkit.Result.YES;
    }
});
EOF
```

### Temperature spikes
- Check if step sizes are too aggressive
- Enable hysteresis with 3-5°C threshold
- Increase minimum fan duty to 25-30%

### High idle temperatures
- Check case airflow
- Verify cooler mount is secure
- Check if background tasks are spiking CPU
