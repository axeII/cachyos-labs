# Display & Audio

> Multi-monitor management and HDMI audio fixes for CachyOS/KDE.

## Overview

This system uses an **ultrawide primary monitor** (3840x1600@75 via DisplayPort) and an **external 4K TV** (3840x2160 via HDMI). The TV is disabled by default on login and must be explicitly enabled when needed.

---

## Display Reset on Login

### Problem

KDE sometimes forgets the display layout on login, especially with hot-plugged HDMI. The ultrawide might not be primary, or the TV might enable itself unexpectedly.

### Solution

A startup script forces the correct display configuration on every KDE login.

### Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/display/reset-display.sh` | `~/.local/bin/` | Display reset script |
| `configs/display/reset-display.desktop` | `~/.config/autostart/` | KDE autostart entry |

### Script (`reset-display.sh`)

```bash
#!/bin/bash
# Reset display configuration to ultrawide-only setup
# Enables DP-1 (ultrawide) as primary and disables HDMI-A-1 (TV)

kscreen-doctor \
    output.DP-1.enable \
    output.DP-1.position.0,0 \
    output.DP-1.primary \
    output.DP-1.mode.3840x1600@75 \
    output.HDMI-A-1.disable \
    2>&1
```

### Installation

```bash
# Copy script
mkdir -p ~/.local/bin
cp configs/display/reset-display.sh ~/.local/bin/
chmod +x ~/.local/bin/reset-display.sh

# Copy autostart entry
mkdir -p ~/.config/autostart
cp configs/display/reset-display.desktop ~/.config/autostart/
```

### Manual Refresh

You can also run the script manually anytime:

```bash
~/.local/bin/reset-display.sh
```

Or search "Reset Display" in KDE Spotlight for a one-click refresh.

---

## Multi-Monitor with Steam Big Picture

### Use Case

Play games on the TV while keeping the ultrawide as the working desktop.

### Approach

1. **TV connected via HDMI**: It will appear as `HDMI-A-1`
2. **Enable TV in KDE**: System Settings → Display → Enable HDMI-A-1, set to 3840x2160
3. **Steam Big Picture**: Set to launch on the TV display
4. **Games**: Most games will use the display where Steam is running

### Quick Toggle (Optional)

For quick switching without going into KDE settings:

```bash
# Enable TV + set as primary for gaming
kscreen-doctor output.HDMI-A-1.enable output.HDMI-A-1.primary output.DP-1.disable

# Back to desktop mode
kscreen-doctor output.DP-1.enable output.DP-1.primary output.HDMI-A-1.disable
```

You can save these as desktop shortcuts or bind them to hotkeys.

---

## HDMI Audio Fix

### Problem

The HDMI audio output from the GPU (Navi 48 HDMI/DP Audio Controller) was not showing up in the sound settings.

### Diagnosis

```bash
# Check audio sinks
wpctl status

# Check card profiles
wpctl inspect alsa_card.pci-0000_0c_00.1
```

The card's Active Profile was set to `off`.

### Fix

```bash
# Activate HDMI stereo output profile
wpctl set-profile alsa_card.pci-0000_0c_00.1 output:hdmi-stereo

# Set as default sink (replace 95 with your actual sink number)
wpctl set-default 95
```

After this, "Navi 48 HDMI/DP Audio Controller Digital Stereo (HDMI)" appeared as an active sink.

### Making it Persistent

To make this persistent across reboots, add to your startup script or KDE autostart:

```bash
wpctl set-profile alsa_card.pci-0000_0c_00.1 output:hdmi-stereo || true
```

---

## Customizing for Your Setup

If your monitor connections differ, edit `reset-display.sh`:

```bash
# Find your output names
kscreen-doctor -l

# Example: if your main monitor is DP-2 instead of DP-1
kscreen-doctor \
    output.DP-2.enable \
    output.DP-2.primary \
    output.DP-2.mode.3840x1600@75 \
    output.HDMI-A-1.disable
```

---

## Troubleshooting

### Display not resetting
- Check `kscreen-doctor -l` to confirm output names
- Check KDE display settings to see if layout is being overridden by a saved config
- Try running `reset-display.sh` manually and check for errors

### Audio not showing
- Verify HDMI cable is plugged into GPU, not motherboard
- Check `wpctl status` for the card name (it may differ from `alsa_card.pci-0000_0c_00.1`)
- Check available profiles: `wpctl inspect <card_name>`
