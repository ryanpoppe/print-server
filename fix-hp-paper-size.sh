#!/bin/bash
#
# fix-hp-paper-size.sh - Fix HP LaserJet 1320 paper size for AirPrint
#
# Patches the installed PPD and Avahi service file so iOS/AirPrint
# shows US Letter instead of A4/A5/A6/Envelope-DL.
#
# Run as root or with sudo on the Raspberry Pi.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root. Use: sudo $0"
    exit 1
fi

HP_NAME="HP-LaserJet-1320"
HP_PPD="/etc/cups/ppd/${HP_NAME}.ppd"
AVAHI_SERVICE="/etc/avahi/services/AirPrint-${HP_NAME}.service"
PI_HOSTNAME=$(hostname)

# =========================================
# Step 1: Patch the HP PPD
# =========================================

echo ""
echo "========================================="
echo " Fixing HP LaserJet 1320 paper sizes"
echo "========================================="
echo ""

if [[ ! -f "$HP_PPD" ]]; then
    log_error "HP PPD not found at $HP_PPD"
    log_error "Is the HP LaserJet 1320 configured in CUPS?"
    exit 1
fi

# Show current defaults
log_info "Current PPD defaults:"
grep "^\*Default\(PageSize\|PageRegion\|ImageableArea\|PaperDimension\)" "$HP_PPD" | sed 's/^/  /'
echo ""

# Back up original PPD
if [[ ! -f "${HP_PPD}.orig" ]]; then
    cp "$HP_PPD" "${HP_PPD}.orig"
    log_info "Backed up original PPD to ${HP_PPD}.orig"
else
    log_info "PPD backup already exists at ${HP_PPD}.orig"
fi

# Set all defaults to Letter
log_info "Setting default page size to Letter..."
sed -i 's/^\*DefaultPageSize:.*/\*DefaultPageSize: Letter/' "$HP_PPD"
sed -i 's/^\*DefaultPageRegion:.*/\*DefaultPageRegion: Letter/' "$HP_PPD"
sed -i 's/^\*DefaultImageableArea:.*/\*DefaultImageableArea: Letter/' "$HP_PPD"
sed -i 's/^\*DefaultPaperDimension:.*/\*DefaultPaperDimension: Letter/' "$HP_PPD"

# Comment out A4, A5, A6, EnvDL entries so iOS won't offer them
log_info "Removing international paper sizes (A4, A5, A6, Envelope DL)..."
for SIZE in A4 A5 A6 EnvDL; do
    sed -i "s|^\(\*PageSize ${SIZE}\)|%% DISABLED: \1|" "$HP_PPD"
    sed -i "s|^\(\*PageRegion ${SIZE}\)|%% DISABLED: \1|" "$HP_PPD"
    sed -i "s|^\(\*ImageableArea ${SIZE}\)|%% DISABLED: \1|" "$HP_PPD"
    sed -i "s|^\(\*PaperDimension ${SIZE}\)|%% DISABLED: \1|" "$HP_PPD"
done

# Verify Letter exists
if grep -q '^\*PageSize Letter' "$HP_PPD"; then
    log_info "PPD patched successfully"
else
    log_error "Letter page size not found in PPD. Restoring backup."
    cp "${HP_PPD}.orig" "$HP_PPD"
    exit 1
fi

# Show new defaults
echo ""
log_info "New PPD defaults:"
grep "^\*Default\(PageSize\|PageRegion\|ImageableArea\|PaperDimension\)" "$HP_PPD" | sed 's/^/  /'
echo ""

# =========================================
# Step 2: Patch the Avahi AirPrint service
# =========================================

log_info "Updating AirPrint service file..."

cat > "$AVAHI_SERVICE" << EOF
<?xml version='1.0' encoding='UTF-8'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">

<!--
  AirPrint service file for HP LaserJet 1320
  Patched by fix-hp-paper-size.sh for US Letter
-->

<service-group>
  <name replace-wildcards="yes">AirPrint HP LaserJet 1320 @ %h</name>

  <service>
    <type>_ipp._tcp</type>
    <subtype>_universal._sub._ipp._tcp</subtype>
    <port>631</port>
    <txt-record>txtvers=1</txt-record>
    <txt-record>qtotal=1</txt-record>
    <txt-record>rp=printers/HP-LaserJet-1320</txt-record>
    <txt-record>ty=HP LaserJet 1320</txt-record>
    <txt-record>adminurl=https://${PI_HOSTNAME}.local:631/printers/HP-LaserJet-1320</txt-record>
    <txt-record>note=HP LaserJet 1320</txt-record>
    <txt-record>priority=0</txt-record>
    <txt-record>product=(HP LaserJet 1320)</txt-record>
    <txt-record>pdl=application/octet-stream,application/pdf,application/postscript,image/jpeg,image/png,image/pwg-raster,image/urf</txt-record>
    <txt-record>URF=CP1,PQ3-4-5,RS300-600,SRGB24,W8,DM1</txt-record>
    <txt-record>TLS=1.2</txt-record>
    <txt-record>printer-state=3</txt-record>
    <txt-record>printer-type=0x801046</txt-record>
    <txt-record>media-default=na_letter_8.5x11in</txt-record>
    <txt-record>media-supported=na_letter_8.5x11in,na_legal_8.5x14in</txt-record>
  </service>
</service-group>
EOF

log_info "AirPrint service file updated with US Letter media"

# =========================================
# Step 3: Restart services
# =========================================

echo ""
log_info "Restarting CUPS..."
systemctl restart cups
sleep 2

if systemctl is-active --quiet cups; then
    log_info "CUPS: running"
else
    log_error "CUPS: failed to restart"
fi

log_info "Restarting Avahi..."
systemctl restart avahi-daemon
sleep 1

if systemctl is-active --quiet avahi-daemon; then
    log_info "Avahi: running"
else
    log_error "Avahi: failed to restart"
fi

# =========================================
# Done
# =========================================

echo ""
echo "========================================="
echo " Fix applied"
echo "========================================="
echo ""
echo "Changes made:"
echo "  - HP PPD default page size: Letter"
echo "  - Disabled sizes: A4, A5, A6, Envelope DL"
echo "  - AirPrint media-default: na_letter_8.5x11in"
echo "  - AirPrint media-supported: Letter, Legal"
echo ""
echo "On your phone, wait ~60 seconds or toggle Wi-Fi"
echo "off/on to refresh the printer discovery cache."
echo ""
echo "To undo this fix:"
echo "  sudo cp ${HP_PPD}.orig ${HP_PPD}"
echo "  sudo systemctl restart cups"
echo "  sudo systemctl restart avahi-daemon"
echo ""
