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

if ! command -v curl >/dev/null 2>&1; then
    info "Installing curl (needed to check for the latest picom release)..."
    sudo pacman -S --needed --noconfirm curl
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
    # Display server + common files
    xorg-server
    xorg-server-common
    xorg-xinit

    # CLI tools used by i3/polybar/rofi scripts and for troubleshooting
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
    xorg-xinput
    xorg-xauth

    # Input drivers - without these, keyboard/mouse/touchpad
    # won't be recognized by the X server
    xf86-input-libinput
    xf86-input-evdev

    # GL/rendering stack (video driver packages are appended
    # separately based on detected GPU vendor below)
    mesa
    vulkan-icd-loader

    # Core X11 client libraries relied on by i3, polybar, rofi,
    # alacritty, dunst, feh, picom, etc.
    libx11
    libxcb
    libxft
    libxinerama
    libxrandr
    libxrender
    libxcursor
    libxfixes
    libxi
    libxext
    libxcomposite
    libxdamage

    # XCB utility libraries (needed by picom, i3, and others)
    xcb-util
    xcb-util-wm
    xcb-util-keysyms
    xcb-util-image
    xcb-util-renderutil
    xcb-util-cursor
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
# Install Picom (auto-updating to latest)
# ------------------------------------------
#
# Arch's official 'picom' package tends to
# track upstream releases quickly, so we try
# that first. We also ask the GitHub API
# (https://github.com/yshui/picom) what the
# latest tagged release actually is; if the
# repo package is behind (or missing), we
# build the latest release from source with
# meson/ninja instead.
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

# Build-time dependencies for compiling picom from source on Arch
# (see "Dependencies" in the picom README: $PICOM_REPO_URL)
PICOM_BUILD_DEPS=(
    base-devel
    git
    meson
    ninja
    cmake
    asciidoctor
)

# Runtime/library dependencies for picom on Arch
PICOM_RUNTIME_DEPS=(
    libx11
    libxext
    libxcb
    xcb-util
    xcb-util-image
    xcb-util-renderutil
    pixman
    libconfig
    dbus
    libglvnd
    libepoxy
    pcre2
    libev
    uthash
    xorgproto
)

build_picom_from_source() {
    local tag="$1"

    info "Building picom $tag from source ($PICOM_REPO_URL)..."

    info "Installing picom build dependencies..."
    sudo pacman -S --needed --noconfirm "${PICOM_BUILD_DEPS[@]}" "${PICOM_RUNTIME_DEPS[@]}"

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
    info "Trying picom from the official Arch repositories first..."
    sudo pacman -S --needed --noconfirm picom || true

    if command -v picom >/dev/null 2>&1; then
        PICOM_VERSION="$(picom --version 2>/dev/null | head -n1 || true)"
    else
        PICOM_VERSION=""
    fi

    if [[ "$PICOM_VERSION" == *"$PICOM_VERSION_REQUIRED"* ]]; then
        success "Installed picom $PICOM_VERSION from the official repositories (latest: $PICOM_LATEST_TAG)."
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
