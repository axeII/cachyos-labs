# Game Tools

> OptiScaler manager and other per-game utilities.

## OptiScaler Manager

[OptiScaler](https://github.com/cdozdil/OptiScaler) is a tool that replaces DLSS/FSR/XeSS upscaling in games with alternative implementations, often enabling better quality or performance.

On Linux, OptiScaler works as a DLL hook for **Windows games running through Proton/Wine**. It does **NOT** work with native Linux game binaries.

### What It Does

- Replaces in-game upscaling with custom implementations
- Enables DLSS on non-RTX cards (via FSR 2/3 backend)
- Can force DLSS quality/performance modes
- Spoofs GPU vendor ID for DLSS compatibility

### The Problem It Solves

Managing OptiScaler across multiple games is tedious:
- Each game needs the correct DLL files copied to its directory
- Different games need different settings (spoofing on/off)
- Updates require re-downloading and re-installing per game
- Easy to lose track of which version is installed where

### The Solution: OptiScaler Manager

A Python CLI/TUI tool that automates all of the above.

### Features

- **Auto-detect games** from Steam and Heroic/GOG paths
- **Fetch latest releases** from GitHub automatically
- **Per-game installation** with version tracking
- **DLSS spoofing settings** per game (some need it, some don't)
- **Backup/restore** before updates
- **Uninstaller script** generation per game
- **Compatibility list** fetched from GitHub wiki
- **CLI mode** by default; `--tui` for interactive

### Games Currently Managed

| Game | DLSS Spoofing | Notes |
|------|--------------|-------|
| Cyberpunk 2077 | Yes (`Dxgi=auto`) | Works well with FSR 3 |
| Pacific Drive | Yes (`Dxgi=auto`) | Good performance uplift |
| Dead Island 2 | No (`Dxgi=false`) | Crashes with spoofing |
| Spider-Man Remastered | No (`Dxgi=false`) | Native DLSS works better |
| Control | No (`Dxgi=false`) | Issues with spoofing |
| HITMAN 3 | No (`Dxgi=false`) | Stable without |
| Forza Horizon 6 | (Tested) | See gaming docs |

### Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/optiscaler/optiscaler-manager.py` | `~/.config/optiscaler/` | Main manager script |

### Installation

```bash
# 1. Install dependencies
pip install rich  # For TUI mode

# 2. Copy manager
mkdir -p ~/.config/optiscaler
cp configs/optiscaler/optiscaler-manager.py ~/.config/optiscaler/
chmod +x ~/.config/optiscaler/optiscaler-manager.py

# 3. Create symlink for easy access
mkdir -p ~/.local/bin
ln -sf ~/.config/optiscaler/optiscaler-manager.py ~/.local/bin/optiscaler

# 4. Verify
optiscaler --help
```

### Usage

```bash
# List managed games
optiscaler list

# Check status
optiscaler status

# Update all games to latest OptiScaler
optiscaler update

# Update specific game
optiscaler update "Cyberpunk 2077"

# Add a new game
optiscaler add "Game Name"

# Remove a game from management
optiscaler remove "Game Name"

# Check for new releases on GitHub
optiscaler check

# Interactive TUI mode
optiscaler --tui
```

### How It Works

1. **Detects games** by scanning Steam library folders and Heroic install paths
2. **Fetches compatibility** from the OptiScaler GitHub wiki
3. **Downloads releases** from GitHub API and caches them
4. **Installs per-game** by copying the correct DLL (dxgi.dll, winmm.dll, etc.)
5. **Tracks versions** in `~/.config/optiscaler/config.json`
6. **Backs up** existing files before overwriting

### Important Notes

- **Windows games only**: Native Linux games (ELF binaries) cannot use OptiScaler
- **Steam Proton**: Games must be configured to use Proton, not native Linux
- **Anti-cheat**: Some online games with kernel-level anti-cheat may ban for DLL modification. Use only in offline/single-player games.

---

## Other Game Utilities

### VKD3D-Proton

VKD3D-Proton translates DirectX 12 to Vulkan. Usually included with Proton GE, but specific versions can be installed:

```bash
# VKD3D-Proton is typically bundled with Proton GE
# For standalone usage, see Proton GE documentation
```

### DXVK

DXVK translates DirectX 9/10/11 to Vulkan. Also bundled with Proton GE.

### Protontricks

Manage Wine prefixes for Proton games:

```bash
yay -S protontricks
protontricks --help
```

---

## Troubleshooting

### OptiScaler not loading
- Verify game is running via Proton (not native Linux)
- Check correct DLL is installed (dxgi.dll, winmm.dll, etc.)
- Check game logs for DLL load errors

### Game crashes with OptiScaler
- Try toggling DLSS spoofing (`Dxgi=auto` vs `Dxgi=false`)
- Check compatibility list for known issues
- Restore backup: `optiscaler remove "Game Name"` then reinstall

### Manager can't find game
- Ensure game is installed in standard Steam/Heroic paths
- Try adding manually: `optiscaler add "Game Name" --path /path/to/game`
