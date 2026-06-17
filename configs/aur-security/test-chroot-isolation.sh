#!/bin/bash
# Chroot Isolation Test
# Tests that paru's --chroot properly contains malicious build-time payloads
# while documenting that .install scripts still run on the host.
#
# Usage:
#   ./test-chroot-isolation.sh    # Full test
#   ./test-chroot-isolation.sh    # Just verify setup
#
# Requires: paru, devtools (makepkg chroot support)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}⚠${NC}"

log()   { echo -e "${BLUE}[TEST]${NC} $1"; }
pass()  { echo -e "  ${PASS} $1"; }
fail()  { echo -e "  ${FAIL} $1"; }
warn()  { echo -e "  ${WARN} $1"; }
header() { echo -e "\n${BOLD}=== $1 ===${NC}\n"; }

cleanup() {
  sudo rm -rf /tmp/aur-test-chroot /tmp/chroot-aur-test-*.txt 2>/dev/null || true
  sudo pacman -R --noconfirm aur-test-chroot 2>/dev/null || true
  sudo rm -f /var/lib/aurbuild/repo/aur-test-chroot*.pkg.tar.zst 2>/dev/null || true
}

check_deps() {
  local missing=false
  for cmd in paru mkarchroot; do
    if ! command -v "$cmd" &>/dev/null; then
      fail "$cmd not found"
      missing=true
    fi
  done
  if ! grep -q '^\[aurbuild\]' /etc/pacman.conf 2>/dev/null; then
    fail "aurbuild repo not in /etc/pacman.conf — run secure-aur.sh first"
    missing=true
  fi
  if ! grep -q '^LocalRepo' ~/.config/paru/paru.conf 2>/dev/null; then
    fail "LocalRepo not in paru.conf — run secure-aur.sh first"
    missing=true
  fi
  if $missing; then
    echo "Run: ./configs/aur-security/secure-aur.sh"
    exit 1
  fi
  pass "All dependencies met"
}

create_test_pkg() {
  local dir="/tmp/aur-test-chroot"
  mkdir -p "$dir"

  cat > "$dir/PKGBUILD" << 'PKG'
pkgname=aur-test-chroot
pkgver=1.0
pkgrel=1
pkgdesc="Chroot isolation test package"
arch=('any')
license=('GPL')
install=aur-test-chroot.install
source=()
sha256sums=()

build() {
  echo "=== BUILD PHASE ==="
  echo "hostname: $(cat /etc/hostname 2>/dev/null || echo unknown)"
  if [ -d /home/ales ]; then
    echo "HOST_ACCESS: /home/ales IS accessible"
  else
    echo "HOST_ACCESS: /home/ales NOT accessible"
  fi
  if head -1 /etc/shadow 2>/dev/null | grep -q root; then
    echo "HOST_ACCESS: /etc/shadow IS readable"
  else
    echo "HOST_ACCESS: /etc/shadow NOT readable"
  fi
  if echo "build-marker" > /tmp/chroot-aur-test-build.txt 2>/dev/null; then
    echo "TMP_WRITE: /tmp/ writable"
  fi
}

package() {
  mkdir -p "$pkgdir/usr/share/aur-test-chroot"
  echo "Package built: $(date)" > "$pkgdir/usr/share/aur-test-chroot/README"
}
PKG

  cat > "$dir/aur-test-chroot.install" << 'INST'
post_install() {
  echo "=== INSTALL PHASE ==="
  echo "whoami: $(whoami)"
  echo "home: $HOME"
  if head -1 /etc/shadow 2>/dev/null | grep -q root; then
    echo "HOST_ACCESS: /etc/shadow IS readable"
  fi
  if echo "install-marker" > /tmp/chroot-aur-test-install.txt 2>/dev/null; then
    echo "TMP_WRITE: /tmp/ writable"
  fi
}
INST

  echo "$dir"
}

run_test() {
  local dir="$1"
  local results_file="/tmp/aur-test-output.txt"
  local results_file2="/tmp/aur-test-output2.txt"

  # Clean markers
  rm -f /tmp/chroot-aur-test-build.txt /tmp/chroot-aur-test-install.txt

  header "Test 1: Chroot build isolation"
  log "Building $dir/PKGBUILD inside chroot..."

  cd "$dir"
  # Build in chroot, capturing output
  paru -B --chroot . 2>&1 | tee "$results_file" || true
  cd >/dev/null

  header "Test 2: Host install isolation (install script)"
  log "Installing from local repo to test .install script..."
  sudo pacman -S --noconfirm aurbuild/aur-test-chroot 2>&1 | tee "$results_file2" || true

  echo ""
  header "RESULTS"

  local build_on_host=false
  local install_on_host=false

  if [ ! -f /tmp/chroot-aur-test-build.txt ]; then
    pass "Build-time file NOT on host (contained in chroot)"
  else
    fail "Build-time file FOUND on host — ESCAPED"
    build_on_host=true
  fi

  if [ -f /tmp/chroot-aur-test-install.txt ]; then
    warn "Install-time file on host (expected — .install runs on host)"
    install_on_host=true
  else
    fail "Install-time file NOT found (unexpected)"
  fi

  echo ""
  if $build_on_host; then
    fail "${BOLD}BUILD ISOLATION FAILED${NC} — chroot is not working"
    return 1
  elif $install_on_host; then
    pass "Build-time: CONTAINED in chroot"
    warn "Install-time: runs on host — review PKGBUILD diffs!"
    echo ""
    echo "Summary:"
    echo "  build()/package()  → runs in chroot  → CONTAINED"
    echo "  .install scripts   → runs on host    → MUST REVIEW"
    return 0
  fi
}

main() {
  echo ""
  echo "${BOLD}AUR Chroot Isolation Test${NC}"
  echo "Tests that paru's chroot protects against malicious build scripts."
  echo ""

  check_deps
  cleanup

  local dir
  dir=$(create_test_pkg)
  run_test "$dir"

  echo ""
  log "Cleaning up..."
  cleanup

  echo ""
  echo "${BOLD}Done.${NC}"
  echo "See docs/aur-security.md for full explanation."
}

main "$@"
