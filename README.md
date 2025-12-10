# tailscale-duplicati

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Linux-green.svg)](https://www.linux.org/)
[![Architecture](https://img.shields.io/badge/Arch-amd64%20|%20arm64%20|%20armhf-orange.svg)](#supported-architectures)

One-click installer for [Duplicati](https://duplicati.com) backup server with [Tailscale](https://tailscale.com) VPN integration. Access your backup dashboard securely from anywhere on your Tailscale network.

## Features

- 🚀 **One-command installation** - Fully automated setup
- 🔒 **Secure by default** - WebUI accessible only via Tailscale VPN
- 🖥️ **Multi-architecture** - Supports amd64, arm64, and armhf (Raspberry Pi)
- 🔑 **Password protected** - Interactive password setup during installation
- 🔄 **Auto-start** - Runs as systemd service on boot
- 🛠️ **Helper scripts** - Easy management commands included

## Quick Start

```bash
# Download the installer
wget https://raw.githubusercontent.com/YOUR_USERNAME/tailscale-duplicati/main/install.sh

# Make it executable
chmod +x install.sh

# Run the installer
sudo ./install.sh
```

## Requirements

- Ubuntu/Debian-based Linux distribution
- Root access (sudo)
- Tailscale installed and connected (`tailscale up`)
- Internet connection for downloading packages

## Supported Architectures

| Architecture | Devices |
|--------------|---------|
| `amd64` | Standard PCs, servers, cloud VMs |
| `arm64` | Raspberry Pi 4/5, Oracle Cloud ARM, Apple Silicon VMs |
| `armhf` | Raspberry Pi 3 and older, some NAS devices |

## What Gets Installed

- **Duplicati** (latest stable) - Backup software with web interface
- **Systemd service** - Auto-starts Duplicati on boot
- **Helper scripts** - Management utilities in `/usr/local/bin/`

## Usage

After installation, access the Duplicati WebUI at:

```
http://<your-tailscale-ip>:8200
```

Use the password you configured during installation.

### Helper Commands

| Command | Description |
|---------|-------------|
| `duplicati-status` | Show service status and WebUI URL |
| `duplicati-update-ip` | Update config if Tailscale IP changes |
| `duplicati-change-password` | Change the WebUI password |

### Service Management

```bash
# Check status
sudo systemctl status duplicati

# Restart service
sudo systemctl restart duplicati

# View logs
sudo journalctl -u duplicati -f

# Stop service
sudo systemctl stop duplicati
```

## Configuration

### Default Settings

| Setting | Value |
|---------|-------|
| WebUI Port | `8200` |
| Interface | Tailscale IP only |
| Data folder | `~/.config/Duplicati` |
| Service user | Current user (or root) |

### Changing the Port

Edit the systemd service file:

```bash
sudo nano /etc/systemd/system/duplicati.service
```

Change `--webservice-port=8200` to your desired port, then:

```bash
sudo systemctl daemon-reload
sudo systemctl restart duplicati
```

## Security

This installer configures Duplicati to:

1. **Listen only on Tailscale interface** - Not exposed to public internet
2. **Require password authentication** - Set during installation
3. **Protect service file** - Contains password, readable only by root

### Best Practices

- Use a strong, unique password
- Keep Tailscale updated
- Regularly update Duplicati via the WebUI
- Enable Tailscale ACLs to restrict access if needed

## Troubleshooting

### Service won't start

```bash
# Check logs for errors
sudo journalctl -u duplicati -n 50

# Verify Tailscale is connected
tailscale status
```

### Can't access WebUI

1. Verify you're connected to Tailscale
2. Check the correct IP: `tailscale ip -4`
3. Ensure the service is running: `duplicati-status`
4. If Tailscale IP changed: `sudo duplicati-update-ip`

### Forgot password

```bash
sudo duplicati-change-password
```

### Port already in use

Change the port in the service file (see [Changing the Port](#changing-the-port)).

## Uninstallation

```bash
# Stop and disable service
sudo systemctl stop duplicati
sudo systemctl disable duplicati

# Remove service file
sudo rm /etc/systemd/system/duplicati.service

# Remove helper scripts
sudo rm /usr/local/bin/duplicati-*

# Remove Duplicati package
sudo apt remove duplicati

# Optional: Remove configuration data
rm -rf ~/.config/Duplicati
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Duplicati](https://duplicati.com) - Free backup software
- [Tailscale](https://tailscale.com) - Zero-config VPN

## Author

Created with ❤️ for the self-hosting community.

---

**⭐ If this project helped you, consider giving it a star!**
