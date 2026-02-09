#!/bin/bash
#
# 05-uninstall.sh - Clean Removal of Print Server
#
# Removes printers, packages, and configuration files installed
# by the print-server setup scripts.
#
# Run as root or with sudo.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${CYAN}[STEP]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root. Use: sudo $0"
    exit 1
fi

echo ""
echo -e "${BOLD}=========================================${NC}"
echo -e "${BOLD} Print Server Uninstall${NC}"
echo -e "${BOLD}=========================================${NC}"
echo ""
echo "This will:"
echo "  - Remove all configured printers from CUPS"
echo "  - Remove AirPrint Avahi service files"
echo "  - Optionally remove CUPS, Avahi, hplip, and Dymo drivers"
echo "  - Optionally restore original configuration files"
echo ""

read -rp "Are you sure you want to proceed? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

# =========================================
# Step 1: Remove printers from CUPS
# =========================================

echo ""
log_step "Removing printers from CUPS..."

PRINTERS=$(lpstat -p 2>/dev/null | awk '{print $2}' || true)
if [[ -n "$PRINTERS" ]]; then
    while IFS= read -r PRINTER; do
        # Cancel all jobs for this printer
        cancel -a "$PRINTER" 2>/dev/null || true
        # Remove the printer
        lpadmin -x "$PRINTER" 2>/dev/null && \
            log_info "Removed printer: $PRINTER" || \
            log_warn "Failed to remove printer: $PRINTER"
    done <<< "$PRINTERS"
else
    log_info "No printers configured in CUPS"
fi

# =========================================
# Step 2: Remove AirPrint Avahi service files
# =========================================

echo ""
log_step "Removing AirPrint Avahi service files..."

AVAHI_SERVICES_DIR="/etc/avahi/services"
AIRPRINT_FILES=$(find "$AVAHI_SERVICES_DIR" -name "AirPrint-*.service" 2>/dev/null || true)
if [[ -n "$AIRPRINT_FILES" ]]; then
    while IFS= read -r SERVICE_FILE; do
        rm -f "$SERVICE_FILE"
        log_info "Removed: $SERVICE_FILE"
    done <<< "$AIRPRINT_FILES"
else
    log_info "No AirPrint service files found"
fi

# =========================================
# Step 3: Clean CUPS spool
# =========================================

echo ""
log_step "Cleaning CUPS print spool..."
rm -rf /var/spool/cups/*
log_info "CUPS spool cleared"

# =========================================
# Step 4: Restore configuration backups
# =========================================

echo ""
log_step "Restoring configuration files..."

CUPSD_CONF="/etc/cups/cupsd.conf"
AVAHI_CONF="/etc/avahi/avahi-daemon.conf"

if [[ -f "${CUPSD_CONF}.bak" ]]; then
    cp "${CUPSD_CONF}.bak" "$CUPSD_CONF"
    rm -f "${CUPSD_CONF}.bak"
    log_info "Restored original cupsd.conf"
else
    log_warn "No cupsd.conf backup found"
fi

if [[ -f "${AVAHI_CONF}.bak" ]]; then
    cp "${AVAHI_CONF}.bak" "$AVAHI_CONF"
    rm -f "${AVAHI_CONF}.bak"
    log_info "Restored original avahi-daemon.conf"
else
    log_warn "No avahi-daemon.conf backup found"
fi

# =========================================
# Step 5: Optionally remove packages
# =========================================

echo ""
read -rp "Remove printer driver packages (hplip, printer-driver-dymo)? [y/N]: " REMOVE_DRIVERS
if [[ "$REMOVE_DRIVERS" =~ ^[Yy] ]]; then
    log_step "Removing printer drivers..."
    apt-get remove -y printer-driver-dymo hplip hplip-data 2>/dev/null || true
    apt-get autoremove -y
    log_info "Printer drivers removed"
fi

echo ""
read -rp "Remove CUPS and Avahi entirely? [y/N]: " REMOVE_CUPS
if [[ "$REMOVE_CUPS" =~ ^[Yy] ]]; then
    log_step "Removing CUPS and Avahi..."

    systemctl stop cups 2>/dev/null || true
    systemctl stop avahi-daemon 2>/dev/null || true
    systemctl disable cups 2>/dev/null || true
    systemctl disable avahi-daemon 2>/dev/null || true

    apt-get remove -y \
        cups cups-client cups-bsd cups-filters \
        avahi-daemon avahi-utils \
        2>/dev/null || true

    echo ""
    read -rp "Also purge configuration files? [y/N]: " PURGE
    if [[ "$PURGE" =~ ^[Yy] ]]; then
        apt-get purge -y \
            cups cups-client cups-bsd cups-filters \
            avahi-daemon avahi-utils \
            2>/dev/null || true
        log_info "Packages purged (configs removed)"
    fi

    apt-get autoremove -y
    log_info "CUPS and Avahi removed"
else
    # Just restart services to apply restored configs
    log_step "Restarting services with restored configs..."
    systemctl restart cups 2>/dev/null || true
    systemctl restart avahi-daemon 2>/dev/null || true
    log_info "Services restarted"
fi

# =========================================
# Step 6: Remove firewall rules
# =========================================

if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    if [[ "$UFW_STATUS" == *"active"* ]]; then
        echo ""
        log_step "Removing firewall rules..."
        ufw delete allow 631/tcp 2>/dev/null || true
        ufw delete allow 5353/udp 2>/dev/null || true
        log_info "Firewall rules removed"
    fi
fi

# =========================================
# Summary
# =========================================

echo ""
echo "========================================="
echo " Uninstall Complete"
echo "========================================="
echo ""
log_info "Print server has been removed."
echo ""
echo "If you want to reinstall, run:"
echo "  sudo ./01-setup.sh"
echo "  sudo ./02-configure-printers.sh"
echo "  sudo ./03-airprint.sh"
echo ""
