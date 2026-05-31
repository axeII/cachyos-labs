# Power Management

> Auto-switching tuned profiles with KDE notifications for gaming and desktop use.

## Overview

This system uses two `tuned` profiles:

| Profile | Use Case | Behavior |
|---------|----------|----------|
| `cachyos-powersave` | Browsing, chill, low-stress work | Lower CPU frequencies, quieter operation |
| `cachyos-gaming` | Gaming, performance workloads | Higher performance, CPU runs at full speed |

The switching is **fully automatic** — no manual intervention needed.

---

## How It Works

A Python daemon (`game-profile-monitor.py`) polls `/proc` every 5 seconds for known game processes. When a game starts, it switches to `cachyos-gaming`. When all game processes exit and 60 seconds pass, it switches back to `cachyos-powersave`.

KDE notifications are sent on every switch so you always know what mode you're in.

### Detected Game Processes

```python
TRIGGERS = [
    "steam.exe",           # Steam/Proton games
    "heroic",              # Heroic Launcher
    "GamesExplorer",       # GOG Galaxy
    "legendary",           # Epic Games (legendary CLI)
    "Beyond-All-Reason.AppImage",  # BAR native
    # Plus reaper(SteamLaunch) for native Steam games
]
```

> **Note:** Native Linux Steam games (like Baldur's Gate 3) run as `reaper` with `SteamLaunch` in their cmdline. The monitor checks cmdline for `SteamLaunch` to catch these.

---

## Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/tuned/game-profile-monitor.py` | `~/.local/bin/` | Main monitoring daemon |
| `configs/tuned/game-profile-monitor.service` | `~/.config/systemd/user/` | systemd user service |
| `configs/tuned/game-profile-monitor.path` | `~/.config/systemd/user/` | Path trigger unit |
| `configs/tuned/cachyos-gaming.desktop` | `~/.local/share/applications/` | Manual "Gaming Mode" launcher |
| `configs/tuned/cachyos-powersave.desktop` | `~/.local/share/applications/` | Manual "Power Saver" launcher |
| `configs/tuned/boot-reset.conf` | `/etc/systemd/system/tuned.service.d/` | Boot reset to powersave |

---

## Installation

```bash
# 1. Copy the monitor script
mkdir -p ~/.local/bin
cp configs/tuned/game-profile-monitor.py ~/.local/bin/
chmod +x ~/.local/bin/game-profile-monitor.py

# 2. Install systemd user units
mkdir -p ~/.config/systemd/user
cp configs/tuned/game-profile-monitor.service ~/.config/systemd/user/
cp configs/tuned/game-profile-monitor.path ~/.config/systemd/user/

# 3. Reload and enable
systemctl --user daemon-reload
systemctl --user enable --now game-profile-monitor.service

# 4. Enable lingering (so service runs even when not logged in)
loginctl enable-linger $USER

# 5. Install manual override launchers
mkdir -p ~/.local/share/applications
cp configs/tuned/cachyos-gaming.desktop ~/.local/share/applications/
cp configs/tuned/cachyos-powersave.desktop ~/.local/share/applications/

# 6. Install boot reset (requires sudo)
sudo mkdir -p /etc/systemd/system/tuned.service.d
sudo cp configs/tuned/boot-reset.conf /etc/systemd/system/tuned.service.d/
sudo systemctl daemon-reload
```

---

## Manual Overrides

You can manually switch profiles at any time via:

- **KDE Spotlight / KRunner**: Search for "CachyOS Gaming" or "CachyOS Power Saver"
- **Terminal**:
  ```bash
  tuned-adm profile cachyos-gaming
  tuned-adm profile cachyos-powersave
  ```

The monitor will respect manual switches and resume auto-detection after the idle timeout.

---

## Logs

```bash
# View monitor log
cat ~/.local/share/game-profile-monitor.log

# Check service status
systemctl --user status game-profile-monitor.service

# Check tuned status
tuned-adm active
```

---

## Troubleshooting

### Profile not switching
- Check `tuned-adm list` — both `cachyos-gaming` and `cachyos-powersave` must be available
- Check monitor log: `cat ~/.local/share/game-profile-monitor.log`
- Check if service is running: `systemctl --user status game-profile-monitor`

### Notification not showing
- Ensure `notify-send` is installed: `pacman -Q libnotify`
- Check KDE notification settings aren't silencing ProfileManager

### Boot doesn't reset to powersave
- Verify boot-reset override: `cat /etc/systemd/system/tuned.service.d/boot-reset.conf`
- Restart tuned: `sudo systemctl restart tuned`
