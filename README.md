# mydebianbuild

A Debian-based Linux distribution with the minimalist, aesthetic look , full **NVIDIA driver** support, and a **Calamares graphical installer**.

Built on **Debian 12 (Bookworm)** with `bspwm`, `polybar`, `picom`, and a carefully curated Catppuccin Mocha dark theme throughout.

---

## Features

| Feature | Details |
|---------|---------|
| **Base** | Debian 12 (Bookworm) — stable, reliable |
| **Window Manager** | bspwm (binary space partitioning) + sxhkd |
| **Status Bar** | Polybar with Catppuccin Mocha colors |
| **Compositor** | Picom with dual-kawase blur and rounded shadows |
| **Launcher** | Rofi (drun, run, window, power menu) |
| **Terminal** | Alacritty (Catppuccin Mocha, Nerd Fonts) |
| **Theme** | Catppuccin Mocha everywhere (GTK 3/4, Alacritty, Polybar, Rofi, Dunst, Starship) |
| **Icons** | Papirus Dark |
| **Cursor** | Breeze |
| **Shell** | Zsh + Starship prompt |
| **Display Manager** | SDDM with auto-login for live session |
| **Installer** | Calamares graphical installer |
| **NVIDIA** | Full proprietary driver stack (driver, CUDA, Vulkan, NVENC) |
| **Bootloader** | GRUB with EFI + BIOS (hybrid ISO) support |
| **Notifications** | Dunst |
| **Screenshots** | Flameshot |
| **Dock** | Plank |
| **File Manager** | Thunar |
| **Browser** | Firefox ESR |
| **Office** | LibreOffice (Writer, Calc, Impress, Draw) |

---

## Project Structure

```
debcraft/
├── docker-build.sh                   # ONE COMMAND: builds both ISOs via Docker
├── Dockerfile                        # Docker build environment
├── docker-entrypoint.sh              # Docker: orchestrates both builds
├── build-inner.sh                    # Actual build logic (used by all methods)
├── build.sh                          # Original native build script
├── build-vagrant.sh                  # Vagrant VM build script
├── Vagrantfile                       # Vagrant VM definition
├── packages/
│   ├── base.list                     # Core Debian system packages
│   ├── desktop.list                  # Desktop environment packages (bspwm, polybar, etc.)
│   ├── nvidia.list                   # NVIDIA driver packages
│   └── theming.list                  # Theme/icon/cursor packages
├── config/
│   ├── bspwm/bspwmrc                 # Window manager configuration
│   ├── sxhkd/sxhkdrc                 # Keyboard shortcuts
│   ├── polybar/
│   │   ├── config.ini                # Status bar configuration
│   │   └── launch.sh                 # Polybar multi-monitor launcher
│   ├── picom/picom.conf              # Compositor (blur, shadows, opacity)
│   ├── rofi/
│   │   ├── launchers/type-1/launcher.rasi   # Application launcher theme
│   │   └── powermenu/powermenu.sh          # Power menu script
│   ├── alacritty/alacritty.toml      # Terminal emulator config
│   ├── dunst/dunstrc                 # Notification daemon config
│   ├── gtk-3.0/settings.ini          # GTK 3 theme settings
│   ├── gtk-4.0/settings.ini          # GTK 4 theme settings
│   ├── conky/                        # System monitor (placeholder)
│   └── starship/starship.toml        # Shell prompt configuration
├── chroot/
│   ├── install-packages.sh           # Package installation (runs inside chroot)
│   ├── install-nvidia.sh             # NVIDIA driver configuration
│   └── setup-desktop.sh              # Desktop environment setup & user config
├── installer/
│   ├── settings.conf                 # Calamares module sequence
│   ├── branding/debcraft.branding    # Installer visual branding
│   └── modules/
│       ├── partition.conf            # Disk partitioning
│       ├── unpackfs.conf             # Filesystem extraction
│       ├── users.conf                # User creation
│       ├── displaymanager.conf       # SDDM setup
│       ├── grubcfg.conf              # GRUB bootloader
│       ├── locale.conf               # Locale/region
│       ├── packages.conf             # Additional packages
│       ├── networkcfg.conf           # Network config
│       ├── shellprocess_preinstall.conf    # Pre-install hooks
│       ├── shellprocess_postinstall.conf   # Post-install system config
│       └── shellprocess_finalize.conf      # Final user config & cleanup
├── scripts/
│   ├── check-build-env.sh            # Verify build environment & files
│   ├── generate-grub-theme.sh        # Create GRUB theme
│   └── post-install.sh               # Configure new user on installed system
├── assets/
│   └── wallpapers/                   # Custom wallpapers (add .png/.jpg here)
└── work/                             # Build artifacts (created during build)
    └── output/                       # Final ISO output
```

---

## Prerequisites & Build Methods

You have **3 ways** to build the ISOs. Pick the one that matches your setup:

### Method 1: Docker (Recommended — works on any Linux, macOS, Windows)

Requires: Docker installed, ~20 GB disk, internet.

```bash
so you unpack the file then cd into the folder with build.sh and do
sudo bash build.sh --nvidia for nvidia
sudo bash build.sh without nvidia

```

That's it. Both ISOs appear in `output/`:
- `debcraft-1.0.0-no-nvidia-amd64.iso`
- `debcraft-1.0.0-amd64.iso` (with NVIDIA)

### Method 2: Vagrant (works on any host with VirtualBox)

Requires: Vagrant + VirtualBox.

```bash
cd debcraft
vagrant up              # Creates Debian VM with build tools
vagrant ssh -c "/vagrant/build-vagrant.sh"
# ISOs appear in ./output/
```

### Method 3: Native (on a Debian/Ubuntu machine with root)

```bash
sudo apt install -y debootstrap squashfs-tools xorriso \
    isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin \
    dosfstools pigz
cd debcraft
chmod +x build.sh scripts/*.sh chroot/*.sh config/polybar/launch.sh

# Build NO-NVIDIA ISO
sudo OVERRIDE_OUTPUT=$(pwd)/output-no-nvidia ./build-inner.sh --no-nvidia

# Build NVIDIA ISO
sudo OVERRIDE_OUTPUT=$(pwd)/output-nvidia ./build-inner.sh --nvidia
```

**Hardware requirements:**
- 20 GB+ free disk space
- 4 GB+ RAM (8 GB recommended)
- x86_64 (amd64) architecture

### Build Options

| Flag | Description |
|------|-------------|
| (default) | Full build with NVIDIA drivers |
| `--no-nvidia` | Build without NVIDIA drivers (smaller ISO) |
| `--clean` | Remove previous build artifacts before building |
| `--help` | Show all available options |

### Build Output

The final ISO will be at:
```
output/debcraft-1.0.0-amd64.iso
output/debcraft-1.0.0-amd64.iso.sha256
```

Flash it with **BalenaEtcher**, **Rufus** (DD mode), or `dd`:
```bash
sudo dd if=output/debcraft-1.0.0-amd64.iso of=/dev/sdX bs=4M status=progress
```

---

## Using the Live ISO

1. **Boot from USB** — select the live entry in GRUB
2. You'll be auto-logged in as user `live` with password `live`
3. The bspwm desktop starts automatically with:
   - Polybar at the top (workspaces, CPU, RAM, volume, battery, time)
   - Plank dock at the bottom
   - Rofi launcher: `Super + Space`
   - Terminal: `Super + Return`
   - File manager: `Super + E`
4. **Install** — double-click the "Install DebCraft" icon on the desktop

### Key Bindings

| Shortcut | Action |
|----------|--------|
| `Super + Return` | Open Alacritty terminal |
| `Super + Shift + Return` | Open Kitty terminal |
| `Super + Space` | Rofi application launcher |
| `Super + Shift + Space` | Rofi run command |
| `Super + E` | Thunar file manager |
| `Super + W` | Firefox ESR |
| `Super + Q` | Close window |
| `Super + F` | Toggle fullscreen |
| `Super + M` | Toggle monocle layout |
| `Super + 1-9, 0` | Switch to desktop |
| `Super + Shift + 1-9, 0` | Send window to desktop |
| `Super + Arrow keys` | Focus/move windows |
| `Super + Alt + Arrow keys` | Resize windows |
| `Super + / Shift +` | Adjust window gaps |
| `Print` | Full screenshot |
| `Super + Print` | Area screenshot |
| `Alt + Tab` | Window switcher |
| `Super + L` | Lock screen |
| `Super + 0` | Power menu |
| `Volume keys` | Volume control |
| `Brightness keys` | Screen brightness |
| `Ctrl + Shift + Space` | Dismiss notifications |

---

## Installed System

After installation via Calamares:

1. **Reboot** and remove the USB
2. GRUB shows "DebCraft" as the boot entry
3. SDDM display manager appears — log in with your created user
4. bspwm starts automatically with the full DebCraft theme

### Post-Install Setup

If you need to configure an additional user:

```bash
sudo /usr/local/bin/debcraft-setup-user <username>
```

### NVIDIA

On the installed system with an NVIDIA GPU:

```bash
# Check driver status
nvidia-smi
nvidia-info

# Power management
sudo nvidia-power on      # Enable persistence mode
sudo nvidia-power off     # Disable
sudo nvidia-power fan 100 # Set power limit
```

---

## Customization

### Adding Your Own Wallpaper

Place `.png` or `.jpg` files in `assets/wallpapers/` before building. They'll be copied into the live system.

### Changing the Color Theme

All colors use the **Catppuccin Mocha** palette. To change:

- **Polybar**: Edit `config/polybar/config.ini` — `[colors]` section
- **bspwm borders**: Edit `config/bspwm/bspwmrc` — border color lines
- **Alacritty**: Edit `config/alacritty/alacritty.toml` — `[colors]` sections
- **Rofi**: Edit `config/rofi/launchers/type-1/launcher.rasi` — `@define-color` lines
- **Dunst**: Edit `config/dunst/dunstrc` — background/foreground/frame_color

### Adding/Removing Packages

Edit the package list files in `packages/`:
- `base.list` — core system packages
- `desktop.list` — desktop apps and utilities
- `nvidia.list` — NVIDIA driver packages
- `theming.list` — themes, icons, fonts

### Custom Calamares Modules

The installer flow is defined in `installer/settings.conf`. Add custom modules by creating new `.conf` files in `installer/modules/` and referencing them in the sequence.

---

## Troubleshooting

### Build Fails at Bootstrap

Ensure you have network access and the correct Debian mirror. Edit `DEBIAN_MIRROR` in `build.sh` if needed.

### NVIDIA Drivers Not Loading

```bash
# On installed system:
sudo update-initramfs -u
sudo grub-mkconfig -o /boot/grub/grub.cfg
sudo reboot
```

### Polybar Doesn't Start

Check with:
```bash
polybar -q main 2>&1
```
Common issue: missing fonts. Install `fonts-jetbrains-mono` and `fonts-font-awesome`.

### No Wi-Fi in Live Session

```bash
# Restart NetworkManager
sudo systemctl restart NetworkManager
nm-applet &
```

---

## License

This project is provided as-is for educational and personal use. Individual packages retain their respective licenses. Debian is a trademark of Software in the Public Interest, Inc. Archcraft is developed by the Archcraft team.

---

## Credits

- **Debian** — Base system
- **Archcraft** — Design inspiration
- **Catppuccin** — Color palette
- **bspwm** — Window manager
- **Polybar** — Status bar
- **Picom** — Compositor
- **Calamares** — Installer framework
- **Papirus** — Icon theme
