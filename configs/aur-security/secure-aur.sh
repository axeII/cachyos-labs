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
#   June 2026: ~408 AUR packages were compromised with malicious .install/.hook
#   scripts running "npm install atomic-lockfile". Building in a chroot
#   isolates the build environment from the host system.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }
log_cmd()  { echo -e "  ${YELLOW}\$${NC} $*"; }

usage() {
    cat <<EOF
AUR Security Setup - Protect against malicious AUR packages

Usage:
  $0                  Install paru + chroot and configure shell aliases
  $0 --fish-only      Only add fish alias (yay -> paru)
  $0 --verify         Check current AUR security status
  $0 --help           Show this help

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

verify_setup() {
    local ok=true

    echo ""
    log_info "=== AUR Security Verification ==="
    echo ""

    if command -v paru &>/dev/null; then
        log_ok "paru installed: $(paru -V 2>&1)"
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

    if [[ -f "$HOME/.config/paru/paru.conf" ]]; then
        if grep -q '^Chroot' "$HOME/.config/paru/paru.conf"; then
            log_ok "paru chroot enabled in config"
        else
            log_warn "paru config exists but Chroot not enabled"
            ok=false
        fi
    else
        log_warn "paru config not found"
        ok=false
    fi

    # Check for fish alias
    if [[ -f "$HOME/.config/fish/config.fish" ]]; then
        if grep -q 'abbr yay paru' "$HOME/.config/fish/config.fish"; then
            log_ok "fish alias: yay -> paru"
        else
            log_warn "fish alias not set"
        fi
    fi

    # Check for bash alias
    if [[ -f "$HOME/.bashrc" ]]; then
        if grep -q "alias yay='paru'" "$HOME/.bashrc"; then
            log_ok "bash alias: yay -> paru"
        fi
    fi

    # Check for zsh alias
    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -q "alias yay='paru'" "$HOME/.zshrc"; then
            log_ok "zsh alias: yay -> paru"
        fi
    fi

    echo ""
    if $ok; then
        log_ok "AUR security setup looks good."
    else
        log_warn "Some checks failed. Run this script without --verify to fix."
    fi
}

install_paru_chroot() {
    log_info "Installing paru and devtools..."

    if ! needs_sudo; then
        return 1
    fi

    if ! command -v paru &>/dev/null; then
        log_info "Installing paru..."
        sudo pacman -S --needed --noconfirm paru || {
            log_err "Failed to install paru"
            return 1
        }
        log_ok "paru installed"
    else
        log_ok "paru already installed: $(paru -V 2>&1 | head -1)"
    fi

    if ! command -v mkarchroot &>/dev/null; then
        log_info "Installing devtools (needed for chroot builds)..."
        sudo pacman -S --needed --noconfirm devtools || {
            log_err "Failed to install devtools"
            return 1
        }
        log_ok "devtools installed"
    else
        log_ok "devtools already installed"
    fi
}

configure_paru() {
    log_info "Configuring paru with chroot isolation..."

    local config_dir="$HOME/.config/paru"
    local config_file="$config_dir/paru.conf"

    mkdir -p "$config_dir"

    cat > "$config_file" << 'PARUCONF'
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
PARUCONF

    log_ok "paru config created: $config_file"
    log_info "Key settings: Chroot (isolated builds), CleanAfter, CombinedUpgrade"
}

add_fish_alias() {
    local fish_config="$HOME/.config/fish/config.fish"

    if [[ ! -f "$fish_config" ]]; then
        log_warn "Fish config not found at $fish_config"
        log_info "To add manually: echo 'abbr yay paru' >> ~/.config/fish/config.fish"
        return 0
    fi

    if grep -q 'abbr yay paru' "$fish_config"; then
        log_ok "fish alias 'yay -> paru' already exists"
        return 0
    fi

    awk '
        /^abbr htop zenith/ {
            print $0
            print "abbr yay paru"
            next
        }
        { print }
    ' "$fish_config" > "${fish_config}.tmp"

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
        log_ok "Added bash alias: yay -> paru"
        added=true
    fi

    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "alias yay='paru'" "$HOME/.zshrc"; then
        echo "alias yay='paru'" >> "$HOME/.zshrc"
        log_ok "Added zsh alias: yay -> paru"
        added=true
    fi

    if ! $added; then
        log_info "No bash/zsh configs found. Skipping posix aliases."
    fi
}

main_install() {
    echo ""
    log_info "=== CachyOS AUR Security Setup ==="
    log_info "This configures paru with chroot-isolated AUR builds."
    log_info "Chroot means: malicious PKGBUILD scripts run in a container,"
    log_info "              not on your host system."
    echo ""

    install_paru_chroot
    configure_paru
    add_fish_alias
    add_posix_aliases

    echo ""
    log_ok "Setup complete!"
    log_info "To test: paru -Syu (or just 'yay' which now aliases to paru)"
    log_info "To skip chroot for a single build: paru --nochroot <package>"
    echo ""
}

# Main
case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --verify)
        verify_setup
        exit 0
        ;;
    --fish-only)
        add_fish_alias
        exit 0
        ;;
    "")
        main_install
        ;;
    *)
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
esac
