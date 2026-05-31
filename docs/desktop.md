# Desktop Environment

> Terminal, system monitor, and desktop customization tweaks.

## Overview

The desktop environment is KDE Plasma on Wayland. This section covers terminal configuration (WezTerm), system monitoring (Clonky), and notification customization.

---

## WezTerm

[WezTerm](https://wezfurlong.org/wezterm/) is a GPU-accelerated terminal emulator with Lua configuration.

### Current Configuration

- **Color scheme**: Tokyo Night Storm
- **Font**: JetBrains Mono Medium, 11pt
- **Opacity**: 92% (glass effect)
- **Frontend**: WebGpu (GPU-accelerated rendering)
- **Tab bar**: Clean custom colors matching Tokyo Night
- **Keybindings**: Standard + custom shortcuts

### Key Features

| Feature | Config |
|---------|--------|
| Click-to-select + auto-copy | Mouse left click selection copies to clipboard |
| Middle-click paste | Pastes from primary selection |
| Ctrl+Tab / Ctrl+Shift+Tab | Next/previous tab |
| Ctrl+Shift+T | New tab |
| Ctrl+Shift+W | Close tab |
| Ctrl+Enter | Spawn command in new tab |
| Ctrl+/- | Font size adjust |
| Ctrl+0 | Reset font size |

### Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/terminal/wezterm.lua` | `~/.config/wezterm/wezterm.lua` | Terminal configuration |

### Installation

```bash
# Install WezTerm
sudo pacman -S wezterm

# Copy config
mkdir -p ~/.config/wezterm
cp configs/terminal/wezterm.lua ~/.config/wezterm/

# Restart WezTerm to apply
```

### Customizing

Edit `~/.config/wezterm/wezterm.lua`:

```lua
-- Change font
config.font = wezterm.font("Your Font", { weight = "Regular" })

-- Change opacity
config.window_background_opacity = 0.89

-- Change color scheme
config.color_scheme = "Dracula"  -- or any scheme from wezterm.color.get_builtin_schemes()
```

List available schemes:

```bash
wezterm ls-fonts --list-system | head -20
wezterm show-keys --lua  # Show all keybindings
```

### Starship Prompt Integration

WezTerm works well with [Starship](https://starship.rs/) prompt. If using Starship, the Meslo Nerd Font variant is recommended for icon support.

---

## Clonky (Lean Conky Config)

[Clonky](https://github.com/brndnmtthws/clonky) is a system monitor sidebar built on conky.

### Fixes Applied

#### 1. Startup Race Condition

**Problem**: Clonky crashed on boot with a segmentation fault because it tried to create its window before the Wayland/XWayland session was ready.

**Solution**: Changed systemd service to start after `graphical-session.target`:

```ini
[Unit]
Description=Clonky
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=exec
ExecStart=$HOME/.config/clonky/start.sh
WorkingDirectory=$HOME/.config/clonky
Restart=on-failure

[Install]
WantedBy=graphical-session.target
```

#### 2. Exit Code Propagation

**Problem**: The `start.sh` script always exited with code 0, even when conky crashed. This prevented systemd's `Restart=on-failure` from working.

**Solution**: Modified `start.sh` to exit with conky's actual return code.

#### 3. Weather Disabled

**Problem**: Weather API was broken/inaccurate and showed broken data.

**Solution**: Disabled weather in `local.conf`:

```lua
lcc.panel = {
    "datetime",
    -- "weather",  -- Disabled: API broken
    "system",
    "cpu",
    "memory",
    "storage",
    "network",
    { "vspace", -20 },
}
```

### Re-enabling Weather

If you want to try re-enabling it later:

```bash
# Edit ~/.config/clonky/local.conf
# Uncomment "weather" in the panel list
# Restart: systemctl --user restart clonky.service
```

---

## Notification Sounds

### Discord and Slack

Different notification sounds for Discord and Slack are configured at the application level:

**Discord**:
- User Settings → Notifications → Sounds
- Built-in sound options available
- Custom sounds require Discord Nitro

**Slack**:
- Preferences → Notifications → Sound & appearance
- Built-in sounds: "Hummus", "Knock Brush", "Wow", etc.

### KDE System-Level

For app-specific notification sounds at the OS level:

```
System Settings → Notifications → Application-specific settings
```

### Apple Watch Note

Apple Watch uses a **universal notification sound** for all third-party apps. Differentiation only happens on the paired iPhone, not the watch itself.

---

## Desktop Shortcuts

Configured in KDE System Settings:

| Shortcut | Action |
|----------|--------|
| Meta + Left | Window to left half |
| Meta + Right | Window to right half |
| Meta + Up | Window maximize |
| Meta + Down | Window minimize |

These are standard KDE shortcuts but worth documenting for consistency.

---

## Mouse Speed

A startup entry adjusts mouse speed: `~/.config/autostart/mouse-speed.desktop`

---

## Troubleshooting

### WezTerm config errors

If WezTerm shows errors on startup:

1. Check if using stable or nightly build (nightly has more features)
2. Common issues:
   - `kde_window_background_blur` — not valid on Linux (remove)
   - `selection` nested table — flatten to `selection_fg`/`selection_bg`
   - `cursor_style` typo — use `default_cursor_style`
3. Clear cache: close all WezTerm windows and reopen

### Clonky not starting

```bash
# Check status
systemctl --user status clonky.service

# Check logs
journalctl --user -u clonky.service -n 50

# Try manual start
$HOME/.config/clonky/start.sh

# If segfault: verify graphical session is ready
systemctl --user status graphical-session.target
```

### WezTerm not using config

- Verify file path: `~/.config/wezterm/wezterm.lua`
- Check for syntax errors: `wezterm --config-file ~/.config/wezterm/wezterm.lua`
- Try `--skip-config` to verify WezTerm itself works
