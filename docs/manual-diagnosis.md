# Manual diagnosis notes

This page captures the commands used to diagnose the missing CH340/CH341 serial driver on Jetson Linux / L4T 36.5.0.

---

## 1. Confirm the USB device exists

```bash
lsusb
```

Expected CH340/CH341 example:

```text
Bus 001 Device 010: ID 1a86:7523 QinHeng Electronics CH340 serial converter
```

If this does not appear, the problem may be cable, power, USB port, or target-board related rather than a Linux driver/module issue.

---

## 2. Check for ttyUSB device

```bash
ls /dev/ttyUSB*
```

Problem case:

```text
ls: cannot access '/dev/ttyUSB*': No such file or directory
```

---

## 3. Check kernel version

```bash
uname -r
```

Tested version:

```text
5.15.185-tegra
```

---

## 4. Check installed NVIDIA kernel packages

```bash
dpkg -l | grep nvidia-l4t-kernel
```

In the tested case, the system had L4T 36.5.0 kernel packages and headers installed.

---

## 5. Check for existing serial modules

```bash
find /lib/modules/$(uname -r) -iname '*usbserial*'
find /lib/modules/$(uname -r) -iname '*ch341*'
```

Problem case:

```text
/lib/modules/5.15.185-tegra/kernel/drivers/usb/serial/usbserial.ko
```

but no `ch341.ko`.

---

## 6. Check kernel config

```bash
grep CONFIG_USB_SERIAL_CH341 /lib/modules/$(uname -r)/build/.config 2>/dev/null || true
```

Problem case:

```text
# CONFIG_USB_SERIAL_CH341 is not set
```

---

## 7. Try loading the module

```bash
sudo modprobe ch341
```

Problem case:

```text
modprobe: FATAL: Module ch341 not found in directory /lib/modules/5.15.185-tegra
```

---

## 8. Check for brltty interference

```bash
dpkg -s brltty >/dev/null 2>&1 && echo "brltty installed" || echo "brltty not installed"
systemctl status brltty --no-pager || true
```

If `brltty` is installed and `/dev/ttyUSB0` still does not appear after the module is installed, read the accessibility warning in the README before disabling or removing it.
