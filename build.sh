#!/usr/bin/env bash
#
# DebCraft — Debian-based Distro ISO Builder
# A minimal, Archcraft-inspired Debian distribution
#
# Usage:
#   sudo ./build.sh              # Build with NVIDIA (default)
#   sudo ./build.sh --no-nvidia  # Build without NVIDIA
#   sudo ./build.sh --clean      # Clean first, then build
#   sudo ./build.sh --help       # Show usage
#
set -euo pipefail

# =============================================================================
# Variables
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_NAME="debcraft"
DISTRO_NAME="DebCraft"
VERSION="1.0.0"
DEBIAN_CODENAME="bookworm"
DEBIAN_MIRROR="http://deb.debian.org/debian"
ARCHITECTURE="amd64"
WORK_DIR="${SCRIPT_DIR}/work"
ISO_DIR="${SCRIPT_DIR}/output"
CHROOT_DIR="${WORK_DIR}/chroot"
CLEAN_BUILD=false
INCLUDE_NVIDIA=true

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# =============================================================================
# Logging
# =============================================================================
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${CYAN}${BOLD}==== $* ====${NC}"; }

# =============================================================================
# Argument parsing
# =============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root."
        echo "  Usage: sudo ./build.sh [options]"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --clean)     CLEAN_BUILD=true;  shift ;;
            --no-nvidia) INCLUDE_NVIDIA=false; shift ;;
            --nvidia)    INCLUDE_NVIDIA=true;  shift ;;
            --help|-h)
                echo "DebCraft ISO Builder v${VERSION}"
                echo ""
                echo "Usage: sudo ./build.sh [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --nvidia      Build with NVIDIA drivers (default)"
                echo "  --no-nvidia   Build without NVIDIA drivers"
                echo "  --clean       Clean previous build artifacts before starting"
                echo "  --help, -h    Show this help message"
                echo ""
                echo "Output: output/debcraft-${VERSION}-amd64[-nvidia].iso"
                exit 0 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done
}

# =============================================================================
# Dependency check
# =============================================================================
check_deps() {
    log_step "Stage 0: Checking build dependencies"

    local missing=()
    local tools=(debootstrap mksquashfs xorriso grub-mkimage)

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_info "Installing missing build tools: ${missing[*]}"
        apt-get update -qq
        apt-get install -y -qq debootstrap squashfs-tools xorriso \
            isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin \
            dosfstools pigz 2>/dev/null || true
    fi

    # Verify critical files exist
    local critical_files=(
        "packages/base.list"
        "packages/desktop.list"
        "packages/theming.list"
        "config/bspwm/bspwmrc"
        "config/sxhkd/sxhkdrc"
        "config/polybar/config.ini"
        "config/polybar/launch.sh"
        "config/picom/picom.conf"
        "config/rofi/launchers/type-1/launcher.rasi"
        "config/alacritty/alacritty.toml"
        "config/dunst/dunstrc"
        "config/gtk-3.0/settings.ini"
        "config/gtk-4.0/settings.ini"
        "config/starship/starship.toml"
        "chroot/setup-desktop.sh"
        "installer/settings.conf"
        "installer/branding/debcraft.branding"
    )

    local missing_files=()
    for f in "${critical_files[@]}"; do
        if [[ ! -f "${SCRIPT_DIR}/${f}" ]]; then
            missing_files+=("$f")
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing critical project files:"
        for f in "${missing_files[@]}"; do
            echo "  - ${f}"
        done
        exit 1
    fi

    log_success "Build dependencies and project files verified"
}

# =============================================================================
# Cleanup
# =============================================================================
clean_build() {
    log_step "Cleaning previous build artifacts"

    # Unmount anything still mounted from a previous run
    for mp in tmp sys proc dev/pts dev; do
        umount "${CHROOT_DIR}/${mp}" 2>/dev/null || true
    done

    # Remove work and output directories
    rm -rf "${WORK_DIR}" "${ISO_DIR}"

    log_success "Clean complete"
}

# =============================================================================
# Helper: Install packages from a list file inside chroot
# =============================================================================
install_pkg_list_from_file() {
    local listfile="$1"
    if [[ ! -f "$listfile" ]]; then
        log_warn "Package list not found: $listfile"
        return 0
    fi

    local pkgs
    pkgs=$(grep -vE '^\s*#|^\s*$' "$listfile" | tr '\n' ' ')
    if [[ -z "$pkgs" ]]; then
        return 0
    fi

    log_info "Installing from $(basename "$listfile")..."
    # Install with --no-install-recommends; allow individual failures
    apt-get install -y --no-install-recommends $pkgs 2>&1 | \
        grep -E "Setting up|already the newest" | tail -5 || true
}

###############################################################################
# Stage 1: Bootstrap Debian
###############################################################################
stage_bootstrap() {
    log_step "Stage 1: Bootstrapping Debian ${DEBIAN_CODENAME}"

    mkdir -p "${CHROOT_DIR}"

    debootstrap --arch="${ARCHITECTURE}" --variant=minbase \
        "${DEBIAN_CODENAME}" "${CHROOT_DIR}" "${DEBIAN_MIRROR}"

    log_success "Bootstrap complete"
}

###############################################################################
# Stage 2: Configure chroot environment
###############################################################################
stage_configure_chroot() {
    log_step "Stage 2: Configuring chroot environment"

    # --- APT sources ---
    # Main repos with non-free for firmware and NVIDIA
    cat > "${CHROOT_DIR}/etc/apt/sources.list" << 'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
EOF

    # Backports for Calamares installer
    cat > "${CHROOT_DIR}/etc/apt/sources.list.d/backports.list" << 'EOF'
deb http://deb.debian.org/debian bookworm-backports main contrib non-free
EOF

    # --- DNS ---
    cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"

    # --- Mount virtual filesystems ---
    mount --bind /dev     "${CHROOT_DIR}/dev"
    mount --bind /dev/pts "${CHROOT_DIR}/dev/pts"
    mount -t proc proc    "${CHROOT_DIR}/proc"
    mount -t sysfs sysfs  "${CHROOT_DIR}/sys"

    log_success "Chroot configured"
}

###############################################################################
# Stage 3: Install packages inside chroot
###############################################################################
stage_install_packages() {
    log_step "Stage 3: Installing packages"

    # Copy package lists into chroot
    cp "${SCRIPT_DIR}/packages/base.list"    "${CHROOT_DIR}/tmp/"
    cp "${SCRIPT_DIR}/packages/desktop.list"  "${CHROOT_DIR}/tmp/"
    cp "${SCRIPT_DIR}/packages/theming.list"  "${CHROOT_DIR}/tmp/"

    # Install packages inside chroot
    chroot "${CHROOT_DIR}" /bin/bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq

        install_list() {
            local listfile="$1"
            local pkgs
            pkgs=$(grep -vE "^\s*#|^\s*$" "$listfile" | tr "\n" " ")
            if [ -n "$pkgs" ]; then
                echo "  -> Installing from $(basename "$listfile")..."
                apt-get install -y --no-install-recommends $pkgs 2>&1 | tail -3 || true
            fi
        }

        install_list /tmp/base.list
        install_list /tmp/desktop.list
        install_list /tmp/theming.list
    '

    # NVIDIA packages (if requested)
    if [[ "${INCLUDE_NVIDIA}" == true ]]; then
        log_info "Installing NVIDIA driver packages..."
        cp "${SCRIPT_DIR}/packages/nvidia.list" "${CHROOT_DIR}/tmp/"
        chroot "${CHROOT_DIR}" /bin/bash -c '
            export DEBIAN_FRONTEND=noninteractive
            grep -vE "^\s*#|^\s*$" /tmp/nvidia.list | tr "\n" " " | \
                xargs apt-get install -y --no-install-recommends 2>&1 | tail -5 || true
        '
    fi

    # --- Install tools NOT in Debian repos ---
    log_info "Installing fastfetch, starship, eza from upstream..."

    chroot "${CHROOT_DIR}" /bin/bash -c '
        set -e
        export DEBIAN_FRONTEND=noninteractive

        # fastfetch — prebuilt binary from GitHub releases
        if ! command -v fastfetch &>/dev/null; then
            echo "  -> Installing fastfetch..."
            ARCH=$(uname -m)
            FASTFETCH_VER="2.8.0"
            case "$ARCH" in
                x86_64) FASTFETCH_ARCH="x86_64" ;;
                aarch64) FASTFETCH_ARCH="aarch64" ;;
                *) echo "  -> Unsupported arch for fastfetch: $ARCH"; exit 0 ;;
            esac
            curl -sL "https://github.com/fastfetch-cli/fastfetch/releases/download/${FASTFETCH_VER}/fastfetch-linux-${FASTFETCH_ARCH}.tar.gz" | \
                tar xz -C /tmp/
            if [[ -f "/tmp/fastfetch/usr/bin/fastfetch" ]]; then
                cp /tmp/fastfetch/usr/bin/fastfetch /usr/local/bin/
                chmod +x /usr/local/bin/fastfetch
                echo "  -> fastfetch installed"
            fi
            rm -rf /tmp/fastfetch
        fi

        # starship — prebuilt binary
        if ! command -v starship &>/dev/null; then
            echo "  -> Installing starship..."
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64) STARSHIP_ARCH="x86_64-unknown-linux-gnu" ;;
                aarch64) STARSHIP_ARCH="aarch64-unknown-linux-gnu" ;;
                *) echo "  -> Unsupported arch for starship: $ARCH"; exit 0 ;;
            esac
            curl -sSfL "https://starship.rs/install.sh" | sh -s -- -y -b /usr/local/bin 2>/dev/null || {
                # Fallback: direct binary download
                curl -sL "https://github.com/starship/starship/releases/latest/download/starship-${STARSHIP_ARCH}.tar.gz" | \
                    tar xz -C /usr/local/bin/
            }
            echo "  -> starship installed"
        fi

        # eza — modern ls replacement
        if ! command -v eza &>/dev/null; then
            echo "  -> Installing eza..."
            ARCH=$(uname -m)
            case "$ARCH" in
                x86_64) EZA_ARCH="x86_64-unknown-linux-musl" ;;
                aarch64) EZA_ARCH="aarch64-unknown-linux-musl" ;;
                *) echo "  -> Unsupported arch for eza: $ARCH"; exit 0 ;;
            esac
            curl -sL "https://github.com/eza-community/eza/releases/latest/download/eza_${EZA_ARCH}.tar.gz" | \
                tar xz -C /usr/local/bin/
            echo "  -> eza installed"
        fi

        # cbatticon — battery indicator
        apt-get install -y --no-install-recommends cbatticon 2>/dev/null || true
    '

    # --- Install Catppuccin GTK theme from source ---
    log_info "Installing Catppuccin GTK theme..."
    chroot "${CHROOT_DIR}" /bin/bash -c '
        if ! dpkg -l | grep -q catppuccin-gtk-theme 2>/dev/null; then
            mkdir -p /tmp/catppuccin-build
            cd /tmp/catppuccin-build
            apt-get install -y -qq git sassc optipng 2>/dev/null || true
            git clone --depth 1 https://github.com/catppuccin/gtk.git 2>/dev/null || true
            if [[ -d gtk ]]; then
                cd gtk
                ./install.sh -d -c mocha 2>/dev/null || true
            fi
            cd /
            rm -rf /tmp/catppuccin-build
        fi
    '

    log_success "All packages installed"
}

###############################################################################
# Stage 4: Desktop environment setup
###############################################################################
stage_setup_desktop() {
    log_step "Stage 4: Setting up desktop environment"

    # Copy all config files and chroot scripts
    mkdir -p "${CHROOT_DIR}/tmp/config" "${CHROOT_DIR}/tmp/assets"
    cp -r "${SCRIPT_DIR}/config/"*  "${CHROOT_DIR}/tmp/config/"
    cp -r "${SCRIPT_DIR}/assets/"*  "${CHROOT_DIR}/tmp/assets/" 2>/dev/null || true

    cp "${SCRIPT_DIR}/chroot/setup-desktop.sh" "${CHROOT_DIR}/tmp/setup-desktop.sh"
    chmod +x "${CHROOT_DIR}/tmp/setup-desktop.sh"

    chroot "${CHROOT_DIR}" /tmp/setup-desktop.sh

    log_success "Desktop environment configured"
}

###############################################################################
# Stage 5: NVIDIA configuration
###############################################################################
stage_setup_nvidia() {
    if [[ "${INCLUDE_NVIDIA}" != true ]]; then
        log_info "Stage 5: Skipping NVIDIA configuration (--no-nvidia)"
        return
    fi

    log_step "Stage 5: Configuring NVIDIA drivers"

    cp "${SCRIPT_DIR}/chroot/install-nvidia.sh" "${CHROOT_DIR}/tmp/install-nvidia.sh"
    chmod +x "${CHROOT_DIR}/tmp/install-nvidia.sh"
    chroot "${CHROOT_DIR}" /tmp/install-nvidia.sh

    log_success "NVIDIA configured"
}

###############################################################################
# Stage 6: Calamares installer setup
###############################################################################
stage_setup_installer() {
    log_step "Stage 6: Configuring Calamares installer"

    # Install Calamares from backports if not already installed
    chroot "${CHROOT_DIR}" /bin/bash -c '
        export DEBIAN_FRONTEND=noninteractive
        if ! command -v calamares &>/dev/null; then
            apt-get install -y -t bookworm-backports calamares 2>/dev/null || true
        fi
    '

    # Copy Calamares configuration
    mkdir -p "${CHROOT_DIR}/etc/calamares"
    mkdir -p "${CHROOT_DIR}/usr/share/calamares/modules"
    mkdir -p "${CHROOT_DIR}/usr/share/calamares/branding/debcraft"

    cp "${SCRIPT_DIR}/installer/settings.conf"                    "${CHROOT_DIR}/etc/calamares/"
    cp "${SCRIPT_DIR}/installer/branding/debcraft.branding"       "${CHROOT_DIR}/etc/calamares/branding/debcraft/branding.desc"
    cp "${SCRIPT_DIR}/installer/modules/"*                        "${CHROOT_DIR}/usr/share/calamares/modules/"

    # Create installer desktop shortcut for the live session
    mkdir -p "${CHROOT_DIR}/home/live/Desktop"
    cat > "${CHROOT_DIR}/home/live/Desktop/install-debcraft.desktop" << 'EOF'
[Desktop Entry]
Name=Install DebCraft
Comment=Install DebCraft to your system
Exec=pkexec calamares
Icon=system-software-install
Terminal=false
Type=Application
Categories=System;
EOF

    log_success "Calamares installer configured"
}

###############################################################################
# Stage 7: Finalize chroot
###############################################################################
stage_finalize() {
    log_step "Stage 7: Finalizing chroot"

    # --- Create live user ---
    chroot "${CHROOT_DIR}" groupadd -r autologin 2>/dev/null || true
    chroot "${CHROOT_DIR}" useradd -m -s /bin/bash \
        -G sudo,audio,video,plugdev,netdev,cdrom,autologin live 2>/dev/null || true
    echo "live:live" | chroot "${CHROOT_DIR}" chpasswd

    # --- SDDM auto-login for live session ---
    mkdir -p "${CHROOT_DIR}/etc/sddm.conf.d"
    cat > "${CHROOT_DIR}/etc/sddm.conf.d/autologin.conf" << 'EOF'
[Autologin]
User=live
Session=bspwm

[General]
Numlock=on
EOF

    # --- Hostname ---
    echo "debcraft-live" > "${CHROOT_DIR}/etc/hostname"
    cat > "${CHROOT_DIR}/etc/hosts" << 'EOF'
127.0.0.1   localhost debcraft-live
::1         localhost ip6-localhost ip6-loopback
EOF

    # --- Locale ---
    chroot "${CHROOT_DIR}" sed -i 's/^# *en_US\.UTF-8/en_US.UTF-8/' /etc/locale.gen
    chroot "${CHROOT_DIR}" locale-gen en_US.UTF-8
    chroot "${CHROOT_DIR}" update-locale LANG=en_US.UTF-8

    # --- Enable essential services ---
    chroot "${CHROOT_DIR}" systemctl enable NetworkManager sddm dbus bluetooth 2>/dev/null || true

    # --- Copy configs to /etc/skel for the installer to use on new users ---
    cp -r "${CHROOT_DIR}/home/live/.config"   "${CHROOT_DIR}/etc/skel/" 2>/dev/null || true
    cp "${CHROOT_DIR}/home/live/.zshrc"       "${CHROOT_DIR}/etc/skel/"  2>/dev/null || true
    cp "${CHROOT_DIR}/home/live/.bashrc"      "${CHROOT_DIR}/etc/skel/"  2>/dev/null || true
    cp "${CHROOT_DIR}/home/live/.xinitrc"     "${CHROOT_DIR}/etc/skel/"  2>/dev/null || true
    cp "${CHROOT_DIR}/home/live/.xprofile"    "${CHROOT_DIR}/etc/skel/"  2>/dev/null || true
    cp "${CHROOT_DIR}/home/live/.Xresources"  "${CHROOT_DIR}/etc/skel/"  2>/dev/null || true
    chown -R root:root "${CHROOT_DIR}/etc/skel" 2>/dev/null || true

    # --- Generate GRUB theme ---
    chroot "${CHROOT_DIR}" /bin/bash -c '
        GRUB_THEME_DIR="/boot/grub/themes/debcraft"
        mkdir -p "$GRUB_THEME_DIR"
        cat > "$GRUB_THEME_DIR/theme.txt" << "GRUBEOF"
title-font: "DejaVu Sans Bold 16"
title-color: "#cdd6f4"
message-font: "DejaVu Sans 14"
message-color: "#cdd6f4"
message-bg-color: "#1e1e2e"
desktop-color: "#1e1e2e"
desktop-image: ""
menu-color-normal: "#cdd6f4"
menu-color-highlight: "#1e1e2e"
menu-bg-color: "#1e1e2e"
menu-border-color: "#313244"
menu-border-width: 2
item-color: "#cdd6f4"
item-selected-color: "#1e1e2e"
item-font: "DejaVu Sans 14"
item-selected-font: "DejaVu Sans Bold 14"
item-selected-bg-color: "#89b4fa"
item-selected-fg-color: "#1e1e2e"
item-height: 36
item-padding: 8
item-icon-width: 40
item-spacing: 12
scrollbar-color: "#313244"
scrollbar-thumb-color: "#89b4fa"
scrollbar-width: 12
progress-bar-color: "#89b4fa"
progress-bar-bg-color: "#313244"
progress-bar-border-color: "#313244"
progress-bar-height: 8
progress-bar-pad: 0
boot-menu-width: 500
boot-menu-height: 400
boot-menu-left: 50%-250
boot-menu-top: 50%-200
terminal-border-color: "#313244"
terminal-font: "DejaVu Sans Mono 14"
label-color: "#89b4fa"
label-bg-color: "transparent"
GRUBEOF

        # Set GRUB theme in default config
        if [[ -f /etc/default/grub ]]; then
            sed -i "/^GRUB_THEME=/d" /etc/default/grub
            echo "GRUB_THEME=\"${GRUB_THEME_DIR}/theme.txt\"" >> /etc/default/grub
            echo "GRUB_TIMEOUT=5" >> /etc/default/grub
            echo "GRUB_DISTRIBUTOR=\"DebCraft\"" >> /etc/default/grub
        fi
    '

    # --- Cleanup chroot ---
    log_info "Cleaning chroot..."
    chroot "${CHROOT_DIR}" apt-get clean
    chroot "${CHROOT_DIR}" apt-get autoremove -y 2>/dev/null || true
    rm -rf "${CHROOT_DIR}"/var/cache/apt/archives/*.deb
    rm -rf "${CHROOT_DIR}"/tmp/*
    rm -rf "${CHROOT_DIR}"/var/tmp/*
    rm -rf "${CHROOT_DIR}"/root/.cache
    rm -rf "${CHROOT_DIR}"/home/live/.cache
    rm -f  "${CHROOT_DIR}"/etc/resolv.conf

    log_success "Chroot finalized"
}

###############################################################################
# Stage 8: Build ISO image
###############################################################################
stage_build_iso() {
    log_step "Stage 8: Building ISO image"

    # --- Unmount virtual filesystems ---
    for mp in tmp sys proc dev/pts dev; do
        umount "${CHROOT_DIR}/${mp}" 2>/dev/null || true
    done

    # --- Auto-detect kernel version ---
    local kernel_version
    kernel_version=$(basename "$(ls -d "${CHROOT_DIR}"/boot/vmlinuz-* 2>/dev/null | head -1)" | sed 's/vmlinuz-//')
    if [[ -z "$kernel_version" ]]; then
        log_error "No kernel found in chroot /boot/. Installation may have failed."
        exit 1
    fi
    log_info "Detected kernel: ${kernel_version}"

    # --- Create squashfs ---
    log_info "Creating squashfs filesystem..."
    mkdir -p "${WORK_DIR}/iso/live"
    mksquashfs "${CHROOT_DIR}" "${WORK_DIR}/iso/live/filesystem.squashfs" \
        -comp xz -b 1M -Xbcj x86 -no-progress
    log_info "Squashfs size: $(du -h "${WORK_DIR}/iso/live/filesystem.squashfs" | cut -f1)"

    # --- Copy kernel and initrd ---
    cp "${CHROOT_DIR}/boot/vmlinuz-${kernel_version}"    "${WORK_DIR}/iso/live/vmlinuz"
    cp "${CHROOT_DIR}/boot/initrd.img-${kernel_version}"  "${WORK_DIR}/iso/live/initrd"

    # =========================================================================
    # UEFI GRUB configuration
    # =========================================================================
    mkdir -p "${WORK_DIR}/iso/efi/boot"

    cat > "${WORK_DIR}/iso/efi/boot/grub.cfg" << EOF
set default="0"
set timeout=10

menuentry "${DISTRO_NAME} ${VERSION} (Live)" {
    linux /live/vmlinuz boot=live quiet splash
    initrd /live/initrd
}

menuentry "${DISTRO_NAME} ${VERSION} (Live, Safe Graphics)" {
    linux /live/vmlinuz boot=live nomodeset
    initrd /live/initrd
}
EOF

    # =========================================================================
    # BIOS ISOLINUX configuration
    # =========================================================================
    mkdir -p "${WORK_DIR}/iso/isolinux"
    cp /usr/lib/ISOLINUX/isolinux.bin                      "${WORK_DIR}/iso/isolinux/" 2>/dev/null || true
    cp /usr/lib/syslinux/modules/bios/ldlinux.c32          "${WORK_DIR}/iso/isolinux/" 2>/dev/null || true
    cp /usr/lib/syslinux/modules/bios/libcom32.c32         "${WORK_DIR}/iso/isolinux/" 2>/dev/null || true
    cp /usr/lib/syslinux/modules/bios/libutil.c32          "${WORK_DIR}/iso/isolinux/" 2>/dev/null || true

    cat > "${WORK_DIR}/iso/isolinux/isolinux.cfg" << EOF
DEFAULT debcraft
TIMEOUT 100
PROMPT 0

LABEL debcraft
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd boot=live quiet splash
    MENU LABEL ${DISTRO_NAME} ${VERSION} (Live)

LABEL safe
    KERNEL /live/vmlinuz
    APPEND initrd=/live/initrd boot=live nomodeset
    MENU LABEL ${DISTRO_NAME} (Safe Graphics)
EOF

    # --- Build EFI GRUB boot image ---
    log_info "Creating GRUB EFI boot image..."
    grub-mkimage -O x86_64-efi \
        -o "${WORK_DIR}/iso/efi/boot/bootx64.efi" \
        -p "/efi/boot" \
        boot linux normal configfile part_gpt fat iso9660 search

    # --- Assemble the hybrid ISO ---
    log_info "Assembling hybrid UEFI+BIOS ISO..."
    mkdir -p "${ISO_DIR}"

    local nvidia_suffix=""
    [[ "${INCLUDE_NVIDIA}" == true ]] && nvidia_suffix="-nvidia"

    xorriso -as mkisofs \
        -o "${ISO_DIR}/${PROJECT_NAME}-${VERSION}-amd64${nvidia_suffix}.iso" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e /efi/boot/bootx64.efi \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -partition_offset 16 \
        -V "DEBCRAFT_LIVE" \
        "${WORK_DIR}/iso/"

    local iso_size
    iso_size=$(du -h "${ISO_DIR}/${PROJECT_NAME}-${VERSION}-amd64${nvidia_suffix}.iso" | cut -f1)
    log_success "ISO created: ${PROJECT_NAME}-${VERSION}-amd64${nvidia_suffix}.iso (${iso_size})"
}

###############################################################################
# Stage 9: Generate checksums
###############################################################################
stage_checksums() {
    log_step "Stage 9: Generating checksums"

    local nvidia_suffix=""
    [[ "${INCLUDE_NVIDIA}" == true ]] && nvidia_suffix="-nvidia"

    cd "${ISO_DIR}"
    sha256sum "${PROJECT_NAME}-${VERSION}-amd64${nvidia_suffix}.iso" \
        > "${PROJECT_NAME}-${VERSION}-amd64${nvidia_suffix}.iso.sha256"

    log_success "SHA256 checksum saved"
}

###############################################################################
# Main
###############################################################################
main() {
    echo -e "${CYAN}${BOLD}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║       DebCraft ISO Builder v${VERSION}       ║"
    echo "  ║  Debian ${DEBIAN_CODENAME} + Archcraft Aesthetic    ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    check_root
    parse_args "$@"
    check_deps

    if [[ "${CLEAN_BUILD}" == true ]]; then
        clean_build
    fi

    local t0
    t0=$(date +%s)

    stage_bootstrap
    stage_configure_chroot
    stage_install_packages
    stage_setup_desktop
    stage_setup_nvidia
    stage_setup_installer
    stage_finalize
    stage_build_iso
    stage_checksums

    local t1 elapsed m s
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    m=$((elapsed / 60))
    s=$((elapsed % 60))

    local nvidia_suffix=""
    [[ "${INCLUDE_NVIDIA}" == true ]] && nvidia_suffix="-nvidia"

    echo -e "\n${GREEN}${BOLD}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║         Build Complete!                 ║"
    echo "  ║                                        ║"
    echo "  ║  ${PROJECT_NAME}-${VERSION}-amd64${nvidia_suffix}.iso"
    echo "  ║  Time: ${m}m ${s}s                        ║"
    echo "  ║  NVIDIA: ${INCLUDE_NVIDIA}                          ║"
    echo "  ║                                        ║"
    echo "  ║  Flash with: dd or BalenaEtcher       ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

main "$@"