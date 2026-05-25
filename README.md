# Jetson CH340/CH341 USB Serial Fix

Build and install the missing **CH340/CH341 USB serial kernel module** (`ch341.ko`) on NVIDIA Jetson Linux / L4T 36.5.0.

This fix is for Jetson systems where a CH340/CH341 USB serial device appears in `lsusb`, but no `/dev/ttyUSB0` serial port is created. It was tested with an ESP32-OLIMEX-POE-ISO board using a QinHeng CH340/CH341 USB serial chip.

## Tested environment

```text
Board: NVIDIA Jetson Orin Nano Developer Kit
Jetson Linux / L4T: 36.5.0
Ubuntu: 22.04 Jammy
Kernel: 5.15.185-tegra
USB serial chip: QinHeng CH340 / CH341
USB ID: 1a86:7523
Target board: ESP32-OLIMEX-POE-ISO
```

This may also help with other CH340/CH341-based boards, including many Arduino, ESP32, ESP8266, and USB-UART adapters on Jetson Linux.

## Problem summary

The USB device is detected:

```bash
lsusb
```

Example:

```text
Bus 001 Device 010: ID 1a86:7523 QinHeng Electronics CH340 serial converter
```

But no serial port appears:

```bash
ls /dev/ttyUSB*
```

Example failure:

```text
ls: cannot access '/dev/ttyUSB*': No such file or directory
```

Loading the driver also fails:

```bash
sudo modprobe ch341
```

Example failure:

```text
modprobe: FATAL: Module ch341 not found in directory /lib/modules/5.15.185-tegra
```

## Quick start

Clone the repository:

```bash
git clone https://github.com/farhan-jm/jetson-ch341-fix.git
cd jetson-ch341-fix
```

Run the safe build script:

```bash
chmod +x safe_build_ch341_l4t36_5.sh
./safe_build_ch341_l4t36_5.sh
```

When the script finishes, unplug and replug your CH340/CH341 USB device.

Then check:

```bash
dmesg | tail -80
ls -l /dev/ttyUSB*
```

Expected result:

```text
/dev/ttyUSB0
```

## Safety notes

This repository is intentionally conservative.

The build script:

- checks that the running kernel is exactly `5.15.185-tegra`
- downloads NVIDIA L4T 36.5 public kernel sources if needed
- builds only `drivers/usb/serial/ch341.ko`
- checks module `vermagic` before installing
- installs only `ch341.ko`
- does **not** replace your kernel image
- does **not** install all kernel modules
- does **not** flash anything
- does **not** reboot your Jetson

> [!WARNING]
> Review the script before running it. It uses `sudo` to install build dependencies, install the verified module, run `depmod`, and load `ch341`.

## Important warning about `brltty`

`brltty` is an accessibility service for Braille displays.

Do **not** disable or remove it if you use a Braille display or depend on it for accessibility.

For many embedded development setups, `brltty` is not needed and can interfere with CH340/CH341 USB serial adapters.

The script will warn you and ask before disabling/masking `brltty`. It does **not** remove `brltty` automatically.

Safer first action:

```bash
sudo systemctl disable --now brltty || true
sudo systemctl mask brltty || true
```

If you do not use a Braille display and disabling is not enough, you can remove it manually:

```bash
sudo apt remove -y brltty
sudo reboot
```

## Quick diagnosis before running the script

Run:

```bash
uname -r
lsusb
find /lib/modules/$(uname -r) -iname '*ch341*'
find /lib/modules/$(uname -r) -iname '*usbserial*'
grep CONFIG_USB_SERIAL_CH341 /lib/modules/$(uname -r)/build/.config 2>/dev/null || true
```

Expected problematic case:

```text
5.15.185-tegra
# CONFIG_USB_SERIAL_CH341 is not set
```

and no `ch341.ko` found.

## Root cause

On the tested Jetson Linux installation:

- `usbserial.ko` existed.
- `ch341.ko` did **not** exist.
- Kernel config showed `CONFIG_USB_SERIAL_CH341` was not enabled.

So Linux could see the USB device, but it could not bind it to the CH340/CH341 USB serial driver.

A second issue was also found: `brltty` can grab some CH340/CH341 adapters before the serial driver creates `/dev/ttyUSB0`.

## What the script does

The script performs these steps:

1. Confirms the running kernel is `5.15.185-tegra`.
2. Checks whether `brltty` is installed and prints an accessibility warning.
3. Installs required build packages.
4. Downloads NVIDIA L4T 36.5 public sources.
5. Extracts the kernel source archive.
6. Copies the current kernel config from a safe source.
7. Enables:

   ```text
   CONFIG_USB_SERIAL=m
   CONFIG_USB_SERIAL_CH341=m
   CONFIG_LOCALVERSION="-tegra"
   # CONFIG_LOCALVERSION_AUTO is not set
   ```

8. Builds only:

   ```text
   drivers/usb/serial/ch341.ko
   ```

9. Verifies `vermagic` contains:

   ```text
   5.15.185-tegra
   ```

10. Installs only:

    ```text
    /lib/modules/5.15.185-tegra/kernel/drivers/usb/serial/ch341.ko
    ```

11. Runs:

    ```bash
    sudo depmod -a 5.15.185-tegra
    sudo modprobe ch341
    ```

## Manual final checks

Check the module:

```bash
modinfo ch341 | head
lsmod | grep -E 'ch341|usbserial'
```

Load manually if needed:

```bash
sudo modprobe ch341
```

Check for the serial device:

```bash
ls -l /dev/ttyUSB*
```

## Fix user permissions

If `/dev/ttyUSB0` exists but your normal user cannot open it:

```bash
sudo usermod -aG dialout $USER
```

Then log out and log back in, or reboot.

Check:

```bash
groups
```

Expected to include:

```text
dialout
```

## ESP32 usage examples

ESP-IDF:

```bash
idf.py -p /dev/ttyUSB0 flash monitor
```

PlatformIO:

```bash
pio run -t upload --upload-port /dev/ttyUSB0
```

Serial monitor:

```bash
python3 -m serial.tools.miniterm /dev/ttyUSB0 115200
```

Exit miniterm:

```text
Ctrl + ]
```

## After a Jetson kernel update

If your Jetson kernel changes, the manually installed `ch341.ko` may need to be rebuilt.

Check after kernel updates:

```bash
uname -r
modinfo ch341
ls /dev/ttyUSB*
```

This script intentionally refuses to run on kernels other than `5.15.185-tegra` unless you explicitly modify `EXPECTED_KREL` and verify the matching L4T source.

## Repository contents

```text
.
|-- .editorconfig
|-- .gitattributes
|-- .gitignore
|-- CHANGELOG.md
|-- LICENSE
|-- README.md
|-- safe_build_ch341_l4t36_5.sh
`-- docs/
    |-- manual-diagnosis.md
    `-- troubleshooting.md
```

## Scope

This repo provides a focused workaround for one tested Jetson Linux release and kernel version.

It does not distribute NVIDIA kernel sources or prebuilt kernel modules. The script downloads public sources on the Jetson and builds the module locally against the running kernel.

## License

MIT License. See [`LICENSE`](LICENSE).
