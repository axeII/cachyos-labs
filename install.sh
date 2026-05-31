#!/bin/bash
# CachyOS Tweaks Installation Script
# Usage: ./install.sh [options]
#        ./install.sh --all       # Install everything
#        ./install.sh --power     # Power management only
#        ./install.sh --display   # Display reset only
#        ./install.sh --gaming    # Gaming configs only
#        ./install.sh --gpu       # GPU tuning only
#        ./install.sh --desktop   # Desktop configs only

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$HOME/.config/cachyos-tweaks-backup/$(date +%Y%m%d_%H%M%S)"
DRY_RUN=false

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    cat <<EOF
CachyOS Tweaks Installer

Usage:
  $0 --all       Install all active tweaks
  $0 --power     Power management (tuned auto-switcher)
  $0 --display   Display reset on login
  $0 --gaming    Gaming configs (MangoHud, env vars)
  $0 --gpu       GPU tuning (LACT config)
  $0 --desktop   Desktop configs (WezTerm, Clonky)
  $0 --dry-run   Show what would be installed without doing it
  $0 --help      Show this help

EOF
}

backup_file() {
    local file="$1"
    if [[ -f "$file" || -d "$file" ]]; then
        local dest="$BACKUP_DIR$(realpath --relative-to="$HOME" "$file" 2>/dev/null || echo "/$file")"
        mkdir -p "$(dirname "$dest")"
        cp -r "$file" "$dest"
        log_info "Backed up: $file"
    fi
}

install_power() {
    log_info "Installing power management..."

    # Monitor script
    mkdir -p "$HOME/.local/bin"
    cp "$REPO_DIR/configs/tuned/game-profile-monitor.py" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/game-profile-monitor.py"
    log_ok "Installed: game-profile-monitor.py"

    # Systemd user units
    mkdir -p "$HOME/.config/systemd/user"
    cp "$REPO_DIR/configs/tuned/game-profile-monitor.service" "$HOME/.config/systemd/user/"
    cp "$REPO_DIR/configs/tuned/game-profile-monitor.path" "$HOME/.config/systemd/user/"
    sed -i "s|\$HOME|$HOME|g" "$HOME/.config/systemd/user/game-profile-monitor.service"
    log_ok "Installed: systemd user units"

    # Manual override launchers
    mkdir -p "$HOME/.local/share/applications"
    cp "$REPO_DIR/configs/tuned/cachyos-gaming.desktop" "$HOME/.local/share/applications/"
    cp "$REPO_DIR/configs/tuned/cachyos-powersave.desktop" "$HOME/.local/share/applications/"
    log_ok "Installed: manual profile launchers"

    # Boot reset (requires sudo)
    if command -v sudo &>/dev/null; then
        log_info "Installing boot reset override (requires sudo)..."
        sudo mkdir -p /etc/systemd/system/tuned.service.d
        sudo cp "$REPO_DIR/configs/tuned/boot-reset.conf" /etc/systemd/system/tuned.service.d/
        sudo systemctl daemon-reload
        log_ok "Installed: tuned boot reset"
    else
        log_warn "sudo not available. Skipping boot reset. Install manually:"
        log_warn "  sudo mkdir -p /etc/systemd/system/tuned.service.d"
        log_warn "  sudo cp configs/tuned/boot-reset.conf /etc/systemd/system/tuned.service.d/"
    fi

    log_info "Reloading systemd user daemon..."
    systemctl --user daemon-reload || true

    log_ok "Power management installed."
    log_info "To enable: systemctl --user enable --now game-profile-monitor.service"
    log_info "To enable lingering: loginctl enable-linger \$USER"
}

install_display() {
    log_info "Installing display configuration..."

    mkdir -p "$HOME/.local/bin"
    cp "$REPO_DIR/configs/display/reset-display.sh" "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/reset-display.sh"
    log_ok "Installed: reset-display.sh"

    mkdir -p "$HOME/.config/autostart"
    cp "$REPO_DIR/configs/display/reset-display.desktop" "$HOME/.config/autostart/"
    sed -i "s|\$HOME|$HOME|g" "$HOME/.config/autostart/reset-display.desktop"
    log_ok "Installed: display autostart entry"

    log_ok "Display configuration installed."
}

install_gaming() {
    log_info "Installing gaming configurations..."

    # MangoHud
    mkdir -p "$HOME/.config/MangoHud"
    cp "$REPO_DIR/configs/gaming/MangoHud.conf" "$HOME/.config/MangoHud/"
    log_ok "Installed: MangoHud.conf"

    # Environment variables
    mkdir -p "$HOME/.config/environment.d"
    cp "$REPO_DIR/configs/gaming/gaming.conf" "$HOME/.config/environment.d/"
    log_ok "Installed: gaming environment variables"

    log_warn "Log out and back in for environment variables to take effect."
    log_ok "Gaming configurations installed."
}

install_gpu() {
    log_info "Installing GPU tuning configurations..."

    if command -v sudo &>/dev/null; then
        # Backup existing LACT config
        if [[ -f /etc/lact/config.yaml ]]; then
            sudo cp /etc/lact/config.yaml /etc/lact/config.yaml.backup.$(date +%Y%m%d) || true
            log_info "Backed up existing LACT config"
        fi

        # Copy LACT config
        sudo cp "$REPO_DIR/configs/gpu/lact-config.yaml" /etc/lact/config.yaml
        log_ok "Installed: LACT config"

        # Systemd override
        sudo mkdir -p /etc/systemd/system/lactd.service.d
        sudo cp "$REPO_DIR/configs/gpu/lactd-override.conf" /etc/systemd/system/lactd.service.d/override.conf
        sudo systemctl daemon-reload
        log_ok "Installed: LACT systemd override"

        log_info "Restarting LACT..."
        sudo systemctl restart lactd || log_warn "Failed to restart lactd (may not be installed)"
    else
        log_warn "sudo not available. Skipping GPU tuning. Install manually:"
        log_warn "  sudo cp configs/gpu/lact-config.yaml /etc/lact/config.yaml"
        log_warn "  sudo cp configs/gpu/lactd-override.conf /etc/systemd/system/lactd.service.d/"
    fi

    log_ok "GPU tuning configurations installed."
}

install_desktop() {
    log_info "Installing desktop configurations..."

    # WezTerm
    mkdir -p "$HOME/.config/wezterm"
    cp "$REPO_DIR/configs/terminal/wezterm.lua" "$HOME/.config/wezterm/"
    log_ok "Installed: wezterm.lua"

    log_ok "Desktop configurations installed."
    log_info "Restart WezTerm to apply changes."
}

install_all() {
    install_power
    install_display
    install_gaming
    install_gpu
    install_desktop
}

# Main
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"
log_info "Backup directory: $BACKUP_DIR"

case "$1" in
    --all|-a)
        install_all
        ;;
    --power|-p)
        install_power
        ;;
    --display|-d)
        install_display
        ;;
    --gaming|-g)
        install_gaming
        ;;
    --gpu)
        install_gpu
        ;;
    --desktop)
        install_desktop
        ;;
    --dry-run|--dryrun)
        DRY_RUN=true
        log_info "DRY RUN - Would install to:"
        log_info "  ~/.local/bin/game-profile-monitor.py"
        log_info "  ~/.config/systemd/user/game-profile-monitor.{service,path}"
        log_info "  ~/.local/share/applications/cachyos-{gaming,powersave}.desktop"
        log_info "  /etc/systemd/system/tuned.service.d/boot-reset.conf"
        log_info "  ~/.local/bin/reset-display.sh"
        log_info "  ~/.config/autostart/reset-display.desktop"
        log_info "  ~/.config/MangoHud/MangoHud.conf"
        log_info "  ~/.config/environment.d/gaming.conf"
        log_info "  /etc/lact/config.yaml"
        log_info "  /etc/systemd/system/lactd.service.d/override.conf"
        log_info "  ~/.config/wezterm/wezterm.lua"
        log_info "  ~/.config/systemd/user/clonky.service"
        log_info "  ~/.config/clonky/local.conf"
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        log_err "Unknown option: $1"
        usage
        exit 1
        ;;
esac

log_ok "Installation complete!"
log_info "See docs/ for detailed documentation."
log_info "See ACTIVE-vs-TEST.md for what's actively running."
