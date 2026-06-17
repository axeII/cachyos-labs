# AUR Security

> Chroot-isolated AUR builds to protect against malicious PKGBUILDs, using paru with devtools.

## Overview

In June 2026, a massive supply-chain attack ("Atomic Arch") compromised the Arch User Repository. Attackers hijacked orphaned packages and injected malicious `.install`/`.hook` files that ran `npm install atomic-lockfile` and `js-digest` during package builds. The [**official Arch list**](https://md.archlinux.org/s/SxbqukK6IA) counts **1,579+ affected packages** (community trackers now list **1,600+** across two attack waves). Popular targets included `linux-cachyos-native`, `bitcoin-core-git`, and `exodus-wallet-bin`. [Phoronix coverage](https://www.phoronix.com/news/Arch-Linux-AUR-More-Than-1500) — [Sonatype analysis (Atomic Arch)](https://www.sonatype.com/blog/atomic-arch-npm-campaign-adds-malicious-dependency) — [PrivacyGuides](https://www.privacyguides.org/news/2026/06/12/around-1-500-aur-packages-compromised-with-rootkit-like-malware/) — [Reddit discussion](https://www.reddit.com/r/linux/comments/1u3alhe/roughly_400_aur_packages_compromised/).

**Payload**: multi-stage infostealer + rootkit that exfiltrated:
- Browser profiles (Chromium + Firefox saved passwords, cookies, autofill)
- SSH private keys
- Environment variables (API tokens, cloud credentials)
- Cryptocurrency wallet files and seed phrases
- GitHub tokens

Arch declared "all's clear" on June 13 after scrubbing all malicious commits and banning compromised accounts.

The fix: **build all AUR packages in a chroot** using `paru` + `devtools`. In a chroot, malicious install scripts are contained — they run inside an isolated environment and can't touch your host filesystem.

### Key Protection Layers

| Layer | What It Does |
|---|---|
| **Chaotic-aur** (repo priority) | Chaotic-aur has trusted maintainer system + human review for untrusted PKGBUILD changes. Caught Atomic Arch in real-time. |
| **AUR disabled by default** | `paru` aliased to `--repo` mode in fish config. Only `paur` can access AUR. |
| **Chroot builds** (`paur`, via LocalRepo) | Every AUR build runs in a clean systemd-nspawn container. `.install` scripts and `npm install` can't access your home directory or running processes. |
| **Firejail sandbox** | Remaining AUR packages (littlesnitch, quadcastrgb, upscayl) run in restricted namespaces with limited FS/network access. |
| **Pacman hook** | Post-transaction hook cross-references installed AUR packages against official + community compromised-package lists. |
| **Snapper snapshots** | Automatic Btrfs snapshots before every pacman transaction for instant rollback. |
| **No npm on host** | The attack vector was `npm install atomic-lockfile` + `js-digest`. npm removed from host. |

---

## How It Works

### Build-time vs Install-time (critical nuance)

The chroot protects the **build** phase, but the **install script** (`.install`) runs on the host during `pacman -U`.

```
Before (vulnerable):
  yay -S some-pkg
  → Downloads PKGBUILD from AUR
  → Runs makepkg ON YOUR HOST
  → build()/package() can access /home, /etc/shadow, SSH keys  <-- DANGER
  → .install script runs npm install atomic-lockfile
  → Infostealer executes, exfiltrates credentials  <-- DANGER

After (protected):
  paur -S some-pkg
  → Downloads PKGBUILD from AUR
  → Copies PKGBUILD into chroot
  → build()/package() runs INSIDE CHROOT
    → /home/ales NOT accessible  ✓ CONTAINED
    → /etc/shadow NOT readable   ✓ CONTAINED
    → Network depends on chroot config
  → Built package extracted from chroot to local repo
  → pacman -U installs on HOST
    → .install script runs on HOST  ⚠️ REMAINING ATTACK SURFACE
    → Must rely on PKGBUILD diff review to catch malicious .install
```

### Test Results (verified June 2026)

| Phase | Can write to /tmp/ | Can read /etc/shadow | Can access /home/ales | Verdict |
|---|---|---|---|---|
| **build() in chroot** | Chroot's own /tmp only ✓ | No ✓ | No ✓ | **CONTAINED** |
| **package() in chroot** | Chroot's own /tmp only ✓ | No ✓ | No ✓ | **CONTAINED** |
| **install script on host** | Yes ⚠️ | Yes ⚠️ | Yes ⚠️ | **HOST LEVEL** |

**Key takeaway:** Chroot protects against build-time exfiltration (`build()`/`package()` functions stealing data). The `.install` script still runs on the host — always review PKGBUILD diffs before approving installation.

The chroot is created automatically on first build with `mkarchroot` (from `devtools`). It uses a minimal Arch Linux root at `/var/lib/aurbuild/x86_64/`.

---

## Reproducing the Test

```bash
# From the labs repo root:
./configs/aur-security/test-chroot-isolation.sh
```

This creates a fake malicious PKGBUILD, builds it with and without chroot, and compares the results. Requires `paru` + `devtools`. No actual malware is deployed.

---

## Checking if You're Affected

Run the audit to check your system:

```bash
./configs/aur-security/secure-aur.sh --audit
```

Or check manually with the community script:

```bash
# Kidev's audit script (read-only)
curl -sL https://gist.githubusercontent.com/Kidev/59bf9f5fb53ab5eee99f19a6a2fc3992/raw/aur_check.sh | bash
```

Safer one-liner (no piping to bash, for fish users run in bash first):

```bash
# Check against official Arch list (~1,579 packages)
comm -12 <(pacman -Qqm | sort) <(curl -sL https://md.archlinux.org/s/SxbqukK6IA/download | sort)

# Also check against community-maintained list (~1,600+ packages, pinned to commit hash)
comm -12 <(pacman -Qqm | sort) <(curl --proto '=https' --tlsv1.3 -sL https://raw.githubusercontent.com/lenucksi/aur-malware-check/3010670b9cad0146cf6e58db28cd17779535d35f/package_list.txt | sort)
```

If any matches appear, **remove those packages immediately**:
```bash
sudo pacman -Rns <package-name>
```

Also check for npm artifacts left in `/tmp`:
```bash
find /tmp -maxdepth 3 \( -name 'atomic-lockfile' -o -name 'js-digest' -o -name 'node_modules' \) -type d
```

> **Note:** The AUR team has reset/removed all malicious commits and banned the compromised accounts as of June 13, 2026. Packages installed *before* or *after* the attack window (June 5-11) are unaffected.

---

## Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/aur-security/secure-aur.sh` | (run in place) | Setup + audit: install paru/devtools, configure chroot, add aliases, scan for compromises |
| `configs/aur-security/check-aur-malware.sh` | (run in place) | Lightweight scan: cross-reference installed AUR packages against community-maintained known-malware list |

### Script Commands

| Flag | What It Does |
|---|---|
| (no args) | Full setup: install paru + devtools, configure chroot, add shell aliases |
| `--audit` | Scan system: cross-reference AUR packages against 1,600+ compromised list (official + community lists), check /tmp for npm artifacts, check pacman logs |
| `--verify` | Check that chroot + aliases are properly configured |
| `--fish-only` | Only add fish alias (yay → paru) |

### Standalone Malware Check

A minimal single-purpose script that checks against the community-maintained [lenucksi/aur-malware-check](https://github.com/lenucksi/aur-malware-check) list:

```bash
./configs/aur-security/check-aur-malware.sh
```

---

## Installation

### Quick Setup

```bash
chmod +x configs/aur-security/secure-aur.sh
./configs/aur-security/secure-aur.sh
```

The script does:
1. Installs `paru` and `devtools` (if not already installed)
2. Creates `~/.config/paru/paru.conf` with `Chroot` enabled
3. Adds `abbr yay paru` to fish shell config
4. Optionally adds `alias yay='paru'` to bash/zsh

### Manual Setup

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

# Audit your system periodically
./configs/aur-security/secure-aur.sh --audit
```

The first AUR build creates the chroot (~200MB download). Subsequent builds are fast.

---

## Compatibility Notes

### Fish Shell

The script adds `abbr yay paru` to `~/.config/fish/config.fish`. An `abbr` (abbreviation) expands in-place — typing `yay` and pressing Space/Enter turns it into `paru`. Muscle memory preserved, real command always visible.

### Bash / Zsh

The script optionally adds `alias yay='paru'` to `~/.bashrc` and `~/.zshrc`.

### Chaotic-aur

If you use [chaotic-aur](https://aur.chaotic.cx/), it's kept as a pacman repository. Chaotic-aur vets packages before publishing. When a package exists in both chaotic-aur and AUR, pacman prefers chaotic-aur due to repository priority in `/etc/pacman.conf`.

---

## Troubleshooting

### "unknown option 'Chroot'" error

`devtools` is not installed:
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

First build downloads ~200MB of base packages. Normal. Use `paru --nochroot` for urgent single packages, re-enable chroot after.

### npm/node installed on host

Chroot protects against `npm install` payloads even if npm is installed on your host. However, if you don't develop with Node.js, removing it closes that attack surface entirely:
```bash
pacman -Rns npm nodejs
```
