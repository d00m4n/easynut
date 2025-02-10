#!/bin/bash

# Configuration variables
UPS_NAME="ups"                      # UPS name
UPS_DESC="Auto-configured UPS"      # UPS description
ADMIN_USER="admin"                  # Admin username
ADMIN_PASS="admin_nut"             # Admin password
MON_USER="monuser"                 # Monitor username
MON_PASS="mon_nut"                 # Monitor password
UPS_DRIVER="usbhid-ups"           # UPS driver
UPS_PORT="auto"                    # UPS port

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to display messages
show_message() {
    echo -e "${GREEN}[*] $1${NC}"
}

show_error() {
    echo -e "${RED}[!] ERROR: $1${NC}"
}

show_warning() {
    echo -e "${YELLOW}[!] WARNING: $1${NC}"
}

# Function to get installation type
get_install_type() {
    while true; do
        echo -e "\nSelect installation type:"
        echo "1) Local installation (standalone)"
        echo "2) Network server installation (network accessible)"
        read -p "Enter your choice (1/2): " choice
        case $choice in
            1) INSTALL_TYPE="standalone"; break;;
            2) INSTALL_TYPE="netserver"; break;;
            *) echo "Please enter 1 or 2";;
        esac
    done
}

# Function to get network configuration if needed
get_network_config() {
    if [ "$INSTALL_TYPE" = "netserver" ]; then
        echo -e "\nNetwork Configuration:"
        echo "1) Allow connections from anywhere (0.0.0.0)"
        echo "2) Allow connections from specific network (e.g., 192.168.1.0/24)"
        read -p "Enter your choice (1/2): " net_choice
        
        case $net_choice in
            1) LISTEN_ADDRESS="0.0.0.0";;
            2) 
                read -p "Enter network address (e.g., 192.168.1.0/24): " LISTEN_ADDRESS
                ;;
            *) 
                show_warning "Invalid choice, defaulting to 0.0.0.0"
                LISTEN_ADDRESS="0.0.0.0"
                ;;
        esac
    fi
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    show_error "This script must be run as root (sudo)"
    exit 1
fi

# Get installation configuration
get_install_type
get_network_config

# Install NUT
show_message "Updating repositories..."
apt update || { show_error "Error updating repositories"; exit 1; }

show_message "Installing NUT..."
apt install -y nut || { show_error "Error installing NUT"; exit 1; }

# Configure NUT
show_message "Configuring NUT..."

# Backup configuration files
show_message "Creating backup of configuration files..."
cp /etc/nut/nut.conf /etc/nut/nut.conf.bak 2>/dev/null
cp /etc/nut/ups.conf /etc/nut/ups.conf.bak 2>/dev/null
cp /etc/nut/upsd.users /etc/nut/upsd.users.bak 2>/dev/null
cp /etc/nut/upsmon.conf /etc/nut/upsmon.conf.bak 2>/dev/null
[ "$INSTALL_TYPE" = "netserver" ] && cp /etc/nut/upsd.conf /etc/nut/upsd.conf.bak 2>/dev/null

# Configure mode
show_message "Configuring operation mode..."
echo "MODE=$INSTALL_TYPE" > /etc/nut/nut.conf

# Configure ups.conf
show_message "Configuring ups.conf..."
cat > /etc/nut/ups.conf << EOL
[${UPS_NAME}]
    driver = ${UPS_DRIVER}
    port = ${UPS_PORT}
    desc = "${UPS_DESC}"
EOL

# Configure upsd.users
show_message "Configuring upsd.users..."
cat > /etc/nut/upsd.users << EOL
[${ADMIN_USER}]
    password = ${ADMIN_PASS}
    actions = SET
    instcmds = ALL

[${MON_USER}]
    password = ${MON_PASS}
    upsmon master
EOL

# Configure upsmon.conf
show_message "Configuring upsmon.conf..."
cat > /etc/nut/upsmon.conf << EOL
MONITOR ${UPS_NAME}@localhost 1 ${MON_USER} ${MON_PASS} master
EOL

# Configure network settings if netserver
if [ "$INSTALL_TYPE" = "netserver" ]; then
    show_message "Configuring network settings..."
    cat > /etc/nut/upsd.conf << EOL
LISTEN ${LISTEN_ADDRESS}
EOL
    
    show_message "Checking firewall..."
    if command -v ufw >/dev/null 2>&1; then
        show_message "Opening port 3493 in UFW firewall..."
        ufw allow 3493/tcp >/dev/null 2>&1
    fi
fi

# Set permissions
show_message "Setting permissions..."
chmod 640 /etc/nut/*.conf
chown root:nut /etc/nut/*.conf

# Restart services
show_message "Restarting services..."
systemctl enable nut-server
systemctl enable nut-client
systemctl restart nut-server
systemctl restart nut-client

# Check installation
show_message "Checking installation..."
if systemctl is-active --quiet nut-server && systemctl is-active --quiet nut-client; then
    show_message "Installation completed successfully!"
    show_message "Admin user: ${ADMIN_USER}"
    show_message "Monitor user: ${MON_USER}"
    show_warning "IMPORTANT: Change default passwords by editing /etc/nut/upsd.users"
    show_message "To check UPS status run: upsc ${UPS_NAME}@localhost"
    
    if [ "$INSTALL_TYPE" = "netserver" ]; then
        show_message "Network configuration:"
        show_message "- Listening on: ${LISTEN_ADDRESS}"
        show_message "- Port: 3493"
        show_message "- For remote monitoring use: upsc ${UPS_NAME}@SERVER_IP"
    fi
else
    show_error "There was a problem with the installation. Check logs with 'journalctl -xe'"
fi
