#!/usr/bin/env bash

set -euo pipefail

# ==========================================
# Light i3 Dotfiles Installer (Arch Linux)
# ==========================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
BACKUP_DIR="$HOME/.config/light-i3-backup-$(date +%Y%m%d-%H%M%S)"

# ------------------------------------------
# Colors
# ------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ------------------------------------------
# Check operating system
# ------------------------------------------

if [[ ! -f /etc/os-release ]]; then
    error "Cannot determine operating system."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "arch" && "${ID_LIKE:-}" != *"arch"* ]]; then
    error "This installer is designed for Arch Linux / Arch-based systems (Manjaro, EndeavourOS, etc.)."
    exit 1
fi

echo
echo "=========================================="
echo "        Light i3 Dotfiles Installer"
echo "=========================================="
echo

info "Detected OS: $PRETTY_NAME"
info "Repository: $REPO_DIR"
info "User: $USER"
echo

# ------------------------------------------
# Check sudo
# ------------------------------------------

if ! command -v sudo >/dev/null 2>&1; then
    error "sudo is required."
    exit 1
fi

# ------------------------------------------
# Check / install an AUR helper (yay)
# ------------------------------------------
#
# A couple of packages in this config
# (light, tty-clock) are AUR-only and are
# not available via pacman directly.
# ------------------------------------------

if ! command -v yay >/dev/null 2>&1; then

    warning "yay (AUR helper) not found."
    read -r -p "Install yay now to pull AUR-only packages? [Y/n]: " yay_answer
    yay_answer="${yay_answer:-Y}"

    if [[ "$yay_answer" =~ ^[Yy]$ ]]; then

        info "Installing base-devel and git..."
        sudo pacman -S --needed --noconfirm base-devel git

        info "Building yay from AUR..."
        TMP_YAY_DIR="$(mktemp -d)"
        git clone https://aur.archlinux.org/yay.git "$TMP_YAY_DIR/yay"
        (cd "$TMP_YAY_DIR/yay" && makepkg -si --noconfirm)
        rm -rf "$TMP_YAY_DIR"

        success "yay installed."
    else
        warning "Continuing without yay. AUR-only packages (light, tty-clock) will be skipped."
    fi
fi

HAVE_YAY=false
if command -v yay >/dev/null 2>&1; then
    HAVE_YAY=true
fi

# ------------------------------------------
# Update package databases
# ------------------------------------------

info "Syncing pacman package databases..."

sudo pacman -Syu --noconfirm

success "Package databases synced."

# ------------------------------------------
# Install required packages (official repos)
# ------------------------------------------

PACKAGES=(
    i3-wm
    i3lock
    polybar
    rofi
    alacritty
    dunst
    feh
    brightnessctl
    playerctl
    pulseaudio
    pulseaudio-alsa
    alsa-utils
    xdotool
    maim
    flameshot
    network-manager-applet
    btop
    python
    mpc
    ncmpcpp
    ranger
    powertop
    fastfetch
    redshift
    cava
    cmatrix
)

# ------------------------------------------
# Xorg / X11 packages required to run i3
# ------------------------------------------
#
# i3 is an X11 window manager, so a working
# Xorg stack has to be present. On Debian
# this mostly comes bundled via metapackages
# (xserver-xorg, x11-xserver-utils); Arch
# ships these as separate packages.
# ------------------------------------------

XORG_PACKAGES=(
    xorg-server
    xorg-xinit
    xorg-xset
    xorg-xrandr
    xorg-xsetroot
    xorg-xprop
    xorg-xwininfo
    xorg-xkill
    xorg-xmodmap
    xorg-xdpyinfo
    xorg-xbacklight
    xorg-xrdb
    xorg-xhost
    mesa
)

# Fonts commonly needed for i3/polybar/rofi glyphs and icons
FONT_PACKAGES=(
    ttf-dejavu
    ttf-font-awesome
    noto-fonts
)

# Packages only available in the AUR
AUR_PACKAGES=(
    light
    tty-clock
)

info "Installing required packages..."

sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"

success "Required packages installed."

info "Installing Xorg/X11 packages..."

sudo pacman -S --needed --noconfirm "${XORG_PACKAGES[@]}"

success "Xorg/X11 packages installed."

info "Installing fonts (icons/glyphs for polybar & rofi)..."

sudo pacman -S --needed --noconfirm "${FONT_PACKAGES[@]}"

success "Fonts installed."

# ------------------------------------------
# GPU driver (best-effort auto-detect)
# ------------------------------------------
#
# Xorg needs a video driver to actually put
# anything on screen. This is hardware
# dependent, so we try to detect it via lspci
# and fall back to the generic modesetting
# driver (via mesa) if detection fails.
# ------------------------------------------

info "Detecting GPU for video driver selection..."

if command -v lspci >/dev/null 2>&1; then
    GPU_INFO="$(lspci | grep -iE 'vga|3d|display' || true)"
else
    GPU_INFO=""
    warning "lspci not found (pciutils not installed); skipping GPU auto-detection."
fi

DRIVER_PACKAGES=()

if [[ "$GPU_INFO" == *"Intel"* ]]; then
    info "Intel GPU detected."
    DRIVER_PACKAGES+=(xf86-video-intel vulkan-intel)
elif [[ "$GPU_INFO" == *"AMD"* || "$GPU_INFO" == *"ATI"* ]]; then
    info "AMD GPU detected."
    DRIVER_PACKAGES+=(xf86-video-amdgpu vulkan-radeon)
elif [[ "$GPU_INFO" == *"NVIDIA"* ]]; then
    info "NVIDIA GPU detected."
    DRIVER_PACKAGES+=(xf86-video-nouveau)
    warning "Open-source nouveau driver will be installed."
    warning "For proprietary drivers, install 'nvidia' or 'nvidia-dkms' separately."
elif [[ -n "$GPU_INFO" ]]; then
    warning "Unrecognized GPU: $GPU_INFO"
    warning "Falling back to generic modesetting driver (via mesa)."
else
    warning "Could not detect GPU. Falling back to generic modesetting driver (via mesa)."
fi

if [[ "${#DRIVER_PACKAGES[@]}" -gt 0 ]]; then
    info "Installing video driver packages: ${DRIVER_PACKAGES[*]}"
    sudo pacman -S --needed --noconfirm "${DRIVER_PACKAGES[@]}"
    success "Video driver packages installed."
else
    info "No dedicated driver package installed; the generic 'modesetting' driver (provided by mesa/xorg-server) will be used."
fi

if [[ "$HAVE_YAY" == true ]]; then
    info "Installing AUR packages (light, tty-clock)..."
    yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"
    success "AUR packages installed."
else
    warning "Skipped AUR packages: ${AUR_PACKAGES[*]}"
    warning "Install yay (or another AUR helper) and run: yay -S ${AUR_PACKAGES[*]}"
fi

# ------------------------------------------
# Install Picom separately
# ------------------------------------------
#
# Arch's official picom package is usually
# recent enough, but we still verify the
# version required by this configuration.
# ------------------------------------------

PICOM_VERSION_REQUIRED="13"

if command -v picom >/dev/null 2>&1; then
    PICOM_VERSION="$(picom --version 2>/dev/null | head -n1 || true)"

    info "Existing Picom detected: $PICOM_VERSION"

    if [[ "$PICOM_VERSION" == *"$PICOM_VERSION_REQUIRED"* ]]; then
        success "Required Picom version already installed."
    else
        warning "Installed Picom does not appear to be version $PICOM_VERSION_REQUIRED."
        warning "Picom installation will need to be handled separately."
    fi
else
    info "Installing picom from the official repositories..."
    if sudo pacman -S --needed --noconfirm picom; then
        PICOM_VERSION="$(picom --version 2>/dev/null | head -n1 || true)"
        if [[ "$PICOM_VERSION" == *"$PICOM_VERSION_REQUIRED"* ]]; then
            success "Picom $PICOM_VERSION_REQUIRED installed."
        else
            warning "Installed Picom ($PICOM_VERSION) does not appear to be version $PICOM_VERSION_REQUIRED."
            warning "Picom installation will need to be handled separately."
        fi
    else
        warning "Picom is not installed."
        warning "Picom v$PICOM_VERSION_REQUIRED will need to be installed separately."
    fi
fi

# ------------------------------------------
# Create config directory
# ------------------------------------------

mkdir -p "$CONFIG_DIR"

# ------------------------------------------
# Backup existing configurations
# ------------------------------------------

CONFIGS=(
    i3
    polybar
    picom
    rofi
    alacritty
    fastfetch
)

BACKUP_NEEDED=false

for config in "${CONFIGS[@]}"; do
    if [[ -e "$CONFIG_DIR/$config" ]]; then
        BACKUP_NEEDED=true
        break
    fi
done

if [[ "$BACKUP_NEEDED" == true ]]; then

    echo
    warning "Existing configuration detected."
    echo
    echo "The following configurations may be replaced:"
    echo

    for config in "${CONFIGS[@]}"; do
        if [[ -e "$CONFIG_DIR/$config" ]]; then
            echo "  ~/.config/$config"
        fi
    done

    echo
    read -r -p "Back up before continuing? [Y/n]: " answer
    answer="${answer:-Y}"

    if [[ "$answer" =~ ^[Yy]$ ]]; then

        mkdir -p "$BACKUP_DIR"

        for config in "${CONFIGS[@]}"; do
            if [[ -e "$CONFIG_DIR/$config" ]]; then
                cp -a "$CONFIG_DIR/$config" "$BACKUP_DIR/"
            fi
        done

        success "Backup created at:"
        echo "  $BACKUP_DIR"

    else
        warning "Continuing without backup."
    fi
fi

# ------------------------------------------
# Install configuration directories
# ------------------------------------------

info "Installing configuration files..."

install_config() {

    local name="$1"

    if [[ -d "$REPO_DIR/$name" ]]; then

        mkdir -p "$CONFIG_DIR/$name"

        cp -a "$REPO_DIR/$name/." "$CONFIG_DIR/$name/"

        success "Installed $name"
    fi
}

install_config "i3"
install_config "polybar"
install_config "picom"
install_config "rofi"
install_config "alacritty"
install_config "fastfetch"

# ------------------------------------------
# Install wallpapers
# ------------------------------------------

WALLPAPER_DIR="$HOME/Pictures/Light-i3-wallpapers"

if [[ -d "$REPO_DIR/wallpapers" ]]; then

    info "Installing wallpapers..."

    mkdir -p "$WALLPAPER_DIR"

    cp -a "$REPO_DIR/wallpapers/." "$WALLPAPER_DIR/"

    success "Wallpapers installed to:"
    echo "  $WALLPAPER_DIR"
fi

# ------------------------------------------
# Make scripts executable
# ------------------------------------------

info "Setting executable permissions..."

find "$CONFIG_DIR/i3" \
     "$CONFIG_DIR/rofi" \
     -type f \
     -name "*.sh" \
     -exec chmod +x {} \; 2>/dev/null || true

find "$CONFIG_DIR/i3" \
     -type f \
     -name "*.py" \
     -exec chmod +x {} \; 2>/dev/null || true

success "Script permissions configured."

# ------------------------------------------
# Finish
# ------------------------------------------

echo
echo "=========================================="
echo "          Installation Complete"
echo "=========================================="
echo

success "Light i3 configuration installed."

echo
echo "Installed components:"
echo "  i3 (Xorg + xinit)"
echo "  Polybar"
echo "  Rofi"
echo "  Alacritty"
echo "  Fastfetch"
echo "  Dunst"
echo "  Redshift"
echo "  Wallpapers"
echo

info "If you don't use a display manager, start i3 with 'startx' after"
info "adding 'exec i3' to ~/.xinitrc."

if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    echo "Backup:"
    echo "  $BACKUP_DIR"
    echo
fi

if [[ "$HAVE_YAY" != true ]]; then
    warning "AUR packages (light, tty-clock) were not installed — set up an AUR helper and install them separately."
fi

echo
echo "After installation, log into an i3 session."
echo
