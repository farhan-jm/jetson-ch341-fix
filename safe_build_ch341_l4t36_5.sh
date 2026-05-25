#!/usr/bin/env bash
set -euo pipefail

# safe_build_ch341_l4t36_5.sh
#
# Safe CH340/CH341 USB serial module builder for NVIDIA Jetson Linux / L4T 36.5.0.
#
# Intended for:
#   Kernel: 5.15.185-tegra
#   L4T:    36.5.0
#
# This script:
#   - Does NOT flash anything
#   - Does NOT replace the kernel Image
#   - Does NOT install all kernel modules
#   - Does NOT reboot
#   - Installs only ch341.ko after checking vermagic
#
# Review this script before running it. It uses sudo for package installation
# and for installing the verified kernel module.
#
# Important:
#   brltty can interfere with CH340/CH341 devices.
#   This script can optionally disable and mask brltty, but it will warn first.
#
# Accessibility warning:
#   brltty is used for Braille displays. Do not remove it if you need it.

KREL="$(uname -r)"
EXPECTED_KREL="${EXPECTED_KREL:-5.15.185-tegra}"
L4T_RELEASE_FILE="/etc/nv_tegra_release"

SRC_URL="${SRC_URL:-https://developer.download.nvidia.com/embedded/L4T/r36_Release_v5.0/sources/public_sources.tbz2}"

WORKDIR="${WORKDIR:-${HOME}/l4t36_5_ch341_build}"
SRC_ARCHIVE="${WORKDIR}/public_sources.tbz2"
EXTRACT_DIR="${WORKDIR}/extract"
MODULE_INSTALL_DIR="/lib/modules/${KREL}/kernel/drivers/usb/serial"
LOG_FILE="${HOME}/ch341_l4t36_5_build_${KREL}_$(date +%Y%m%d_%H%M%S).log"

say() {
    printf '%s\n' "$*"
}

section() {
    say
    say "============================================================"
    say " $*"
    say "============================================================"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        say "ERROR: Required command not found: $1"
        exit 1
    }
}

confirm_yes() {
    local prompt="$1"
    local ans=""
    read -r -p "${prompt} Type YES exactly: " ans
    [[ "${ans}" == "YES" ]]
}

section "Safe CH341 / CH340 builder for Jetson Linux"

say "Running kernel : ${KREL}"
say "Expected kernel: ${EXPECTED_KREL}"
say "Workdir        : ${WORKDIR}"
say "Log file       : ${LOG_FILE}"
say

if [[ "${KREL}" != "${EXPECTED_KREL}" ]]; then
    say "ERROR: This script is written for ${EXPECTED_KREL}, but you are running ${KREL}."
    say "Aborting for safety."
    exit 1
fi

if [[ "${KREL}" != *tegra* ]]; then
    say "ERROR: This does not look like a Jetson tegra kernel: ${KREL}"
    say "Aborting for safety."
    exit 1
fi

if [[ -f "${L4T_RELEASE_FILE}" ]]; then
    say "Detected ${L4T_RELEASE_FILE}:"
    cat "${L4T_RELEASE_FILE}"
    say
else
    say "WARNING: ${L4T_RELEASE_FILE} not found."
    say "This script is intended for Jetson Linux / L4T."
    say
fi

section "Current CH341 state"

if modinfo ch341 >/dev/null 2>&1; then
    say "ch341 module already exists:"
    modinfo ch341 | head
    say
else
    say "ch341 module is not currently installed."
fi

if lsmod | grep -q '^ch341'; then
    say "ch341 is already loaded."
else
    say "ch341 is not currently loaded."
fi

say

section "brltty check"

BRLTTY_INSTALLED=0
if dpkg -s brltty >/dev/null 2>&1; then
    BRLTTY_INSTALLED=1
    say "brltty is installed."
    say
    say "WARNING:"
    say "  brltty is an accessibility service for Braille displays."
    say "  Do not remove it if you use or need a Braille display."
    say
    say "  On many embedded-development systems, brltty can grab CH340/CH341"
    say "  USB serial adapters and prevent /dev/ttyUSB0 from appearing."
    say
else
    say "brltty is not installed."
fi

section "Planned actions"

say "This script will:"
say "  1. Install build dependencies with apt."
say "  2. Download NVIDIA L4T 36.5 public sources if needed."
say "  3. Extract kernel source."
say "  4. Build only drivers/usb/serial/ch341.ko."
say "  5. Verify module vermagic contains ${KREL}."
say "  6. Install only ch341.ko into ${MODULE_INSTALL_DIR}."
say "  7. Run depmod and modprobe ch341."
say
say "It will NOT replace your kernel, NOT flash, and NOT reboot."
say

if ! confirm_yes "Continue with CH341 build/install?"; then
    say "Aborted by user."
    exit 0
fi

exec > >(tee -a "${LOG_FILE}") 2>&1

section "Step 1: Install required packages"

sudo apt update
sudo apt install -y \
    build-essential \
    bc \
    flex \
    bison \
    libssl-dev \
    libelf-dev \
    dwarves \
    wget \
    xz-utils \
    bzip2 \
    tar \
    rsync \
    kmod

section "Step 2: Prepare workspace"

mkdir -p "${WORKDIR}" "${EXTRACT_DIR}"
cd "${WORKDIR}"

if [[ ! -f "${SRC_ARCHIVE}" ]]; then
    say "Downloading NVIDIA public sources:"
    say "  ${SRC_URL}"
    wget -O "${SRC_ARCHIVE}.partial" "${SRC_URL}"
    mv "${SRC_ARCHIVE}.partial" "${SRC_ARCHIVE}"
else
    say "Source archive already exists:"
    say "  ${SRC_ARCHIVE}"
fi

say "Source archive:"
ls -lh "${SRC_ARCHIVE}"

section "Step 3: Extract source archive"

if [[ ! -d "${EXTRACT_DIR}/Linux_for_Tegra/source" && ! -d "${EXTRACT_DIR}/kernel" ]]; then
    say "Extracting public_sources.tbz2..."
    tar -xjf "${SRC_ARCHIVE}" -C "${EXTRACT_DIR}"
else
    say "Source archive already appears extracted."
fi

section "Step 4: Find and extract kernel source"

mapfile -t CANDIDATE_TARS < <(
    find "${EXTRACT_DIR}" -type f \( \
        -name 'kernel_src.tbz2' -o \
        -name '*kernel*src*.tbz2' \
    \) | sort
)

say "Candidate kernel source archives:"
if [[ "${#CANDIDATE_TARS[@]}" -eq 0 ]]; then
    say "  none"
else
    printf '  %s\n' "${CANDIDATE_TARS[@]}"
fi

for tarball in "${CANDIDATE_TARS[@]:-}"; do
    base="$(basename "${tarball}")"
    if [[ "${base}" == "kernel_src.tbz2" || "${base}" == *"kernel_src"* ]]; then
        marker="${WORKDIR}/kernel_src_extracted.marker"
        if [[ ! -f "${marker}" ]]; then
            say "Extracting kernel source archive:"
            say "  ${tarball}"
            tar -xjf "${tarball}" -C "${WORKDIR}"
            touch "${marker}"
        else
            say "Kernel source archive already extracted."
        fi
        break
    fi
done

section "Step 5: Locate ch341.c"

mapfile -t CH341_PATHS < <(
    find "${WORKDIR}" -path '*/drivers/usb/serial/ch341.c' -type f | sort
)

if [[ "${#CH341_PATHS[@]}" -eq 0 ]]; then
    say "ERROR: Could not find drivers/usb/serial/ch341.c."
    say "No changes were made to /lib/modules."
    exit 1
fi

CH341_C="${CH341_PATHS[0]}"
KERNEL_SRC="${CH341_C%/drivers/usb/serial/ch341.c}"

say "Using kernel source:"
say "  ${KERNEL_SRC}"

if [[ ! -f "${KERNEL_SRC}/Makefile" ]]; then
    say "ERROR: Kernel source Makefile not found:"
    say "  ${KERNEL_SRC}/Makefile"
    exit 1
fi

section "Step 6: Base kernel config"

cd "${KERNEL_SRC}"

CONFIG_SOURCE=""

if [[ -f "/proc/config.gz" ]]; then
    say "Using /proc/config.gz."
    zcat /proc/config.gz > .config
    CONFIG_SOURCE="/proc/config.gz"
elif [[ -f "/boot/config-${KREL}" ]]; then
    say "Using /boot/config-${KREL}."
    cp "/boot/config-${KREL}" .config
    CONFIG_SOURCE="/boot/config-${KREL}"
elif [[ -f "/lib/modules/${KREL}/build/.config" ]]; then
    say "Using /lib/modules/${KREL}/build/.config."
    cp "/lib/modules/${KREL}/build/.config" .config
    CONFIG_SOURCE="/lib/modules/${KREL}/build/.config"
else
    say "ERROR: Could not find a safe base kernel config."
    exit 1
fi

say "Base config source:"
say "  ${CONFIG_SOURCE}"

CONFIG_BACKUP=".config.backup.before_ch341_$(date +%Y%m%d_%H%M%S)"
cp -a .config "${CONFIG_BACKUP}"

say "Config backup:"
say "  ${KERNEL_SRC}/${CONFIG_BACKUP}"

say "Current relevant config:"
grep -E '^CONFIG_USB_SERIAL=|^CONFIG_USB_SERIAL_CH341=|^CONFIG_LOCALVERSION=|^CONFIG_LOCALVERSION_AUTO' .config || true

section "Step 7: Configure module build"

# Jetson modules must match the running kernel release string.
if grep -q '^CONFIG_LOCALVERSION=' .config; then
    sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-tegra"/' .config
else
    echo 'CONFIG_LOCALVERSION="-tegra"' >> .config
fi

if grep -q '^CONFIG_LOCALVERSION_AUTO=' .config; then
    sed -i 's/^CONFIG_LOCALVERSION_AUTO=.*/# CONFIG_LOCALVERSION_AUTO is not set/' .config
else
    echo '# CONFIG_LOCALVERSION_AUTO is not set' >> .config
fi

if [[ ! -x scripts/config ]]; then
    chmod +x scripts/config
fi

scripts/config --module USB_SERIAL
scripts/config --module USB_SERIAL_CH341

say "New relevant config:"
grep -E '^CONFIG_USB_SERIAL=|^CONFIG_USB_SERIAL_CH341=|^CONFIG_LOCALVERSION=|^CONFIG_LOCALVERSION_AUTO' .config || true

if ! grep -q '^CONFIG_USB_SERIAL=m$' .config; then
    say "ERROR: CONFIG_USB_SERIAL did not become module."
    cp -a "${CONFIG_BACKUP}" .config
    exit 1
fi

if ! grep -q '^CONFIG_USB_SERIAL_CH341=m$' .config; then
    say "ERROR: CONFIG_USB_SERIAL_CH341 did not become module."
    cp -a "${CONFIG_BACKUP}" .config
    exit 1
fi

section "Step 8: Prepare kernel build"

make olddefconfig
make prepare modules_prepare

section "Step 9: Build only drivers/usb/serial"

make M=drivers/usb/serial modules

BUILT_MODULE="${KERNEL_SRC}/drivers/usb/serial/ch341.ko"

if [[ ! -f "${BUILT_MODULE}" ]]; then
    say "ERROR: Build finished but ch341.ko was not created."
    cp -a "${CONFIG_BACKUP}" .config
    exit 1
fi

say "Built module:"
ls -lh "${BUILT_MODULE}"

section "Step 10: Verify module vermagic"

MODULE_VERMAGIC="$(modinfo -F vermagic "${BUILT_MODULE}" || true)"

say "Module vermagic:"
say "  ${MODULE_VERMAGIC}"
say "Running kernel:"
say "  ${KREL}"

if [[ "${MODULE_VERMAGIC}" != *"${KREL}"* ]]; then
    say "ERROR: Built module vermagic does not match running kernel."
    say "The module was NOT installed."
    cp -a "${CONFIG_BACKUP}" .config
    exit 1
fi

say "Vermagic check passed."

section "Step 11: Install only ch341.ko"

sudo mkdir -p "${MODULE_INSTALL_DIR}"

if [[ -f "${MODULE_INSTALL_DIR}/ch341.ko" ]]; then
    EXISTING_BACKUP="${MODULE_INSTALL_DIR}/ch341.ko.backup.$(date +%Y%m%d_%H%M%S)"
    say "Existing ch341.ko found. Backing it up:"
    say "  ${EXISTING_BACKUP}"
    sudo cp -a "${MODULE_INSTALL_DIR}/ch341.ko" "${EXISTING_BACKUP}"
fi

sudo install -m 0644 "${BUILT_MODULE}" "${MODULE_INSTALL_DIR}/ch341.ko"

say "Installed module:"
ls -lh "${MODULE_INSTALL_DIR}/ch341.ko"

section "Step 12: depmod and modprobe"

sudo depmod -a "${KREL}"
sudo modprobe ch341

say "Loaded modules:"
lsmod | grep -E '^ch341|^usbserial' || true

section "Step 13: Restore source .config"

cp -a "${CONFIG_BACKUP}" .config
say "Restored source .config."
say "Backup remains:"
say "  ${KERNEL_SRC}/${CONFIG_BACKUP}"

section "Step 14: Optional brltty handling"

if [[ "${BRLTTY_INSTALLED}" -eq 1 ]]; then
    say "brltty is installed."
    say
    say "Accessibility warning:"
    say "  brltty is used for Braille displays."
    say "  Do not disable or remove it if you need Braille display support."
    say
    say "Recommended safe first action:"
    say "  sudo systemctl disable --now brltty"
    say "  sudo systemctl mask brltty"
    say
    say "If you do not use a Braille display and /dev/ttyUSB0 still does not appear,"
    say "you can remove it manually:"
    say "  sudo apt remove -y brltty"
    say "  sudo reboot"
    say
    if confirm_yes "Disable and mask brltty now?"; then
        sudo systemctl disable --now brltty || true
        sudo systemctl mask brltty || true
        say "brltty disabled and masked."
    else
        say "Skipped brltty changes."
    fi
else
    say "brltty is not installed. Nothing to do."
fi

section "Done"

say "Now unplug and replug your CH340/CH341 USB device."
say
say "Then run:"
say "  dmesg | tail -80"
say "  ls -l /dev/ttyUSB*"
say
say "Expected:"
say "  /dev/ttyUSB0"
say
say "If /dev/ttyUSB0 appears but your software cannot open it:"
say "  sudo usermod -aG dialout \$USER"
say "Then log out/in or reboot."
say
say "Build log:"
say "  ${LOG_FILE}"
