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


info "Updating apt package lists..."

sudo apt update

success "apt package lists updated."

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
    cava
    cmatrix
    tty-clock

    # X11 diagnostic/utility tools used by i3 configs and scripts.
    # XFCE already provides the underlying X11 stack (Xorg, input
    # drivers, core libs), so we only need these CLI helpers -
    # x11-xserver-utils alone doesn't include xprop/xwininfo/xkill
    # (those live in x11-utils) or xmodmap (x11-xkb-utils).
    x11-utils
    x11-xkb-utils
    xinput
    xauth

    # notify-send, used by volume/brightness OSD scripts with dunst
    libnotify-bin

    # needed to query GitHub for the latest picom release below
    curl
)

info "Installing required packages..."

sudo apt install -y "${PACKAGES[@]}"

success "Required packages installed."

# ------------------------------------------
# Install Picom (auto-updating to latest)
# ------------------------------------------
#
# Linux Mint's APT repository ships a Picom
# that is much older than upstream, so we
# ask the GitHub API (https://github.com/
# yshui/picom) what the latest tagged
# release actually is, try apt first anyway
# (in case it's ever caught up), and if it
# hasn't, build that release from source
# with meson/ninja instead.
# ------------------------------------------

PICOM_REPO_URL="https://github.com/yshui/picom"
PICOM_VERSION_REQUIRED="13"   # fallback if the GitHub API can't be reached

info "Checking GitHub for the latest picom release..."

PICOM_LATEST_TAG="$(curl -fsSL --max-time 10 \
    https://api.github.com/repos/yshui/picom/releases/latest 2>/dev/null \
    | grep -m1 '"tag_name"' \
    | sed -E 's/.*"tag_name":\s*"([^"]+)".*/\1/' || true)"

if [[ -n "$PICOM_LATEST_TAG" ]]; then
    PICOM_VERSION_REQUIRED="${PICOM_LATEST_TAG#v}"
    success "Latest picom release on GitHub: $PICOM_LATEST_TAG"
else
    warning "Could not reach the GitHub API; falling back to picom v$PICOM_VERSION_REQUIRED."
    PICOM_LATEST_TAG="v$PICOM_VERSION_REQUIRED"
fi

# Build-time dependencies for compiling picom from source on
# Debian/Ubuntu/Mint (see the "Dependencies" section of the picom
# README: $PICOM_REPO_URL). with_docs defaults to false in picom's
# meson build, so asciidoctor/docbook tooling is not required.
PICOM_BUILD_DEPS=(
    build-essential
    git
    pkg-config
    meson
    ninja-build
    cmake
)

# Runtime/library dependencies for picom on Debian/Ubuntu/Mint
PICOM_RUNTIME_DEPS=(
    libconfig-dev
    libdbus-1-dev
    libegl-dev
    libgl-dev
    libepoxy-dev
    libev-dev
    libpcre2-dev
    libpixman-1-dev
    libx11-xcb-dev
    libxcb1-dev
    libxcb-composite0-dev
    libxcb-damage0-dev
    libxcb-glx0-dev
    libxcb-image0-dev
    libxcb-present-dev
    libxcb-randr0-dev
    libxcb-render0-dev
    libxcb-render-util0-dev
    libxcb-shape0-dev
    libxcb-util-dev
    libxcb-xfixes0-dev
    uthash-dev
)

build_picom_from_source() {
    local tag="$1"

    info "Building picom $tag from source ($PICOM_REPO_URL)..."

    info "Installing picom build dependencies..."
    sudo apt install -y "${PICOM_BUILD_DEPS[@]}" "${PICOM_RUNTIME_DEPS[@]}"

    local build_dir
    build_dir="$(mktemp -d)"

    if ! git clone --branch "$tag" --depth 1 "${PICOM_REPO_URL}.git" "$build_dir/picom"; then
        error "Failed to clone picom $tag from $PICOM_REPO_URL."
        rm -rf "$build_dir"
        return 1
    fi

    (
        cd "$build_dir/picom"
        meson setup --buildtype=release build
        ninja -C build
    ) || {
        error "Failed to build picom $tag."
        rm -rf "$build_dir"
        return 1
    }

    info "Installing picom $tag (requires sudo)..."
    sudo ninja -C "$build_dir/picom/build" install

    rm -rf "$build_dir"
    return 0
}

PICOM_OK=false

if command -v picom >/dev/null 2>&1; then
    PICOM_VERSION="$(picom --version 2>/dev/null | head -n1 || true)"
    info "Existing picom detected: $PICOM_VERSION"
    if [[ "$PICOM_VERSION" == *"$PICOM_VERSION_REQUIRED"* ]]; then
        success "picom is already at the latest version ($PICOM_LATEST_TAG)."
        PICOM_OK=true
    fi
fi

if [[ "$PICOM_OK" != true ]]; then
    info "Trying picom from the Mint/Ubuntu repositories first..."
    sudo apt install -y picom || true

    if command -v picom >/dev/null 2>&1; then
        PICOM_VERSION="$(picom --version 2>/dev/null | head -n1 || true)"
    else
        PICOM_VERSION=""
    fi

    if [[ "$PICOM_VERSION" == *"$PICOM_VERSION_REQUIRED"* ]]; then
        success "Installed picom $PICOM_VERSION from the repositories (latest: $PICOM_LATEST_TAG)."
        PICOM_OK=true
    else
        warning "Repo picom ($PICOM_VERSION) does not match the latest release ($PICOM_LATEST_TAG)."
        info "Falling back to building picom $PICOM_LATEST_TAG from source..."

        if build_picom_from_source "$PICOM_LATEST_TAG"; then
            PICOM_VERSION="$(picom --version 2>/dev/null | head -n1 || true)"
            success "picom built and installed from source: $PICOM_VERSION"
            PICOM_OK=true
        else
            warning "Building picom from source failed."
            warning "picom $PICOM_LATEST_TAG will need to be installed separately."
        fi
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

if [[ "$PICOM_OK" == true ]]; then
    success "picom ($PICOM_VERSION) is installed."
else
    warning "picom $PICOM_LATEST_TAG still needs to be installed separately."
fi

echo
echo "After installation, log into an i3 session."
echo
