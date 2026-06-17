#!/bin/bash
# CachyOS AUR Security Setup
# Configures paru with chroot builds to protect against malicious PKGBUILDs.
#
# What this does:
#   - Installs paru and devtools (makepkg chroot support)
#   - Creates paru config with Chroot enabled
#   - Adds fish shell alias: yay -> paru
#   - Optionally adds bash/zsh aliases
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
AUR Security Setup — Protect against malicious AUR packages

Usage:
  $0                  Install paru + chroot and configure shell aliases
  $0 --fish-only      Only add fish alias (yay -> paru)
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
  - paru AUR helper with chroot isolation for builds
  - fish shell alias: yay -> paru
  - (Optional) bash/zsh aliases

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

    if [[ -f "$HOME/.config/fish/config.fish" ]] && grep -q 'abbr yay paru' "$HOME/.config/fish/config.fish"; then
        log_ok "fish alias: yay -> paru"
    fi

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

add_fish_alias() {
    local fish_config="$HOME/.config/fish/config.fish"

    if [[ ! -f "$fish_config" ]]; then
        log_warn "Fish config not found. Add manually: echo 'abbr yay paru' >> ~/.config/fish/config.fish"
        return 0
    fi

    if grep -q 'abbr yay paru' "$fish_config"; then
        log_ok "fish alias 'yay -> paru' already exists"
        return 0
    fi

    awk '/^abbr htop zenith/ { print $0; print "abbr yay paru"; next } { print }' "$fish_config" > "${fish_config}.tmp"
    if ! grep -q 'abbr yay paru' "${fish_config}.tmp"; then
        echo "abbr yay paru" >> "${fish_config}.tmp"
    fi
    mv "${fish_config}.tmp" "$fish_config"
    log_ok "Added fish alias: yay -> paru"
}

add_posix_aliases() {
    local added=false
    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "alias yay='paru'" "$HOME/.bashrc"; then
        echo "alias yay='paru'" >> "$HOME/.bashrc"
        log_ok "Added bash alias: yay -> paru"; added=true
    fi
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "alias yay='paru'" "$HOME/.zshrc"; then
        echo "alias yay='paru'" >> "$HOME/.zshrc"
        log_ok "Added zsh alias: yay -> paru"; added=true
    fi
    if ! $added; then
        log_info "No bash/zsh configs found. Skipping."
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
    sudo chown -R "$USER:$USER" /var/lib/aurbuild 2>/dev/null || true
    sudo pacman -Sy --noconfirm 2>&1 | tail -1 || true
    log_ok "Local repo 'aurbuild' configured"
}

install_firejail() {
    log_info "Installing firejail sandbox..."
    if ! command -v firejail &>/dev/null; then
        sudo pacman -S --needed --noconfirm firejail
    fi
    log_ok "firejail installed"
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
    log_info "Protects against supply-chain attacks like the June 2026"
    log_info "\"Atomic Arch\" compromise (1,600+ packages)."
    log_info "Chroot builds run in a container — malware can't escape to host."
    echo ""

    install_paru_chroot
    configure_paru
    setup_local_repo
    install_firejail
    setup_pacman_hook
    add_fish_alias
    add_posix_aliases

    echo ""
    log_ok "Setup complete!"
    log_info "System: pacman -Syu  (repos + Chaotic-AUR only, no AUR)"
    log_info "AUR:   paur -S <package>  (uses chroot-isolated build)"
    log_info "Skip chroot: paur --nochroot <package>"
    echo ""
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
    --verify)  verify_setup; exit 0 ;;
    --audit)   audit_system; exit 0 ;;
    --fish-only) add_fish_alias; exit 0 ;;
    "") main_install ;;
    *) log_err "Unknown option: $1"; usage; exit 1 ;;
esac
