#!/bin/bash
# CachyOS AUR Security Setup
# Three-layer defense against malicious PKGBUILDs (Atomic Arch, June 2026):
#   Layer 1: Chaotic-AUR (prevent) — reviewed packages, no direct AUR
#   Layer 2: Chroot builds (contain) — systemd-nspawn isolation
#   Layer 3: Firejail + pacman hook + snapper (detect & recover)
#
# What this does:
#   - Installs paru and devtools (makepkg chroot support)
#   - Creates paru config with Chroot + LocalRepo enabled
#   - Creates local repo at /var/lib/aurbuild/repo/ for chroot-built packages
#   - Adds fish functions: paru -> 'paru --repo' (safe), paur -> 'paru' (AUR)
#   - Adds bash/zsh functions with same pattern
#   - Removes yay binary to prevent accidental AUR access
#   - Installs firejail with profiles for remaining AUR packages
#   - Deploys pacman post-transaction hook (compromised-package check)
#
# Why:
#   June 2026: 1,600+ AUR packages compromised via "Atomic Arch" supply-chain
#   attack. Attackers hijacked orphaned packages and injected npm install
#   atomic-lockfile / js-digest in .install/.hook files, deploying info-stealers
#   and rootkits. Building in a chroot isolates the build environment from the
#   host system.
#
# Official affected list: https://md.archlinux.org/s/SxbqukK6IA

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
AUR Security Setup — Three-layer defense against malicious AUR packages

Usage:
  $0                  Full setup: paru + chroot + LocalRepo + fish aliases
                      + firejail + pacman hook
  $0 --fish-only      Add fish functions (paru -> repo-safe, paur -> AUR)
  $0 --verify         Check current AUR security status
  $0 --audit          Cross-reference installed AUR packages against the
                      official 1,600+ known-compromised package list
  $0 --help           Show this help

Context:
  June 2026: 1,600+ AUR packages were compromised via "Atomic Arch"
  supply-chain attack. Malicious .install/.hook files ran:
      npm install atomic-lockfile js-digest
  The payload was an infostealer + rootkit that exfiltrated browser
  profiles, SSH keys, env vars, crypto wallets, and GitHub tokens.

What this configures:
  Layer 1 — Chaotic-AUR: migrate from direct AUR to reviewed packages
  Layer 2 — Chroot builds: paru + devtools, systemd-nspawn containers
  Layer 3 — Firejail + pacman hook + snapper: detect & recover
  Shell:   paru -> paru --repo (safe, repos only)
           paur -> paru        (explicit AUR access with chroot)
  Hook:    Post-transaction cross-reference against compromised lists

EOF
}

needs_sudo() {
    if command -v sudo &>/dev/null; then
        return 0
    fi
    log_err "sudo is required but not available."
    return 1
}

audit_system() {
    local official_list="https://md.archlinux.org/s/SxbqukK6IA/download"
    local community_list="https://raw.githubusercontent.com/lenucksi/aur-malware-check/3010670b9cad0146cf6e58db28cd17779535d35f/package_list.txt"
    local community_gist="https://gist.githubusercontent.com/Kidev/59bf9f5fb53ab5eee99f19a6a2fc3992/raw/aur_check.sh"

    echo ""
    log_info "=== AUR Compromise Audit ==="
    echo ""

    log_info "Fetching compromised package lists..."
    local official_matches
    official_matches=$(curl -sL "$official_list" 2>/dev/null | grep -Fxf <(pacman -Qqm 2>/dev/null) || true)

    local combined_list
    combined_list=$( { curl -fsSL "$official_list" 2>/dev/null; curl -fsSL "$community_list" 2>/dev/null; } | sort -u)
    local all_matches
    all_matches=$(comm -12 <(echo "$combined_list") <(pacman -Qqm 2>/dev/null | sort) 2>/dev/null || true)

    if [[ -n "$all_matches" ]]; then
        log_err "POTENTIALLY COMPROMISED PACKAGES FOUND:"
        echo "$all_matches"
        echo ""
        log_warn "Remove these immediately: sudo pacman -Rns <package>"
    else
        log_ok "No matches found across any compromised package list."
    fi

    echo ""
    log_info "Checking for npm artifacts (atomic-lockfile, js-digest) in /tmp..."
    local artifacts
    artifacts=$(find /tmp -maxdepth 3 \( -name 'atomic-lockfile' -o -name 'js-digest' -o -name 'node_modules' \) -type d 2>/dev/null || true)
    if [[ -n "$artifacts" ]]; then
        log_err "Suspicious npm artifacts found in /tmp:"
        echo "$artifacts"
    else
        log_ok "No npm artifacts found in /tmp."
    fi

    echo ""
    log_info "Checking pacman logs for suspicious installs in attack window (June 1-13)..."
    local suspicious
    suspicious=$(grep -iE '2026-06-(0[1-9]|1[0-3]).*installed.*atomic|2026-06-(0[1-9]|1[0-3]).*npm.install' /var/log/pacman.log 2>/dev/null || true)
    if [[ -n "$suspicious" ]]; then
        log_err "Suspicious log entries found:"
        echo "$suspicious"
    else
        log_ok "No suspicious install log entries."
    fi

    echo ""
    log_info "Quick community script (read-only, from Kidev gist):"
    log_info "  curl -sL $community_gist | bash"
    echo ""
}

verify_setup() {
    local ok=true

    echo ""
    log_info "=== AUR Security Verification ==="

    if command -v paru &>/dev/null; then
        log_ok "paru installed: $(paru -V 2>&1 | head -1)"
    else
        log_err "paru not installed"
        ok=false
    fi

    if command -v mkarchroot &>/dev/null; then
        log_ok "devtools installed (chroot support)"
    else
        log_warn "devtools not installed (chroot won't work)"
        ok=false
    fi

    if [[ -f "$HOME/.config/paru/paru.conf" ]] && grep -q '^Chroot' "$HOME/.config/paru/paru.conf"; then
        log_ok "paru chroot enabled in config"
    else
        log_warn "paru config missing or Chroot not enabled"
        ok=false
    fi

    if grep -q '^LocalRepo' "$HOME/.config/paru/paru.conf" 2>/dev/null; then
        log_ok "paru LocalRepo configured"
    else
        log_warn "paru LocalRepo not set (chroot builds may not work)"
    fi

    if [[ -f "$HOME/.config/fish/config.fish" ]] && grep -q 'function paru' "$HOME/.config/fish/config.fish"; then
        log_ok "fish function: paru -> paru --repo (safe mode)"
    else
        log_warn "fish paru function not found"
    fi

    if [[ -f "$HOME/.config/fish/config.fish" ]] && grep -q 'function paur' "$HOME/.config/fish/config.fish"; then
        log_ok "fish function: paur -> paru (AUR access)"
    else
        log_warn "fish paur function not found"
    fi

    if [[ -x /usr/local/bin/aur-malware-check.sh ]]; then
        log_ok "AUR malware check hook installed"
    else
        log_warn "AUR malware check hook not found"
    fi

    local rpm
    rpm=$(pacman -Qqm 2>/dev/null | wc -l)
    log_info "Foreign packages: $rpm (should be 3 for hardened setup)"

    if $ok; then
        log_ok "AUR security setup looks good."
    else
        log_warn "Some checks failed. Run without --verify to fix."
    fi
}

install_paru_chroot() {
    log_info "Installing paru and devtools..."
    needs_sudo || return 1

    if ! command -v paru &>/dev/null; then
        sudo pacman -S --needed --noconfirm paru || { log_err "Failed to install paru"; return 1; }
        log_ok "paru installed"
    else
        log_ok "paru already installed: $(paru -V 2>&1 | head -1)"
    fi

    if ! command -v mkarchroot &>/dev/null; then
        sudo pacman -S --needed --noconfirm devtools || { log_err "Failed to install devtools"; return 1; }
        log_ok "devtools installed"
    else
        log_ok "devtools already installed"
    fi
}

configure_paru() {
    log_info "Configuring paru with chroot isolation..."
    mkdir -p "$HOME/.config/paru"

    cat > "$HOME/.config/paru/paru.conf" << 'PARUCONF'
[options]
BottomUp
RemoveMake
SudoLoop
CleanAfter
Devel
Provides
CombinedUpgrade
UseAsk
PgpFetch
LocalRepo = aurbuild
Chroot
BatchInstall
PARUCONF

    log_ok "paru config created: ~/.config/paru/paru.conf"
    log_info "Key: LocalRepo + Chroot (isolated builds), PgpFetch, CleanAfter"
}

add_fish_aliases() {
    local fish_config="$HOME/.config/fish/config.fish"

    if [[ ! -f "$fish_config" ]]; then
        log_warn "Fish config not found. Create one, or add functions manually:"
        log_warn "  function paru; if test (count \$argv) -eq 0; command paru --repo -Syu; else; command paru --repo \$argv; end; end"
        log_warn "  function paur; command paru \$argv; end"
        return 0
    fi

    # Remove old-style abbr if present
    if grep -q 'abbr yay paru' "$fish_config"; then
        sed -i '/abbr yay paru/d' "$fish_config"
        log_info "Removed old yay abbr (replaced by paru/paur functions)"
    fi

    # Add paru function (repo-safe mode with default -Syu)
    if grep -q 'function paru' "$fish_config"; then
        log_ok "fish function 'paru' already exists"
    else
        cat >> "$fish_config" << 'FISH'

# AUR is DISABLED by default after Atomic Arch incident (June 2026).
# `paru` defaults to repo-only mode (uses --repo flag internally).
# Use `paur` for explicit AUR access on remaining AUR-only packages.
function paru
    if test (count $argv) -eq 0
        command paru --repo -Syu
    else
        command paru --repo $argv
    end
end

function paur
    command paru $argv
end
FISH
        log_ok "Added fish functions: paru (repo-safe), paur (AUR access)"
    fi
}

add_posix_aliases() {
    local block
    read -r -d '' block << 'FUNCS' || true
# AUR-safe aliases (Atomic Arch defense)
paru() {
    if [ $# -eq 0 ]; then
        command paru --repo -Syu
    else
        command paru --repo "$@"
    fi
}
paur() {
    command paru "$@"
}
FUNCS

    local added=false
    for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [[ -f "$rc" ]] && ! grep -q "paru()" "$rc" 2>/dev/null; then
            # Remove old yay alias if present
            sed -i '/alias yay/d' "$rc" 2>/dev/null || true
            echo "" >> "$rc"
            echo "$block" >> "$rc"
            log_ok "Added paru/paur functions to $rc"
            added=true
        fi
    done
    if ! $added; then
        log_info "No bash/zsh configs found (or already present). Skipping."
    fi
}

remove_yay() {
    if pacman -Q yay &>/dev/null; then
        log_info "Removing yay binary to prevent accidental AUR access..."
        sudo pacman -R --noconfirm yay 2>/dev/null || true
        log_ok "yay removed"
    else
        log_ok "yay not installed (good)"
    fi
}

setup_local_repo() {
    log_info "Setting up local repo for AUR builds..."
    if ! grep -q '^\[aurbuild\]' /etc/pacman.conf 2>/dev/null; then
        sudo sed -i '/^# cachyos repos/i # Local repo for paru chroot builds\n[aurbuild]\nSigLevel = Optional TrustAll\nServer = file:///var/lib/aurbuild/repo\n' /etc/pacman.conf
    fi
    sudo mkdir -p /var/lib/aurbuild/repo
    if [[ ! -f /var/lib/aurbuild/repo/aurbuild.db.tar.gz ]]; then
        sudo sh -c 'cd /var/lib/aurbuild/repo && tar czf aurbuild.db.tar.gz -T /dev/null && ln -sf aurbuild.db.tar.gz aurbuild.db'
    fi
    # Clean any leftover test packages from the repo database
    for leftover in aur-chroot-test aur-chroot-test-build; do
        if tar -tzf /var/lib/aurbuild/repo/aurbuild.db.tar.gz 2>/dev/null | grep -q "$leftover"; then
            sudo repo-remove /var/lib/aurbuild/repo/aurbuild.db.tar.gz "$leftover" 2>/dev/null || true
            log_info "Cleaned leftover test package: $leftover"
        fi
    done
    sudo chown -R "$USER:$USER" /var/lib/aurbuild 2>/dev/null || true
    sudo pacman -Sy --noconfirm 2>&1 | tail -1 || true
    log_ok "Local repo 'aurbuild' configured"
}

install_firejail() {
    log_info "Installing firejail sandbox..."
    if ! command -v firejail &>/dev/null; then
        sudo pacman -S --needed --noconfirm firejail
        log_ok "firejail installed"
    else
        log_ok "firejail already installed"
    fi

    # Deploy firejail profiles for remaining AUR packages
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local profiles=("upscayl-bin.local" "quadcastrgb.local" "littlesnitch-bin.local")

    for profile in "${profiles[@]}"; do
        local src="$script_dir/$profile"
        if [[ -f "$src" ]] && [[ ! -f "/etc/firejail/$profile" ]]; then
            sudo cp "$src" "/etc/firejail/$profile"
            log_ok "Deployed firejail profile: $profile"
        elif [[ -f "/etc/firejail/$profile" ]]; then
            log_ok "firejail profile already exists: $profile"
        fi
    done
}

setup_pacman_hook() {
    log_info "Installing AUR malware check hook..."
    sudo tee /usr/local/bin/aur-malware-check.sh > /dev/null << 'SCRIPT'
#!/bin/bash
set -euo pipefail
MALWARE_LIST_URL="https://raw.githubusercontent.com/lenucksi/aur-malware-check/3010670b9cad0146cf6e58db28cd17779535d35f/package_list.txt"
OFFICIAL_LIST_URL="https://md.archlinux.org/s/SxbqukK6IA/download"
foreign_pkgs=$(pacman -Qqm 2>/dev/null || true)
[[ -z "$foreign_pkgs" ]] && exit 0
hits=$(comm -12 <(echo "$foreign_pkgs" | sort) <(curl -fsSL "$OFFICIAL_LIST_URL" 2>/dev/null | sort) 2>/dev/null || true)
if [[ -z "$hits" ]]; then
    hits=$(comm -12 <(echo "$foreign_pkgs" | sort) <(curl -fsSL "$MALWARE_LIST_URL" 2>/dev/null | sort) 2>/dev/null || true)
fi
if [[ -n "$hits" ]]; then
    echo "WARNING: Installed AUR packages match known-compromised lists!"
    echo "$hits"
    exit 1
fi
SCRIPT
    sudo chmod +x /usr/local/bin/aur-malware-check.sh

    sudo tee /etc/pacman.d/hooks/aur-malware-check.hook > /dev/null << 'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *
[Action]
Description = Checking AUR packages against known malware lists...
When = PostTransaction
Exec = /usr/local/bin/aur-malware-check.sh
AbortOnFail
HOOK
    log_ok "Pacman hook installed"
}

main_install() {
    echo ""
    log_info "=== CachyOS AUR Security Setup ==="
    log_info "Three-layer defense against supply-chain attacks"
    log_info "Layer 1: Chaotic-AUR (prevent) — reviewed packages only"
    log_info "Layer 2: Chroot builds (contain) — systemd-nspawn isolation"
    log_info "Layer 3: Firejail + hook + snapper (detect & recover)"
    echo ""

    install_paru_chroot
    configure_paru
    remove_yay
    setup_local_repo
    install_firejail
    setup_pacman_hook
    add_fish_aliases
    add_posix_aliases

    echo ""
    log_ok "Setup complete!"
    log_info "Daily usage:"
    log_info "  paru                  — System update (repos only, no AUR)"
    log_info "  paru -S <pkg>         — Install from repos (safe)"
    log_info "  paur -S <pkg>         — Install from AUR (chroot-isolated)"
    log_info "  paur --nochroot <pkg> — Skip chroot (emergency only)"
    echo ""
    log_info "Run '$0 --audit' to scan for compromised packages"
    echo ""
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --verify)  verify_setup; exit 0 ;;
    --audit)   audit_system; exit 0 ;;
    --fish-only) add_fish_aliases; exit 0 ;;
    "") main_install ;;
    *) log_err "Unknown option: $1"; usage; exit 1 ;;
esac
