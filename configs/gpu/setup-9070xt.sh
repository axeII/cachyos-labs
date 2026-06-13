#!/bin/bash
# RX 9070 XT LACT Profile Setup
# Configures LACT with dual profiles:
#   - Default: stable daily-driver undervolt
#   - Forza Horizon 6: more aggressive undervolt (auto-switches via process detection)
#
# Usage:
#   ./setup-9070xt.sh                    # Interactive mode
#   ./setup-9070xt.sh --default -30 --fh6 -55 --apply  # Non-interactive
#
# Run with --help for all options.

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${BLUE}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
header() { echo -e "\n${CYAN}=== $1 ===${NC}\n"; }

# --- Defaults ---
DEFAULT_VOLTAGE=-30
FH6_VOLTAGE=-55
POWER_CAP=317
ZERO_RPM=false
MIN_FAN=0.3

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --default) DEFAULT_VOLTAGE="$2"; shift 2 ;;
        --fh6) FH6_VOLTAGE="$2"; shift 2 ;;
        --power-cap) POWER_CAP="$2"; shift 2 ;;
        --apply) NONINTERACTIVE=true; shift ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --default <mV>    Default profile voltage offset (default: -30)"
            echo "  --fh6 <mV>        FH6 profile voltage offset (default: -55)"
            echo "  --power-cap <W>   Power cap in watts (default: 317)"
            echo "  --apply           Non-interactive: apply with current args"
            echo "  --help            Show this help"
            exit 0
            ;;
        *) err "Unknown option: $1"; exit 1 ;;
    esac
done

# --- Prerequisites ---
header "Prerequisites"

if ! command -v lact &>/dev/null; then
    log "LACT not found. Installing..."
    if command -v yay &>/dev/null; then
        yay -S lact
    elif command -v paru &>/dev/null; then
        paru -S lact
    else
        err "No AUR helper found. Install LACT manually:"
        err "  yay -S lact"
        err "  sudo systemctl enable --now lactd"
        exit 1
    fi
    ok "LACT installed"
fi

# Check daemon is running
if ! systemctl is-active --quiet lactd; then
    log "Starting LACT daemon..."
    sudo systemctl enable --now lactd
    sleep 2
fi

# --- Detect GPU ---
header "GPU Detection"

GPU_INFO=$(lact cli list-gpus 2>/dev/null || true)
if [[ -z "$GPU_INFO" ]]; then
    # Try finding GPU via lspci
    GPU_PCI=$(lspci -nn | grep -i "9070.*XT\|Navi 48\|RDNA 4" | head -1 | awk '{print $1}')
    if [[ -z "$GPU_PCI" ]]; then
        GPU_PCI=$(lspci -nn | grep -i "VGA.*AMD.*Radeon" | head -1 | awk '{print $1}')
    fi
    if [[ -n "$GPU_PCI" ]]; then
        GPU_ID=$(lspci -nn -s "$GPU_PCI" | grep -oP '\[10de:\K[0-9a-f]+|\[1002:\K[0-9a-f]+' | head -1)
        warn "LACT CLI not available. Detected PCI device: $GPU_PCI"
        warn "We'll create a generic config. Check PCI ID with: lspci -nn -s $GPU_PCI"
    else
        warn "Could not auto-detect GPU. We'll generate a generic config."
        warn "Update the PCI ID after install."
    fi
else
    GPU_ID=$(echo "$GPU_INFO" | grep -oP '^[0-9]+:\s*\K[^\s]+' | head -1)
    GPU_NAME=$(echo "$GPU_INFO" | grep -oP '\([^)]+\)' | head -1 | tr -d '()')
    if echo "$GPU_INFO" | grep -qi "9070\|Navi 48\|RDNA 4"; then
        ok "Detected: $GPU_NAME ($GPU_ID)"
    else
        warn "Detected GPU does not appear to be an RX 9070 XT: $GPU_INFO"
        if [[ -z "$NONINTERACTIVE" ]]; then
            read -rp "Continue anyway? [Y/n] " REPLY
            [[ "$REPLY" =~ ^[Nn] ]] && exit 0
        fi
    fi
fi

# If we have a real GPU ID from LACT, use it. Otherwise use a placeholder.
FULL_GPU_ID="${GPU_ID:-1002:7550-XXXX:XXXX-0000:0c:00.0}"

# --- Interactive Configuration ---
header "Voltage Configuration"

if [[ -z "$NONINTERACTIVE" ]]; then
    echo "Recommended starting points for RX 9070 XT:"
    echo "  -30mV: Safe daily driver, good efficiency + boost gain"
    echo "  -45mV: Aggressive, test stability thoroughly"
    echo "  -55mV: Very aggressive, may crash in some games"
    echo "  -70mV: Maximum tested on this card, crashes FH6"
    echo ""
    read -rp "Default profile voltage offset (mV) [-30]: " INPUT
    DEFAULT_VOLTAGE="${INPUT:--30}"
    # Strip leading - if user entered positive, make it negative
    [[ "$DEFAULT_VOLTAGE" != -* ]] && DEFAULT_VOLTAGE="-${DEFAULT_VOLTAGE#+}"
    echo ""

    read -rp "Forza Horizon 6 profile voltage offset (mV) [-55]: " INPUT
    FH6_VOLTAGE="${INPUT:--55}"
    [[ "$FH6_VOLTAGE" != -* ]] && FH6_VOLTAGE="-${FH6_VOLTAGE#+}"
    echo ""

    read -rp "Power cap in watts (VBIOS default is 317) [317]: " INPUT
    POWER_CAP="${INPUT:-317}"
    echo ""

    echo "Configuration Summary:"
    echo "  Default profile:   ${DEFAULT_VOLTAGE}mV @ ${POWER_CAP}W"
    echo "  FH6 profile:       ${FH6_VOLTAGE}mV @ ${POWER_CAP}W"
    echo "  Auto-switch:       forzahorizon6.exe -> FH6 profile"
    echo ""
    read -rp "Apply this configuration? [Y/n] " REPLY
    [[ "$REPLY" =~ ^[Nn] ]] && exit 0
fi

# --- Generate Config ---
header "Generating Configuration"

CONFIG=$(cat <<EOF
version: 5
daemon:
  log_level: info
  admin_group: wheel
  disable_clocks_cleanup: false
apply_settings_timer: 5
gpus:
  ${FULL_GPU_ID}:
    fan_control_enabled: true
    fan_control_settings:
      mode: curve
      static_speed: ${MIN_FAN}
      temperature_key: edge
      interval_ms: 500
      curve:
        30: 0.3
        45: 0.35
        60: 0.45
        78: 0.7
        92: 1.0
      spindown_delay_ms: 5000
      change_threshold: 2
    pmfw_options:
      zero_rpm: ${ZERO_RPM}
    power_cap: ${POWER_CAP}.0
    performance_level: auto
    voltage_offset: ${DEFAULT_VOLTAGE}
profiles:
  forzahorizon6:
    gpus:
      ${FULL_GPU_ID}:
        fan_control_enabled: true
        fan_control_settings:
          mode: curve
          static_speed: ${MIN_FAN}
          temperature_key: edge
          interval_ms: 500
          curve:
            30: 0.3
            45: 0.35
            60: 0.45
            78: 0.7
            92: 1.0
          spindown_delay_ms: 5000
          change_threshold: 2
        pmfw_options:
          zero_rpm: ${ZERO_RPM}
        power_cap: ${POWER_CAP}.0
        performance_level: auto
        voltage_offset: ${FH6_VOLTAGE}
    rule:
      type: process
      filter:
        name: forzahorizon6.exe
auto_switch_profiles: true
EOF
)

echo "$CONFIG"

# --- Apply ---
header "Applying Configuration"

if [[ -f /etc/lact/config.yaml ]]; then
    BACKUP="/etc/lact/config.yaml.backup.$(date +%Y%m%d_%H%M%S)"
    log "Backing up existing config to $BACKUP"
    sudo cp /etc/lact/config.yaml "$BACKUP"
fi

log "Writing /etc/lact/config.yaml ..."
echo "$CONFIG" | sudo tee /etc/lact/config.yaml > /dev/null
ok "Config written"

log "Restarting LACT daemon..."
sudo systemctl restart lactd
sleep 2

# --- Verify ---
header "Verification"

if systemctl is-active --quiet lactd; then
    ok "LACT daemon is running"
else
    err "LACT daemon failed to start. Check: sudo journalctl -u lactd -n 30"
fi

log "Active profiles in LACT:"
lact cli profile list 2>/dev/null || echo "  (CLI unavailable, check /etc/lact/config.yaml manually)"

CURRENT_VOLT=$(lact cli get voltage_offset 2>/dev/null || echo "N/A")
log "Current voltage offset: $CURRENT_VOLT"

echo ""
ok "Setup complete!"
echo ""
echo "What next?"
echo "  1. Test stability: run a demanding game for 30+ minutes"
echo "  2. Monitor with: watch -n 1 'lact cli stats'"
echo "  3. If unstable, try a less aggressive undervolt (smaller magnitude)"
echo "  4. Forza Horizon 6 will auto-switch to the FH6 profile on launch"
echo ""
echo "To see active profiles:  lact cli profile list"
echo "To switch manually:      lact cli profile switch <name>"
echo "To restore backup:       sudo cp ${BACKUP:-/etc/lact/config.yaml.backup*} /etc/lact/config.yaml && sudo systemctl restart lactd"
