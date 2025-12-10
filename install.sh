#!/bin/bash

# =============================================================================
# Duplicati Installation Script for Ubuntu/Debian (Multi-Architecture)
# Configures WebUI to listen on Tailscale interface, starts on boot
# Supports: amd64, arm64, armhf
#
# Repository: https://github.com/YOUR_USERNAME/tailscale-duplicati
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${CYAN}[STEP]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (use sudo)"
   exit 1
fi

# Get the actual user (not root)
ACTUAL_USER=${SUDO_USER:-$USER}
ACTUAL_HOME=$(eval echo ~$ACTUAL_USER)

echo ""
echo "=============================================="
echo "   Duplicati + Tailscale Installer"
echo "   Multi-Architecture Support"
echo "=============================================="
echo ""

# =============================================================================
# 1. Detect System Architecture
# =============================================================================
log_step "Detecting system architecture..."

# Multiple methods to detect architecture
if command -v dpkg &> /dev/null; then
    ARCH=$(dpkg --print-architecture)
elif command -v uname &> /dev/null; then
    UNAME_ARCH=$(uname -m)
    case $UNAME_ARCH in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l)  ARCH="armhf" ;;
        armv6l)  ARCH="armhf" ;;
        *)       ARCH="$UNAME_ARCH" ;;
    esac
else
    log_error "Cannot detect architecture"
    exit 1
fi

log_info "Architecture: $ARCH"
log_info "User: $ACTUAL_USER"
log_info "Home: $ACTUAL_HOME"

# =============================================================================
# 2. Check Tailscale
# =============================================================================
log_step "Checking Tailscale..."

if ! command -v tailscale &> /dev/null; then
    log_warn "Tailscale not found. Installing..."
    curl -fsSL https://tailscale.com/install.sh | sh
    log_warn "Tailscale installed. Run 'sudo tailscale up' to authenticate, then re-run this script."
    exit 1
fi

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "")
if [[ -z "$TAILSCALE_IP" ]]; then
    log_error "Tailscale not connected. Run 'sudo tailscale up' first."
    exit 1
fi
log_info "Tailscale IP: $TAILSCALE_IP"

# =============================================================================
# 3. Ask for WebUI Password
# =============================================================================
log_step "WebUI Password Configuration"

echo ""
while true; do
    read -s -p "Enter password for Duplicati WebUI: " WEBUI_PASSWORD
    echo ""
    
    if [[ -z "$WEBUI_PASSWORD" ]]; then
        log_error "Password cannot be empty"
        continue
    fi
    
    if [[ ${#WEBUI_PASSWORD} -lt 6 ]]; then
        log_error "Password must be at least 6 characters"
        continue
    fi
    
    read -s -p "Confirm password: " WEBUI_PASSWORD_CONFIRM
    echo ""
    
    if [[ "$WEBUI_PASSWORD" != "$WEBUI_PASSWORD_CONFIRM" ]]; then
        log_error "Passwords do not match. Please try again."
        continue
    fi
    
    log_info "Password configured"
    break
done
echo ""

# =============================================================================
# 4. Install Dependencies
# =============================================================================
log_step "Installing dependencies..."
apt-get update -qq
apt-get install -y -qq wget curl > /dev/null
log_info "Dependencies installed"

# =============================================================================
# 5. Download Duplicati from GitHub Releases
# =============================================================================
log_step "Downloading Duplicati..."

# Duplicati stable version
DUPLICATI_VERSION="2.2.0.1_stable_2025-11-09"

# Map architecture to Duplicati package naming
case $ARCH in
    amd64|x86_64)
        PKG_ARCH="x64"
        ;;
    arm64|aarch64)
        PKG_ARCH="arm64"
        ;;
    armhf|armv7l|armv6l)
        PKG_ARCH="arm7"
        ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        log_error "Supported: amd64, arm64, armhf"
        exit 1
        ;;
esac

# GitHub release URL format: duplicati-VERSION-linux-ARCH-gui.deb
DEB_FILENAME="duplicati-${DUPLICATI_VERSION}-linux-${PKG_ARCH}-gui.deb"
DEB_URL="https://github.com/duplicati/duplicati/releases/download/v${DUPLICATI_VERSION}/${DEB_FILENAME}"

log_info "Version: $DUPLICATI_VERSION"
log_info "Package: $DEB_FILENAME"

# Download
cd /tmp
if ! wget -q --show-progress -O duplicati.deb "$DEB_URL"; then
    log_error "Download failed from $DEB_URL"
    log_info "Check releases at: https://github.com/duplicati/duplicati/releases"
    exit 1
fi

log_info "Download complete"

# =============================================================================
# 6. Install Duplicati
# =============================================================================
log_step "Installing Duplicati..."

# Install package and dependencies
apt-get install -y ./duplicati.deb
rm -f duplicati.deb

log_info "Duplicati installed"

# =============================================================================
# 7. Configure Systemd Service for Tailscale
# =============================================================================
log_step "Configuring systemd service..."

# Stop and disable default service if exists
systemctl stop duplicati 2>/dev/null || true
systemctl disable duplicati 2>/dev/null || true

# Create custom service that binds to Tailscale IP with password
cat > /etc/systemd/system/duplicati.service << EOF
[Unit]
Description=Duplicati Backup Service (Tailscale)
After=network-online.target tailscaled.service
Wants=network-online.target tailscaled.service

[Service]
Type=simple
User=$ACTUAL_USER
Group=$ACTUAL_USER
ExecStart=/usr/bin/duplicati-server \\
    --webservice-interface=$TAILSCALE_IP \\
    --webservice-port=8200 \\
    --webservice-password=$WEBUI_PASSWORD \\
    --server-datafolder=$ACTUAL_HOME/.config/Duplicati
Restart=on-failure
RestartSec=10
TimeoutStopSec=20

[Install]
WantedBy=multi-user.target
EOF

# Secure the service file (contains password)
chmod 600 /etc/systemd/system/duplicati.service

# Create config directory with correct permissions
mkdir -p "$ACTUAL_HOME/.config/Duplicati"
chown -R "$ACTUAL_USER:$ACTUAL_USER" "$ACTUAL_HOME/.config/Duplicati"

log_info "Service configured"

# =============================================================================
# 8. Create Helper Scripts
# =============================================================================
log_step "Creating helper scripts..."

# Script to update Tailscale IP if it changes
cat > /usr/local/bin/duplicati-update-ip << 'SCRIPT'
#!/bin/bash
# Updates Duplicati service with current Tailscale IP

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error:${NC} This script must be run as root (use sudo)"
   exit 1
fi

NEW_IP=$(tailscale ip -4 2>/dev/null)
if [[ -z "$NEW_IP" ]]; then
    echo -e "${RED}Error:${NC} Tailscale not connected"
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/duplicati.service"
CURRENT_IP=$(grep -oP 'webservice-interface=\K[0-9.]+' "$SERVICE_FILE" 2>/dev/null)

if [[ "$NEW_IP" != "$CURRENT_IP" ]]; then
    sed -i "s/webservice-interface=[0-9.]*/webservice-interface=$NEW_IP/" "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl restart duplicati
    echo -e "${GREEN}Updated:${NC} Duplicati now listening on $NEW_IP:8200"
else
    echo -e "${GREEN}OK:${NC} IP unchanged ($CURRENT_IP:8200)"
fi
SCRIPT

# Script to show status
cat > /usr/local/bin/duplicati-status << 'SCRIPT'
#!/bin/bash
# Shows Duplicati status and access URL

echo ""
echo "=== Duplicati Status ==="
echo ""

# Service status
if systemctl is-active --quiet duplicati; then
    echo -e "Service:   \033[0;32m● Running\033[0m"
else
    echo -e "Service:   \033[0;31m○ Stopped\033[0m"
fi

# Get current IP from service
IP=$(grep -oP 'webservice-interface=\K[0-9.]+' /etc/systemd/system/duplicati.service 2>/dev/null)
if [[ -n "$IP" ]]; then
    echo "WebUI:     http://$IP:8200"
fi

# Tailscale status
TS_IP=$(tailscale ip -4 2>/dev/null)
if [[ -n "$TS_IP" ]]; then
    echo -e "Tailscale: \033[0;32m$TS_IP\033[0m"
    if [[ "$TS_IP" != "$IP" ]]; then
        echo ""
        echo -e "\033[1;33m⚠ Warning:\033[0m Tailscale IP changed!"
        echo "  Run: sudo duplicati-update-ip"
    fi
else
    echo -e "Tailscale: \033[0;31mNot connected\033[0m"
fi

echo ""
SCRIPT

# Script to change password
cat > /usr/local/bin/duplicati-change-password << 'SCRIPT'
#!/bin/bash
# Change Duplicati WebUI password

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error:${NC} This script must be run as root (use sudo)"
   exit 1
fi

echo ""
read -s -p "Enter new password: " NEW_PASS
echo ""

if [[ -z "$NEW_PASS" ]]; then
    echo -e "${RED}Error:${NC} Password cannot be empty"
    exit 1
fi

if [[ ${#NEW_PASS} -lt 6 ]]; then
    echo -e "${RED}Error:${NC} Password must be at least 6 characters"
    exit 1
fi

read -s -p "Confirm new password: " NEW_PASS_CONFIRM
echo ""

if [[ "$NEW_PASS" != "$NEW_PASS_CONFIRM" ]]; then
    echo -e "${RED}Error:${NC} Passwords do not match"
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/duplicati.service"
sed -i "s/--webservice-password=.*/--webservice-password=$NEW_PASS \\\\/" "$SERVICE_FILE"

systemctl daemon-reload
systemctl restart duplicati

echo ""
echo -e "${GREEN}Success:${NC} Password updated"
echo ""
SCRIPT

chmod +x /usr/local/bin/duplicati-update-ip
chmod +x /usr/local/bin/duplicati-status
chmod +x /usr/local/bin/duplicati-change-password

log_info "Helper scripts created"

# =============================================================================
# 9. Enable and Start Service
# =============================================================================
log_step "Starting Duplicati service..."

systemctl daemon-reload
systemctl enable duplicati
systemctl start duplicati

# Wait and verify
sleep 3
if systemctl is-active --quiet duplicati; then
    log_info "Service started successfully"
else
    log_warn "Service may have issues"
    log_warn "Check logs: journalctl -u duplicati -n 50"
fi

# =============================================================================
# 10. Summary
# =============================================================================
echo ""
echo "=============================================="
echo -e "${GREEN}     Installation Complete!${NC}"
echo "=============================================="
echo ""
echo "  System:     $(uname -s) $(uname -m) ($ARCH)"
echo "  Version:    Duplicati $DUPLICATI_VERSION"
echo "  User:       $ACTUAL_USER"
echo ""
echo -e "  ${CYAN}WebUI:${NC}       http://$TAILSCALE_IP:8200"
echo -e "  ${CYAN}Password:${NC}    (as configured during setup)"
echo ""
echo "  Commands:"
echo "    duplicati-status           - Show status & URL"
echo "    duplicati-update-ip        - Update after IP change"
echo "    duplicati-change-password  - Change WebUI password"
echo ""
echo "  Service:"
echo "    sudo systemctl restart duplicati"
echo "    sudo journalctl -u duplicati -f"
echo ""
echo "=============================================="
echo ""
