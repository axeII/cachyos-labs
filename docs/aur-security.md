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

## Three Layers of Defense

Defense-in-depth — no single layer is perfect, so we stack three:

### Layer 1: Chaotic-AUR (prevent)
Chaotic-AUR has a **trusted maintainer system** where every package update is reviewed by a human before being published. During Atomic Arch, Chaotic-AUR caught the malicious commits in real-time and blocked them before they reached users. By migrating from direct AUR to Chaotic-AUR where possible, we eliminate the attack surface entirely for those packages.

**Coverage**: All packages that have Chaotic-AUR equivalents are installed from there instead of AUR. After migration: 8 foreign → 3 foreign packages.

### Layer 2: Chroot builds (contain)
For the remaining 3 packages that *must* come from AUR, we build them inside a **systemd-nspawn container**. The `build()` and `package()` functions in the PKGBUILD cannot access:
- `/home/ales` (user files, SSH keys, browser profiles)
- `/etc/shadow` (password hashes)
- The host filesystem at all (except `/tmp` which goes to the chroot's own `/tmp`)
- Running host processes (different PID namespace)

**Verified** by building a fake malicious PKGBUILD that attempts to exfiltrate these targets — blocked in every case.

> ⚠️ **Remaining attack surface:** The `.install` script runs on the host during `pacman -U`. Chroot doesn't protect this. We rely on **PKGBUILD diff review** before approving any AUR build.

### Layer 3: Firejail + Pacman Hook + Snapper (detect & recover)

| Sub-layer | What It Does |
|---|---|
| **Firejail sandbox** | The 3 AUR packages run in restricted namespaces: no-network for quadcastrgb/upscayl, read-only filesystem for littlesnitch. Limits blast radius if a runtime exploit is triggered. |
| **Pacman post-transaction hook** | After every `pacman` Install/Upgrade, cross-references installed AUR packages against the official Arch compromised list (1,579 packages) + community list (1,600+). If a match is found, the transaction **aborts**. |
| **Snapper snapshots** | Automatic Btrfs snapshots before every transaction. Rollback is one `snapper undochange` command. |
| **No npm on host** | The Atomic Arch payload vector was `npm install atomic-lockfile` + `js-digest`. We removed npm from the host entirely. Even if a malicious `.install` script runs, it can't deploy npm-based payloads. |

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

## How We Confirmed the System Was Not Infected

When Atomic Arch broke (June 12), we ran a forensic audit before applying any hardening. Here is exactly what we checked and what we found:

### 1. Package intersection with compromised lists

```bash
# Official Arch list (~1,579 affected packages)
comm -12 <(pacman -Qqm | sort) <(curl -sL https://md.archlinux.org/s/SxbqukK6IA/download | sort)

# Community list (~1,600+, pinned to known commit)
comm -12 <(pacman -Qqm | sort) <(curl --proto '=https' --tlsv1.3 -sL \
  https://raw.githubusercontent.com/lenucksi/aur-malware-check/3010670b9cad0146cf6e58db28cd17779535d35f/package_list.txt | sort)
```

**Result**: Zero intersections. None of the installed AUR packages were on either compromised list.

### 2. Install date vs. attack window

The attack window was June 5–11, 2026, with the third wave (malicious `.hook` files) on June 10. We checked `pacman -Qi` for every foreign package to find the *latest* install date:

```bash
pacman -Qqm | xargs -I{} sh -c 'echo "{}: $(pacman -Qi {} 2>/dev/null | grep "Install Date" | cut -d: -f2-)"'
```

**Result**: The most recently installed AUR package was on **June 6** (coolercontrol-bin's migration to the new service). The next most recent was **May 29** (littlesnitch-bin). The package installed on June 6 was `coolercontrol-bin` — which triggered the migration investigation (see below) but was not on any compromised list.

### 3. Pacman log inspection

We grepped the pacman log for any installs inside the attack window:

```bash
journalctl -b --no-pager -u pacman  # or
grep -E '^\[2026-06-(0[5-9]|1[0-1])' /var/log/pacman.log | grep -i 'installed'
```

**Result**: No AUR package installations or updates occurred on June 5–11. The only pacman transactions during that window were system-level updates from official repos.

### 4. /tmp/ artifact scan

The Atomic Arch payload left artifacts in `/tmp/` (checkouts of `npm install`):

```bash
find /tmp -maxdepth 3 \( -name 'atomic-lockfile' -o -name 'js-digest' -o -name 'node_modules' \) -type d 2>/dev/null
```

**Result**: No npm artifacts found. Additionally, `npm` itself was not installed on the host.

### 5. DNS / network behavior check

Atomic Arch payloads beaconed to `c2.atomicarch[.]systems`. We checked DNS logs:

```bash
journalctl -b --no-pager | grep -i 'atomicarch\|c2\.' || echo "No DNS hits"
```

**Result**: No hits.

### 6. Why `coolercontrol-bin` (Jun 6) was important

`coolercontrol-bin` was installed on June 6 — inside the attack window. We investigated:
- **Not on any compromised list**. Neither the official Arch list nor the community list included it.
- **Binary package from Chaotic-AUR** (`coolercontrol-bin`), not compiled from AUR. Chaotic-AUR had already blocked Atomic Arch payloads by June 6.
- **Pacman log confirmed**: standard `pacman -S` from cachyos-extra-v3 repo, no AUR interaction.
- **No `.install` hook** in the package. The Atomic Arch vector required `.install` files to run `npm install`.

**Verdict**: Low-risk. But we still migrated to `coolercontrol` (official repo, same binaries) to reduce foreign package count.

### Summary

| Check | Result | Verdict |
|---|---|---|
| Package list intersection | 0 matches | ✅ Clean |
| Install date in attack window | No AUR installs Jun 5–11 (except coolercontrol-bin, verified safe) | ✅ Clean |
| Pacman log for malicious packages | None found | ✅ Clean |
| /tmp/ npm artifacts | None found (npm not even installed) | ✅ Clean |
| DNS beaconing to known C2 | No hits | ✅ Clean |
| Chaotic-AUR migration status | 3 AUR packages remain, pinned, reviewed | ✅ Clean |

**Bottom line**: The system was not infected. Migration from AUR → Chaotic-AUR and chroot isolation were applied as **proactive hardening**, not remediation.

---

## Files

| File | Destination | Purpose |
|------|-------------|---------|
| `configs/aur-security/secure-aur.sh` | (run in place) | Full setup: install paru/devtools, configure chroot + LocalRepo, add fish aliases (`paru`→`--repo`, `paur`→AUR), deploy pacman hook + firejail profiles |
| `configs/aur-security/check-aur-malware.sh` | (run in place) | Lightweight scan: cross-reference installed AUR packages against community-maintained known-malware list |
| `configs/aur-security/test-chroot-isolation.sh` | (run in place) | Build a fake malicious PKGBUILD with and without chroot to verify containment |
| `configs/aur-security/aur-malware-check.sh` | `/usr/local/bin/aur-malware-check.sh` | Post-transaction hook script: checks packages against official + community compromised lists |
| `configs/aur-security/aur-malware-check.hook` | `/etc/pacman.d/hooks/aur-malware-check.hook` | Pacman hook that triggers the malware check script after every Install/Upgrade |
| `configs/aur-security/upscayl-bin.local` | `/etc/firejail/upscayl-bin.local` | Firejail profile: no-network, GPU + Pictures/Downloads only |
| `configs/aur-security/quadcastrgb.local` | `/etc/firejail/quadcastrgb.local` | Firejail profile: no-network, USB only |
| `configs/aur-security/littlesnitch-bin.local` | `/etc/firejail/littlesnitch-bin.local` | Firejail profile: network allowed, FS read-only except own config |

### Script Commands

| Flag | What It Does |
|---|---|
| (no args) | Full setup: install paru + devtools, configure chroot + LocalRepo, add fish aliases (`paru`→`--repo`, `paur`→AUR), deploy pacman hook + firejail profiles |
| `--audit` | Scan system: cross-reference AUR packages against 1,600+ compromised list (official + community lists), check /tmp for npm artifacts, check pacman logs |
| `--verify` | Check that chroot, LocalRepo, aliases, hook, and firejail are properly configured |
| `--fish-only` | Only add fish abbreviations (`paru`→`paru --repo`, `paur`→`paru`) |

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
2. Creates `~/.config/paru/paru.conf` with `Chroot` + `LocalRepo` enabled
3. Creates local repo at `/var/lib/aurbuild/repo/` and adds `[aurbuild]` entry to `/etc/pacman.conf`
4. Adds fish abbreviations: `paru` → `paru --repo` (safe, no AUR), `paur` → `paru` (explicit AUR access)
5. Deploys pacman post-transaction hook for malware check
6. Installs firejail and deploys sandbox profiles for remaining AUR packages
7. Optionally scans existing packages against compromised lists

### Manual Setup

```bash
# 1. Install dependencies
sudo pacman -S --needed paru devtools firejail

# 2. Create paru config with chroot + local repo
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
LocalRepo = aurbuild
BatchInstall
EOF

# 3. Create local repo for chroot-built packages
sudo mkdir -p /var/lib/aurbuild/repo
sudo repo-add /var/lib/aurbuild/repo/aurbuild.db.tar.gz

# 4. Add aurbuild repo to pacman (before chaotic-aur)
cat >> /etc/pacman.conf << 'EOF'

[aurbuild]
Server = file:///var/lib/aurbuild/repo
SigLevel = Never
EOF

# 5. Add fish aliases
echo 'abbr paru paru --repo' >> ~/.config/fish/config.fish
echo 'abbr paur paru' >> ~/.config/fish/config.fish

# 6. Deploy pacman hook for malware check
sudo mkdir -p /usr/local/bin /etc/pacman.d/hooks
sudo cp configs/aur-security/aur-malware-check.sh /usr/local/bin/
sudo cp configs/aur-security/aur-malware-check.hook /etc/pacman.d/hooks/

# 7. Deploy firejail profiles
sudo mkdir -p /etc/firejail
sudo cp configs/aur-security/upscayl-bin.local /etc/firejail/
sudo cp configs/aur-security/quadcastrgb.local /etc/firejail/
sudo cp configs/aur-security/littlesnitch-bin.local /etc/firejail/
```

---

## Daily Usage

```bash
# Full system update (repos only — Chaotic-AUR, official, AUR packages not checked)
paru

# Install from repos only (safe, no AUR)
paru -S <package>

# Install from AUR (explicit — uses chroot, shows PKGBUILD diff)
paur -S <package>

# Search AUR (explicit)
paur -Ss <query>

# Skip chroot for a single AUR build (if needed)
paur --nochroot <package>

# Audit your system periodically
./configs/aur-security/secure-aur.sh --audit
```

**Key distinction**: `paru` = safe (repos only, no AUR risk). `paur` = AUR access (chroot + diff review required). The fish abbreviations enforce this — you must type `paur` to touch AUR at all.

The first AUR build creates the chroot (~200MB download). Subsequent builds are fast.

---

## Compatibility Notes

### Fish Shell

The script adds two abbreviations to `~/.config/fish/config.fish`:
- `paru` → `paru --repo` (repo-only mode, safe — no AUR access)
- `paur` → `paru` (explicit AUR access with chroot)

An `abbr` (abbreviation) expands in-place — typing `paru` and pressing Space/Enter turns it into `paru --repo`. The command you see is always the real command.

### Bash / Zsh

For bash/zsh, add functions instead of aliases to handle arguments:
```bash
paru() { command paru --repo "$@"; }
paur() { command paru "$@"; }
```

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
