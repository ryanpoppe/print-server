#!/bin/bash
#
# 04-maintenance.sh - Print Server Maintenance Utility
#
# Interactive menu for monitoring and maintaining the print server.
# Can also be called with command-line arguments for scripted use.
#
# Usage:
#   sudo ./04-maintenance.sh            # Interactive menu
#   sudo ./04-maintenance.sh status     # Show printer status
#   sudo ./04-maintenance.sh queue      # Show print queue
#   sudo ./04-maintenance.sh health     # System health check
#   sudo ./04-maintenance.sh logs       # View CUPS error log
#   sudo ./04-maintenance.sh restart    # Restart CUPS and Avahi
#   sudo ./04-maintenance.sh clear      # Clear all print queues
#   sudo ./04-maintenance.sh usb        # Check USB devices
#   sudo ./04-maintenance.sh test       # Print test page
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

# --- Check root ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

# =========================================
# Maintenance Functions
# =========================================

show_printer_status() {
    echo ""
    echo -e "${BOLD}=== Printer Status ===${NC}"
    echo ""

    # Overall status
    lpstat -p -d 2>/dev/null || log_warn "No printers configured"
    echo ""

    # Detailed per-printer info
    for PRINTER in $(lpstat -p 2>/dev/null | awk '{print $2}'); do
        echo -e "${CYAN}--- $PRINTER ---${NC}"
        lpstat -p "$PRINTER" -l 2>/dev/null || true
        echo "  URI: $(lpstat -s 2>/dev/null | grep "$PRINTER" | awk '{print $NF}')"
        echo ""
    done

    # Service status
    echo -e "${BOLD}Service Status:${NC}"
    printf "  CUPS:  "
    if systemctl is-active --quiet cups; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi
    printf "  Avahi: "
    if systemctl is-active --quiet avahi-daemon; then
        echo -e "${GREEN}running${NC}"
    else
        echo -e "${RED}stopped${NC}"
    fi
    echo ""
}

show_print_queue() {
    echo ""
    echo -e "${BOLD}=== Print Queue ===${NC}"
    echo ""

    QUEUE=$(lpstat -o 2>/dev/null || true)
    if [[ -z "$QUEUE" ]]; then
        log_info "All print queues are empty"
    else
        echo "$QUEUE"
    fi
    echo ""
}

clear_print_queue() {
    echo ""
    echo -e "${BOLD}=== Clearing Print Queues ===${NC}"
    echo ""

    for PRINTER in $(lpstat -p 2>/dev/null | awk '{print $2}'); do
        JOBS=$(lpstat -o "$PRINTER" 2>/dev/null | wc -l)
        if [[ $JOBS -gt 0 ]]; then
            cancel -a "$PRINTER"
            log_info "Cleared $JOBS job(s) from $PRINTER"
        else
            log_info "$PRINTER: queue already empty"
        fi
    done
    echo ""
}

cancel_specific_job() {
    echo ""
    echo -e "${BOLD}=== Cancel Specific Job ===${NC}"
    echo ""

    QUEUE=$(lpstat -o 2>/dev/null || true)
    if [[ -z "$QUEUE" ]]; then
        log_info "No jobs in queue to cancel"
        return
    fi

    echo "Current jobs:"
    echo "$QUEUE"
    echo ""
    read -rp "Enter job ID to cancel (e.g., HP-LaserJet-1320-1): " JOB_ID

    if [[ -n "$JOB_ID" ]]; then
        cancel "$JOB_ID" 2>/dev/null && log_info "Job $JOB_ID cancelled" || log_error "Failed to cancel job $JOB_ID"
    fi
    echo ""
}

restart_services() {
    echo ""
    echo -e "${BOLD}=== Restarting Services ===${NC}"
    echo ""

    log_info "Restarting CUPS..."
    systemctl restart cups
    sleep 2
    if systemctl is-active --quiet cups; then
        log_info "CUPS: restarted successfully"
    else
        log_error "CUPS: failed to restart"
    fi

    log_info "Restarting Avahi..."
    systemctl restart avahi-daemon
    sleep 1
    if systemctl is-active --quiet avahi-daemon; then
        log_info "Avahi: restarted successfully"
    else
        log_error "Avahi: failed to restart"
    fi
    echo ""
}

check_usb_devices() {
    echo ""
    echo -e "${BOLD}=== USB Devices ===${NC}"
    echo ""

    echo "All USB devices:"
    lsusb
    echo ""

    echo "Printer-related devices:"
    lsusb | grep -iE "(dymo|hewlett|hp|printer)" || log_warn "No printer USB devices detected"
    echo ""

    echo "CUPS-detected USB devices:"
    lpinfo -v 2>/dev/null | grep "usb://" || log_warn "No USB printer URIs detected by CUPS"
    echo ""
}

view_cups_logs() {
    echo ""
    echo -e "${BOLD}=== CUPS Error Log (last 50 lines) ===${NC}"
    echo ""

    CUPS_LOG="/var/log/cups/error_log"
    if [[ -f "$CUPS_LOG" ]]; then
        tail -50 "$CUPS_LOG"
    else
        log_warn "CUPS error log not found at $CUPS_LOG"
    fi
    echo ""
}

view_cups_access_logs() {
    echo ""
    echo -e "${BOLD}=== CUPS Access Log (last 30 lines) ===${NC}"
    echo ""

    CUPS_ACCESS_LOG="/var/log/cups/access_log"
    if [[ -f "$CUPS_ACCESS_LOG" ]]; then
        tail -30 "$CUPS_ACCESS_LOG"
    else
        log_warn "CUPS access log not found at $CUPS_ACCESS_LOG"
    fi
    echo ""
}

system_health() {
    echo ""
    echo -e "${BOLD}=== System Health ===${NC}"
    echo ""

    # CPU temperature
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_C=$((TEMP / 1000))
        TEMP_F=$(( (TEMP_C * 9 / 5) + 32 ))
        if [[ $TEMP_C -ge 80 ]]; then
            log_error "CPU Temperature: ${TEMP_C}C / ${TEMP_F}F (CRITICAL)"
        elif [[ $TEMP_C -ge 70 ]]; then
            log_warn "CPU Temperature: ${TEMP_C}C / ${TEMP_F}F (HIGH)"
        else
            log_info "CPU Temperature: ${TEMP_C}C / ${TEMP_F}F"
        fi
    fi

    # Memory
    echo ""
    echo "Memory usage:"
    free -h
    echo ""

    MEM_AVAILABLE_KB=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    MEM_AVAILABLE_MB=$((MEM_AVAILABLE_KB / 1024))
    if [[ $MEM_AVAILABLE_MB -lt 100 ]]; then
        log_warn "Available memory is low: ${MEM_AVAILABLE_MB}MB"
    else
        log_info "Available memory: ${MEM_AVAILABLE_MB}MB"
    fi

    # Disk space
    echo ""
    echo "Disk usage:"
    df -h / /var/log /var/spool 2>/dev/null | sort -u
    echo ""

    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    if [[ $DISK_USAGE -ge 90 ]]; then
        log_error "Root filesystem is ${DISK_USAGE}% full (CRITICAL)"
    elif [[ $DISK_USAGE -ge 80 ]]; then
        log_warn "Root filesystem is ${DISK_USAGE}% full"
    else
        log_info "Root filesystem is ${DISK_USAGE}% full"
    fi

    # Uptime and load
    echo ""
    echo "Uptime and load:"
    uptime
    echo ""

    # Network
    echo ""
    echo "Network:"
    PI_IP=$(hostname -I | awk '{print $1}')
    log_info "IP Address: $PI_IP"
    log_info "Hostname: $(hostname)"
    echo ""

    # CUPS spool size
    SPOOL_SIZE=$(du -sh /var/spool/cups 2>/dev/null | awk '{print $1}')
    log_info "CUPS spool size: ${SPOOL_SIZE:-unknown}"
    echo ""
}

print_test_page() {
    echo ""
    echo -e "${BOLD}=== Print Test Page ===${NC}"
    echo ""

    PRINTERS=$(lpstat -p 2>/dev/null | awk '{print $2}')
    if [[ -z "$PRINTERS" ]]; then
        log_warn "No printers configured"
        return
    fi

    echo "Available printers:"
    local i=1
    declare -a PRINTER_ARRAY
    while IFS= read -r p; do
        echo "  $i) $p"
        PRINTER_ARRAY[$i]="$p"
        ((i++))
    done <<< "$PRINTERS"

    echo ""
    read -rp "Select printer number (or 'q' to cancel): " CHOICE

    if [[ "$CHOICE" == "q" || -z "$CHOICE" ]]; then
        return
    fi

    SELECTED="${PRINTER_ARRAY[$CHOICE]:-}"
    if [[ -z "$SELECTED" ]]; then
        log_error "Invalid selection"
        return
    fi

    log_info "Sending test page to $SELECTED..."

    # Use lp to print CUPS test page
    lp -d "$SELECTED" /usr/share/cups/data/testprint 2>/dev/null \
        && log_info "Test page sent to $SELECTED" \
        || log_error "Failed to send test page. Try printing from CUPS web UI instead."
    echo ""
}

enable_debug_logging() {
    echo ""
    echo -e "${BOLD}=== Toggle CUPS Debug Logging ===${NC}"
    echo ""

    CURRENT_LEVEL=$(grep "^LogLevel" /etc/cups/cupsd.conf | awk '{print $2}')
    log_info "Current log level: $CURRENT_LEVEL"

    if [[ "$CURRENT_LEVEL" == "debug" || "$CURRENT_LEVEL" == "debug2" ]]; then
        read -rp "Debug logging is ON. Turn it OFF (set to 'warn')? [y/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy] ]]; then
            sed -i 's/^LogLevel.*/LogLevel warn/' /etc/cups/cupsd.conf
            systemctl restart cups
            log_info "Log level set to 'warn'. CUPS restarted."
        fi
    else
        read -rp "Enable debug logging? (generates verbose output) [y/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy] ]]; then
            sed -i 's/^LogLevel.*/LogLevel debug/' /etc/cups/cupsd.conf
            systemctl restart cups
            log_info "Log level set to 'debug'. CUPS restarted."
            log_info "View logs with: tail -f /var/log/cups/error_log"
        fi
    fi
    echo ""
}

clean_cups_spool() {
    echo ""
    echo -e "${BOLD}=== Clean CUPS Spool ===${NC}"
    echo ""

    SPOOL_SIZE=$(du -sh /var/spool/cups 2>/dev/null | awk '{print $1}')
    log_info "Current spool size: $SPOOL_SIZE"

    # Count completed/cancelled job files
    SPOOL_FILES=$(find /var/spool/cups -name "d*" -type f 2>/dev/null | wc -l)
    log_info "Spool data files: $SPOOL_FILES"

    read -rp "Clean completed job data from spool? [y/N]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Yy] ]]; then
        # Cancel all pending jobs first
        cancel -a 2>/dev/null || true
        # Clean old job files
        find /var/spool/cups -name "d*" -mtime +1 -delete 2>/dev/null || true
        find /var/spool/cups -name "c*" -mtime +1 -delete 2>/dev/null || true

        SPOOL_SIZE_AFTER=$(du -sh /var/spool/cups 2>/dev/null | awk '{print $1}')
        log_info "Spool cleaned. Size: $SPOOL_SIZE -> $SPOOL_SIZE_AFTER"
    fi
    echo ""
}

# =========================================
# CLI argument handling
# =========================================

if [[ $# -gt 0 ]]; then
    check_root
    case "$1" in
        status)   show_printer_status ;;
        queue)    show_print_queue ;;
        clear)    clear_print_queue ;;
        restart)  restart_services ;;
        usb)      check_usb_devices ;;
        logs)     view_cups_logs ;;
        health)   system_health ;;
        test)     print_test_page ;;
        debug)    enable_debug_logging ;;
        clean)    clean_cups_spool ;;
        *)
            echo "Usage: $0 [status|queue|clear|restart|usb|logs|health|test|debug|clean]"
            exit 1
            ;;
    esac
    exit 0
fi

# =========================================
# Interactive menu
# =========================================

check_root

while true; do
    echo ""
    echo -e "${BOLD}=========================================${NC}"
    echo -e "${BOLD} Print Server Maintenance${NC}"
    echo -e "${BOLD}=========================================${NC}"
    echo ""
    echo "  1)  Printer status"
    echo "  2)  View print queue"
    echo "  3)  Clear all print queues"
    echo "  4)  Cancel specific job"
    echo "  5)  Restart CUPS & Avahi"
    echo "  6)  Check USB devices"
    echo "  7)  View CUPS error log"
    echo "  8)  View CUPS access log"
    echo "  9)  System health check"
    echo "  10) Print test page"
    echo "  11) Toggle debug logging"
    echo "  12) Clean CUPS spool"
    echo ""
    echo "  q)  Quit"
    echo ""
    read -rp "Select option: " OPTION

    case "$OPTION" in
        1)  show_printer_status ;;
        2)  show_print_queue ;;
        3)  clear_print_queue ;;
        4)  cancel_specific_job ;;
        5)  restart_services ;;
        6)  check_usb_devices ;;
        7)  view_cups_logs ;;
        8)  view_cups_access_logs ;;
        9)  system_health ;;
        10) print_test_page ;;
        11) enable_debug_logging ;;
        12) clean_cups_spool ;;
        q|Q) echo "Goodbye."; exit 0 ;;
        *)  log_warn "Invalid option: $OPTION" ;;
    esac
done
