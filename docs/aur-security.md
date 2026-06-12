# AUR Security

> Chroot-isolated AUR builds to protect against malicious PKGBUILDs, using paru with devtools.

## Overview

In June 2026, approximately **408 AUR packages** were compromised with malicious `.install` and `.hook` files that ran `npm install atomic-lockfile` during package build/installation. The malicious code executed arbitrary JavaScript payloads on the host system.

The fix: **build all AUR packages in a chroot** using `paru` + `devtools`. In a chroot, malicious install scripts are contained — they run inside an isolated environment and can't touch your host filesystem.

### Key Protection Layers

| Layer | What It Does |
|---|---|
| **Chroot builds** (`paru --chroot`) | Every AUR build runs in a clean container. `.install` scripts and `npm install` can't escape. |
| **Diff review** (`paru` default) | paru shows PKGBUILD diffs before building. You'd spot `npm install atomic-lockfile` immediately. |
| **Chaotic-aur** (repo priority) | Chaotic-aur vets packages before publishing. When a package exists in both chaotic-aur and AUR, pacman prefers chaotic-aur. |
| **No npm dependency** | The attack vector was `npm install atomic-lockfile`. Avoid installing npm globally unless needed. |

---

## How It Works

```
Before (vulnerable):
  yay -S some-pkg
  → Downloads PKGBUILD from AUR
  → Runs makepkg ON YOUR HOST
  → Malicious .install script runs npm install atomic-lockfile
  → Payload executes on your system  <-- DANGER

After (protected):
  paru -S some-pkg
  → Downloads PKGBUILD from AUR
  → Shows diff for review
  → Runs makepkg INSIDE CHROOT (clean Arch container)
  → Malicious .install script runs inside chroot
  → Can't escape the container  <-- SAFE
  → Built package is installed from the chroot
```

The chroot is created automatically on first use with `mkarchroot` (from `devtools`). It uses a minimal Arch Linux root that gets updated along with your system.

---

## Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/aur-security/secure-aur.sh` | (run in place) | One-shot setup: install paru + devtools, configure chroot, add aliases |

---

## Installation

### Quick Setup

```bash
# Run the setup script
chmod +x configs/aur-security/secure-aur.sh
./configs/aur-security/secure-aur.sh
```

The script does:
1. Installs `paru` and `devtools` (if not already installed)
2. Creates `~/.config/paru/paru.conf` with `Chroot` enabled
3. Adds `abbr yay paru` to fish shell config (muscle memory preserved)
4. Optionally adds `alias yay='paru'` to bash/zsh

### Manual Setup

If you prefer to do it yourself:

```bash
# 1. Install dependencies
sudo pacman -S --needed paru devtools

# 2. Create paru config
mkdir -p ~/.config/paru
cat > ~/.config/paru/paru.conf << 'EOF'
[options]
BottomUp
RemoveMake
SudoLoop
CleanAfter
Devel
Provides
CombinedUpgrade
UseAsk
Chroot
BatchInstall
EOF

# 3. Add fish alias
echo 'abbr yay paru' >> ~/.config/fish/config.fish
```

### Verify Setup

```bash
./configs/aur-security/secure-aur.sh --verify
```

Or check manually:

```bash
# Check paru version
paru -V

# Check chroot is configured
grep Chroot ~/.config/paru/paru.conf

# Check fish alias
grep 'abbr yay' ~/.config/fish/config.fish
```

---

## Daily Usage

```bash
# Full system update (replaces yay -Syu)
paru

# Search packages
paru -Ss <query>

# Install a package (chroot build, auto)
paru -S <package>

# Skip chroot for a single build (if needed)
paru --nochroot <package>

# Clean build artifacts
paru -Sc
```

The first time you build an AUR package, paru will create the chroot. This takes a few minutes as it downloads a minimal Arch base. Subsequent builds are fast (they re-use the chroot).

---

## Compatibility Notes

### Fish Shell

The setup script adds `abbr yay paru` to `~/.config/fish/config.fish`. An `abbr` (abbreviation) expands in-place — typing `yay` and pressing Space/Enter turns it into `paru` on the command line. Your muscle memory works, but you always see the real command.

### Bash / Zsh

The script optionally adds `alias yay='paru'` to `~/.bashrc` and `~/.zshrc`. These are standard shell aliases.

### Chaotic-aur

If you use [chaotic-aur](https://aur.chaotic.cx/), it's kept as a pacman repository (not an AUR build source). Chaotic-aur vets packages before publishing, providing an additional protection layer. When a package exists in both chaotic-aur and AUR, pacman prefers chaotic-aur due to repository priority order in `/etc/pacman.conf`.

---

## Troubleshooting

### "unknown option 'Chroot'" error

Make sure `devtools` is installed:
```bash
sudo pacman -S devtools
```

### "checking keyring... FAILED"

First chroot creation may need keyring initialization:
```bash
sudo pacman-key --init
sudo pacman-key --populate archlinux
```

### Chroot creation takes too long

The first chroot build downloads ~200MB of base packages. This is normal. Use `paru --nochroot` for urgent single packages, but re-enable chroot for regular use.

### npm/node installed on host

The chroot protects against `npm install` payloads even if npm is installed on your host. However, if you don't develop with Node.js, removing it closes that attack surface entirely:
```bash
pacman -Rns npm nodejs
```

### Removing yay (optional)

Once you're comfortable with paru, you can remove yay:
```bash
sudo pacman -Rns yay
```
paru is a drop-in replacement with the same CLI and flags.
