# Raspberry Pi 3B Print Server

CUPS-based print server with AirPrint support for three USB printers.

## Hardware

- **Server:** Raspberry Pi 3B (1GB RAM)
- **OS:** Raspberry Pi OS Lite (Bookworm / Debian 12)
- **Printers:**
  - HP LaserJet 1320 (USB) — general purpose laser printer
  - Dymo LabelWriter 4XL (USB) — 4x6 shipping labels
  - Dymo LabelWriter 450 Turbo (USB) — standard address/barcode labels

## Prerequisites

1. Raspberry Pi OS Lite (Bookworm) installed and booted
2. Network connectivity (Ethernet or Wi-Fi configured)
3. SSH access or local terminal
4. All three printers connected via USB (a powered USB hub is recommended since the Pi 3B has limited USB power)

## Installation

Copy the `print-server/` directory to your Pi (via scp, USB drive, etc.), then run:

```bash
# Make scripts executable
chmod +x *.sh

# Step 1: Install packages and configure system
sudo ./01-setup.sh

# Step 2: Connect all USB printers, then configure them
sudo ./02-configure-printers.sh

# Step 3: Enable AirPrint discovery
sudo ./03-airprint.sh
```

## Scripts

| Script | Purpose |
|---|---|
| `01-setup.sh` | System update, install CUPS/Avahi/hplip/Dymo drivers, configure networking |
| `02-configure-printers.sh` | Detect USB printers and add them to CUPS with correct drivers |
| `03-airprint.sh` | Configure Avahi service files for AirPrint/Bonjour discovery |
| `04-maintenance.sh` | Interactive maintenance menu (status, queues, logs, health) |
| `05-uninstall.sh` | Clean removal of printers, packages, and configs |

## Maintenance

The maintenance script can be used interactively or with command-line arguments:

```bash
# Interactive menu
sudo ./04-maintenance.sh

# Direct commands
sudo ./04-maintenance.sh status     # Printer status
sudo ./04-maintenance.sh queue      # View print queue
sudo ./04-maintenance.sh clear      # Clear all queues
sudo ./04-maintenance.sh restart    # Restart CUPS & Avahi
sudo ./04-maintenance.sh usb        # Check USB devices
sudo ./04-maintenance.sh logs       # View CUPS error log
sudo ./04-maintenance.sh health     # System health (temp, RAM, disk)
sudo ./04-maintenance.sh test       # Print test page
sudo ./04-maintenance.sh debug      # Toggle CUPS debug logging
sudo ./04-maintenance.sh clean      # Clean CUPS spool directory
```

## Client Setup

### macOS / iOS (AirPrint)

Printers are discovered automatically. No setup required.

- **macOS:** System Settings > Printers & Scanners > the printers should appear automatically. If not, click "+" and they will be listed under "Nearby Printers".
- **iOS:** In any app, tap Share > Print. The printers will appear in the printer list.

### Windows 10/11

Windows 10/11 supports IPP natively:

1. **Settings** > **Bluetooth & devices** > **Printers & scanners**
2. Click **Add device**
3. Wait — the printers may appear automatically via WSD/mDNS
4. If not found, click **Add manually** > **Add a printer using an IP address or hostname**
5. Select **IPP** as the protocol
6. Enter the printer URL:
   - HP LaserJet 1320: `ipp://<pi-ip>:631/printers/HP-LaserJet-1320`
   - Dymo LabelWriter 4XL: `ipp://<pi-ip>:631/printers/Dymo-LabelWriter-4XL`
   - Dymo LabelWriter 450 Turbo: `ipp://<pi-ip>:631/printers/Dymo-LabelWriter-450-Turbo`

Replace `<pi-ip>` with your Pi's IP address (e.g., `192.168.1.50`) or use `<hostname>.local` if mDNS resolution works on your network.

> **Note on Dymo + Windows:** Windows clients may need the Dymo Label software installed locally for proper label formatting. CUPS handles the raw printing, but label layout tools run on the client.

### Linux

Printers should be auto-discovered via Avahi. If not:

```bash
# GUI: Add via system printer settings

# CLI: Add manually
lpadmin -p HP-LaserJet-1320 -v ipp://<pi-ip>:631/printers/HP-LaserJet-1320 -E
```

### Android

Most modern Android devices support printing via the built-in Print Service:

1. **Settings** > **Connected devices** > **Printing**
2. Enable **Default Print Service**
3. Printers should appear automatically

If not, install the **CUPS Printing** app from the Play Store.

## CUPS Web Interface

Access the CUPS administration panel from any browser on your network:

```
https://<pi-ip>:631
```

- Username: your Pi username (default: `pi`)
- Password: your Pi login password

The browser will warn about a self-signed certificate — this is normal, accept it.

From the web interface you can:
- View printer status and queues
- Manage printer settings and defaults
- Set per-printer options (paper size, quality, etc.)
- View completed and failed jobs

## Default Printer Settings

| Printer | Default Paper | Default Quality |
|---|---|---|
| HP LaserJet 1320 | US Letter (8.5x11) | Normal |
| Dymo LabelWriter 4XL | 4x6 Shipping Label | Graphics |
| Dymo LabelWriter 450 Turbo | Address Label (30252) | Graphics |

You can change these defaults via the CUPS web interface or with `lpadmin`:

```bash
# Example: Change Dymo 4XL default to a different label size
sudo lpadmin -p Dymo-LabelWriter-4XL -o media=w288h432

# Example: Set HP to duplex by default
sudo lpadmin -p HP-LaserJet-1320 -o sides=two-sided-long-edge
```

## Troubleshooting

### Printer not detected

```bash
# Check USB connections
lsusb | grep -iE "dymo|hp|hewlett"

# Check CUPS device detection
sudo lpinfo -v | grep usb

# If a printer isn't showing up:
# 1. Unplug and replug the USB cable
# 2. Try a different USB port
# 3. Restart CUPS: sudo systemctl restart cups
# 4. Check dmesg for USB errors: dmesg | tail -20
```

### Print jobs stuck in queue

```bash
# View the queue
lpstat -o

# Cancel all jobs for a specific printer
cancel -a HP-LaserJet-1320

# Cancel all jobs on all printers
cancel -a

# Restart CUPS
sudo systemctl restart cups
```

### AirPrint not discovering printers

```bash
# Check Avahi is running
systemctl status avahi-daemon

# Browse for IPP services
avahi-browse -t _ipp._tcp

# Check service files exist
ls -la /etc/avahi/services/AirPrint-*.service

# Restart Avahi
sudo systemctl restart avahi-daemon

# Make sure printers are shared
lpstat -s
```

### CUPS web interface not accessible

```bash
# Check CUPS is listening on all interfaces (not just localhost)
ss -tlnp | grep 631

# Should show 0.0.0.0:631, not 127.0.0.1:631
# If it shows localhost only, re-run 01-setup.sh

# Check firewall
sudo ufw status
```

### Dymo prints blank labels or wrong size

```bash
# List available media sizes for the printer
lpoptions -p Dymo-LabelWriter-4XL -l | grep media

# Common Dymo media codes:
#   w432h288  = 4"x6" shipping label (4XL)
#   w162h252  = Standard address label 30252 (450)
#   w167h288  = Large address label 30321 (450)
#   w54h144   = Return address label 30330 (450)

# Set a different default
sudo lpadmin -p Dymo-LabelWriter-4XL -o media=w432h288
```

### HP LaserJet 1320 driver issues

```bash
# Check hplip is installed
dpkg -l | grep hplip

# List available HP PPDs
lpinfo -m | grep -i "1320"

# Run HP diagnostic
hp-check

# If PPD issues persist, try the generic PCL driver:
sudo lpadmin -p HP-LaserJet-1320 -m drv:///hp/hplip.drv/hp-laserjet_1320-pcl3.ppd
```

### Memory pressure on Pi 3B (1GB)

```bash
# Check memory
free -h

# Check swap
swapon --show

# If swap is too small, increase it:
sudo sed -i 's/^CONF_SWAPSIZE=.*/CONF_SWAPSIZE=512/' /etc/dphys-swapfile
sudo systemctl restart dphys-swapfile
```

## USB Hub Recommendation

The Raspberry Pi 3B has 4 USB 2.0 ports. With three printers connected, you'll use 3 of 4 ports. A **powered USB hub** is strongly recommended because:

- The Pi 3B can only supply ~1.2A total across all USB ports
- The Dymo LabelWriter 4XL draws significant power during printing
- USB power issues can cause printers to disconnect mid-job

Connect the powered hub to one of the Pi's USB ports, then plug all three printers into the hub.

## Uninstall

To completely remove the print server:

```bash
sudo ./05-uninstall.sh
```

This will remove printers, AirPrint service files, and optionally remove all installed packages.
