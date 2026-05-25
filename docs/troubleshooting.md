# Troubleshooting

## `modprobe: FATAL: Module ch341 not found`

This means the CH341 module is not installed for your running kernel.

Confirm:

```bash
uname -r
find /lib/modules/$(uname -r) -iname '*ch341*'
```

If you are running `5.15.185-tegra`, use the build script in this repo.

---

## Script aborts because kernel is not `5.15.185-tegra`

The script is intentionally locked to the tested kernel release.

Check:

```bash
uname -r
cat /etc/nv_tegra_release 2>/dev/null || true
```

If your kernel is different, do not blindly force the script. You need matching NVIDIA kernel sources and a module built with matching `vermagic`.

---

## `vermagic` check fails

The script refuses to install a module if the module version string does not match the running kernel.

This protects your system from installing a kernel module built against the wrong source/config.

Check:

```bash
uname -r
modinfo -F vermagic path/to/ch341.ko
```

The output should contain your exact `uname -r` string.

---

## `ch341` loads but `/dev/ttyUSB0` still does not appear

Unplug and replug the USB device, then check:

```bash
dmesg | tail -80
lsmod | grep -E 'ch341|usbserial'
ls -l /dev/ttyUSB*
```

If `brltty` is installed, it may be grabbing the adapter.

Read the accessibility warning first. Then, if you do not use a Braille display, try:

```bash
sudo systemctl disable --now brltty || true
sudo systemctl mask brltty || true
```

Unplug and replug the USB device again.

If disabling is not enough and you do not need Braille display support:

```bash
sudo apt remove -y brltty
sudo reboot
```

---

## `/dev/ttyUSB0` appears but upload/monitor fails with permission denied

Add your user to the `dialout` group:

```bash
sudo usermod -aG dialout $USER
```

Then log out and log back in, or reboot.

Confirm:

```bash
groups
```

Expected to include:

```text
dialout
```

---

## USB device does not appear in `lsusb`

This repo is for the case where the CH340/CH341 device appears in USB but does not create `/dev/ttyUSB0`.

If `lsusb` does not show the device:

- try another USB cable
- use a data-capable cable, not charge-only
- try another USB port
- check target-board power
- check whether the USB-UART chip is damaged
