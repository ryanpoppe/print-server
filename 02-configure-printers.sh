#!/bin/bash
#
# 02-configure-printers.sh - Detect and Configure USB Printers
#
# Adds the following printers to CUPS:
#   - Dymo LabelWriter 4XL
#   - Dymo LabelWriter 450 Turbo
#   - HP LaserJet 1320
#
# Run as root or with sudo after 01-setup.sh
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root. Use: sudo $0"
    exit 1
fi

# --- Verify CUPS is running ---

if ! systemctl is-active --quiet cups; then
    log_error "CUPS is not running. Run 01-setup.sh first."
    exit 1
fi

# --- USB device IDs ---
# Dymo LabelWriter 4XL:      USB vendor 0922
# Dymo LabelWriter 450 Turbo: USB vendor 0922
# HP LaserJet 1320:           USB vendor 03f0

DYMO_VENDOR="0922"
HP_VENDOR="03f0"

# CUPS printer names (no spaces, used as queue identifiers)
HP_NAME="HP-LaserJet-1320"
DYMO_4XL_NAME="Dymo-LabelWriter-4XL"
DYMO_450_NAME="Dymo-LabelWriter-450-Turbo"

# Human-readable descriptions
HP_DESC="HP LaserJet 1320"
DYMO_4XL_DESC="Dymo LabelWriter 4XL"
DYMO_450_DESC="Dymo LabelWriter 450 Turbo"

# Location (customize as needed)
LOCATION="Print Server"

# --- Detect connected USB printers ---

log_step "Scanning for connected USB printers..."
echo ""

USB_PRINTERS=$(lsusb 2>/dev/null || true)

echo "$USB_PRINTERS" | grep -iE "(dymo|hewlett|hp)" || true
echo ""

# --- Detect CUPS USB device URIs ---

log_step "Detecting CUPS device URIs..."
echo ""

# Give CUPS a moment to detect USB devices
sleep 2

DEVICE_URIS=$(lpinfo -v 2>/dev/null || true)

echo "Available device URIs:"
echo "$DEVICE_URIS" | grep -i "usb://" || log_warn "No USB printer URIs detected"
echo ""

# --- Function to find device URI by pattern ---

find_device_uri() {
    local pattern="$1"
    echo "$DEVICE_URIS" | grep -i "usb://.*${pattern}" | awk '{print $2}' | head -1
}

# --- Function to find PPD by pattern ---

find_ppd() {
    local pattern="$1"
    lpinfo -m 2>/dev/null | grep -i "$pattern" | head -1 | awk '{print $1}'
}

# --- Function to add a printer ---

add_printer() {
    local name="$1"
    local uri="$2"
    local ppd="$3"
    local desc="$4"
    local location="$5"

    if [[ -z "$uri" ]]; then
        log_error "No device URI found for $desc. Is the printer connected?"
        return 1
    fi

    if [[ -z "$ppd" ]]; then
        log_error "No PPD/driver found for $desc."
        return 1
    fi

    log_info "Adding printer: $desc"
    log_info "  URI: $uri"
    log_info "  PPD: $ppd"

    # Remove existing printer with the same name if present
    if lpstat -p "$name" &>/dev/null; then
        log_warn "Printer '$name' already exists. Removing and re-adding..."
        lpadmin -x "$name"
    fi

    # Add the printer
    lpadmin -p "$name" \
        -v "$uri" \
        -m "$ppd" \
        -D "$desc" \
        -L "$location" \
        -E

    # Enable and share the printer
    cupsenable "$name"
    cupsaccept "$name"
    lpadmin -p "$name" -o printer-is-shared=true

    log_info "Printer '$desc' added and shared successfully"
    return 0
}

# =========================================
# Configure HP LaserJet 1320
# =========================================

echo ""
echo "========================================="
log_step "Configuring HP LaserJet 1320"
echo "========================================="
echo ""

HP_URI=$(find_device_uri "HP.*LaserJet.*1320")
if [[ -z "$HP_URI" ]]; then
    HP_URI=$(find_device_uri "Hewlett.*1320")
fi
if [[ -z "$HP_URI" ]]; then
    # Try broader HP match
    HP_URI=$(find_device_uri "HP\|Hewlett")
    if [[ -n "$HP_URI" ]]; then
        log_warn "Could not find specific HP 1320 URI. Found: $HP_URI"
        log_warn "Verify this is the correct printer."
    fi
fi

# Find PPD - try hplip first, then generic postscript
HP_PPD=$(find_ppd "HP.*LaserJet.*1320")
if [[ -z "$HP_PPD" ]]; then
    HP_PPD=$(find_ppd "laserjet.*1320")
fi
if [[ -z "$HP_PPD" ]]; then
    # hplip provides PPDs under drv:///
    HP_PPD="drv:///hp/hplip.drv/hp-laserjet_1320-pcl3.ppd"
    log_warn "Using default hplip PPD path: $HP_PPD"
fi

if add_printer "$HP_NAME" "$HP_URI" "$HP_PPD" "$HP_DESC" "$LOCATION"; then
    # Set HP-specific options
    lpadmin -p "$HP_NAME" -o media=na_letter_8.5x11in
    lpadmin -p "$HP_NAME" -o sides=one-sided
    lpadmin -p "$HP_NAME" -o print-quality=4
    log_info "HP LaserJet 1320: default paper=Letter, simplex, normal quality"
else
    log_error "Failed to configure HP LaserJet 1320"
fi

# =========================================
# Configure Dymo LabelWriter 4XL
# =========================================

echo ""
echo "========================================="
log_step "Configuring Dymo LabelWriter 4XL"
echo "========================================="
echo ""

DYMO_4XL_URI=$(find_device_uri "DYMO.*4XL")
if [[ -z "$DYMO_4XL_URI" ]]; then
    DYMO_4XL_URI=$(find_device_uri "DYMO.*LabelWriter.*4XL")
fi

DYMO_4XL_PPD=$(find_ppd "4xl")
if [[ -z "$DYMO_4XL_PPD" ]]; then
    DYMO_4XL_PPD=$(find_ppd "lw4xl")
fi
if [[ -z "$DYMO_4XL_PPD" ]]; then
    # Default path from printer-driver-dymo package
    DYMO_4XL_PPD="dymo:0/ppd/lw4xl.ppd"
    log_warn "Using default Dymo 4XL PPD path: $DYMO_4XL_PPD"
fi

if add_printer "$DYMO_4XL_NAME" "$DYMO_4XL_URI" "$DYMO_4XL_PPD" "$DYMO_4XL_DESC" "$LOCATION"; then
    # Set Dymo 4XL options - default to 4x6 shipping labels
    lpadmin -p "$DYMO_4XL_NAME" -o media=w432h288 2>/dev/null || true
    lpadmin -p "$DYMO_4XL_NAME" -o DymoPrintQuality=Graphics 2>/dev/null || true
    lpadmin -p "$DYMO_4XL_NAME" -o DymoPrintDensity=Normal 2>/dev/null || true
    log_info "Dymo 4XL: default label size=4x6 shipping, quality=Graphics"
else
    log_error "Failed to configure Dymo LabelWriter 4XL"
fi

# =========================================
# Configure Dymo LabelWriter 450 Turbo
# =========================================

echo ""
echo "========================================="
log_step "Configuring Dymo LabelWriter 450 Turbo"
echo "========================================="
echo ""

DYMO_450_URI=$(find_device_uri "DYMO.*450")
if [[ -z "$DYMO_450_URI" ]]; then
    DYMO_450_URI=$(find_device_uri "DYMO.*LabelWriter.*450")
fi

DYMO_450_PPD=$(find_ppd "450.*turbo\|450t")
if [[ -z "$DYMO_450_PPD" ]]; then
    DYMO_450_PPD=$(find_ppd "lw450t")
fi
if [[ -z "$DYMO_450_PPD" ]]; then
    # Default path from printer-driver-dymo package
    DYMO_450_PPD="dymo:0/ppd/lw450t.ppd"
    log_warn "Using default Dymo 450 Turbo PPD path: $DYMO_450_PPD"
fi

if add_printer "$DYMO_450_NAME" "$DYMO_450_URI" "$DYMO_450_PPD" "$DYMO_450_DESC" "$LOCATION"; then
    # Set Dymo 450 options - default to standard address labels (1-1/8 x 3-1/2)
    lpadmin -p "$DYMO_450_NAME" -o media=w162h252 2>/dev/null || true
    lpadmin -p "$DYMO_450_NAME" -o DymoPrintQuality=Graphics 2>/dev/null || true
    lpadmin -p "$DYMO_450_NAME" -o DymoPrintDensity=Normal 2>/dev/null || true
    log_info "Dymo 450 Turbo: default label size=Address (30252), quality=Graphics"
else
    log_error "Failed to configure Dymo LabelWriter 450 Turbo"
fi

# =========================================
# Set default printer
# =========================================

echo ""
log_step "Setting default printer..."

if lpstat -p "$HP_NAME" &>/dev/null; then
    lpadmin -d "$HP_NAME"
    log_info "Default printer set to: $HP_DESC"
else
    log_warn "HP LaserJet 1320 not available. No default printer set."
fi

# =========================================
# Summary
# =========================================

echo ""
echo "========================================="
echo " Printer Configuration Summary"
echo "========================================="
echo ""

log_info "Configured printers:"
echo ""
lpstat -p -d 2>/dev/null || true

echo ""
log_info "Shared printers:"
lpstat -s 2>/dev/null || true

PI_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================="
echo " Configuration complete!"
echo "========================================="
echo ""
echo "Printers are now available at:"
echo "  HP LaserJet 1320:         ipp://$PI_IP:631/printers/$HP_NAME"
echo "  Dymo LabelWriter 4XL:    ipp://$PI_IP:631/printers/$DYMO_4XL_NAME"
echo "  Dymo LabelWriter 450:    ipp://$PI_IP:631/printers/$DYMO_450_NAME"
echo ""
echo "Next steps:"
echo "  1. Run: sudo ./03-airprint.sh  (for AirPrint support)"
echo "  2. Test printing from the CUPS web interface: https://$PI_IP:631"
echo ""
