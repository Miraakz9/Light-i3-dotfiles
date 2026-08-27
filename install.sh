#!/usr/bin/env bash

set -euo pipefail

# ==========================================
# Light i3 Dotfiles Installer
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

if [[ "$ID" != "linuxmint" && "$ID" != "ubuntu" && "$ID_LIKE" != *"debian"* ]]; then
    error "This installer is designed for Linux Mint / Ubuntu / Debian-based systems."
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
# Update package lists
# ------------------------------------------

info "Updating APT package lists..."

sudo apt update

success "APT package lists updated."

# ------------------------------------------
# Install required packages
# ------------------------------------------

PACKAGES=(
    i3
    i3lock
    polybar
    rofi
    alacritty
    dunst
    feh
    brightnessctl
    light
    playerctl
    pulseaudio-utils
    alsa-utils
    x11-xserver-utils
    xdotool
    maim
    flameshot
    network-manager-gnome
    btop
    python3
    mpc
    ncmpcpp
    ranger
    powertop
    fastfetch
    redshift
)

info "Installing required packages..."

sudo apt install -y "${PACKAGES[@]}"

success "Required packages installed."

# ------------------------------------------
# Install Picom separately
# ------------------------------------------
#
# Your Linux Mint APT repository provides
# an older Picom than the version required
# by this configuration.
#
# We will handle Picom separately.
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
    warning "Picom is not installed."
    warning "Picom v13 will need to be installed separately."
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
    read -r -p "Back them up before continuing? [Y/n]: " answer
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
echo "  i3"
echo "  Polybar"
echo "  Rofi"
echo "  Alacritty"
echo "  Fastfetch"
echo "  Dunst"
echo "  Redshift"
echo "  Wallpapers"
echo

if [[ -n "${BACKUP_DIR:-}" && -d "$BACKUP_DIR" ]]; then
    echo "Backup:"
    echo "  $BACKUP_DIR"
    echo
fi

warning "Picom v13 still needs to be handled separately."

echo
echo "After installation, log into an i3 session."
echo
