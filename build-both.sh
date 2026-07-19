#!/usr/bin/env bash
#
# DebCraft — Build BOTH ISOs (NVIDIA + Non-NVIDIA)
# This is the only script you need to run for a complete build.
#
# Usage:
#   sudo ./build-both.sh          # Build both variants
#   sudo ./build-both.sh --clean  # Clean everything first
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(readlink -f "${BASH_SOURCE[0]}")" && pwd)"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║     DebCraft Dual-ISO Builder                 ║"
echo "  ║     Building NVIDIA + Non-NVIDIA variants     ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root."
    echo "  Usage: sudo ./build-both.sh [--clean]"
    exit 1
fi

CLEAN=false
[[ "${1:-}" == "--clean" ]] && CLEAN=true

TOTAL_START=$(date +%s)

# ── Build 1: Non-NVIDIA ISO ──────────────────────────────────
echo -e "\n${CYAN}${BOLD}━━━ [1/2] Building NON-NVIDIA ISO ━━━${NC}\n"
if [[ "$CLEAN" == true ]]; then
    "${SCRIPT_DIR}/build.sh" --clean --no-nvidia
else
    "${SCRIPT_DIR}/build.sh" --no-nvidia
fi

# Rename work dir so the second build starts fresh
mv "${SCRIPT_DIR}/work" "${SCRIPT_DIR}/work-nonvidia" 2>/dev/null || true

# ── Build 2: NVIDIA ISO ──────────────────────────────────────
echo -e "\n${CYAN}${BOLD}━━━ [2/2] Building NVIDIA ISO ━━━${NC}\n"
"${SCRIPT_DIR}/build.sh" --nvidia

# ── Summary ───────────────────────────────────────────────────
TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))
TM=$((TOTAL_ELAPSED / 60))
TS=$((TOTAL_ELAPSED % 60))

echo -e "\n${GREEN}${BOLD}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║       Both ISOs Built Successfully!           ║"
echo "  ╠═══════════════════════════════════════════════╣"
echo "  ║                                               ║"
echo "  ║  output/debcraft-1.0.0-amd64.iso              ║"
echo "  ║    -> No NVIDIA drivers (smaller ISO)         ║"
echo "  ║                                               ║"
echo "  ║  output/debcraft-1.0.0-amd64-nvidia.iso       ║"
echo "  ║    -> Full NVIDIA driver stack                ║"
echo "  ║                                               ║"
echo "  ║  Total time: ${TM}m ${TS}s                         ║"
echo "  ║  Flash with: dd or BalenaEtcher               ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# Clean up intermediate work directories to save disk space
echo -e "${CYAN}[INFO]${NC}  Cleaning up intermediate build directories..."
rm -rf "${SCRIPT_DIR}/work-nonvidia" 2>/dev/null || true
rm -rf "${SCRIPT_DIR}/work" 2>/dev/null || true
echo -e "${GREEN}[OK]${NC}    Done!"