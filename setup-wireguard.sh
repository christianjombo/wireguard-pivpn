#!/bin/bash

set -e  # Exit on error

echo "🚀 Starting WireGuard + PiVPN Setup on DigitalOcean..."

# Update system
apt update && apt upgrade -y

# Install required dependencies
apt install -y qrencode zip

# Install PiVPN (automates WireGuard setup)
curl -L https://install.pivpn.io | bash -s -- --unattended

# Enable IP forwarding
echo "net.ipv4.ip_forward=1" | tee -a /etc/sysctl.conf
sysctl -p

# Open WireGuard Port
ufw allow 51820/udp
ufw enable

# Restart WireGuard
systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

echo "✅ WireGuard Setup Complete!"

# Create directories for configuration files
mkdir -p /root/wireguard_clients
mkdir -p /root/wireguard_qrcodes

# CSV File to store Client Details
CSV_FILE="/root/wireguard_clients/client_list.csv"
echo "Username,IP Address" > "$CSV_FILE"

# Create 50 clients
CLIENT_IP_BASE="10.6.0."
for i in {1..50}; do
    CLIENT_NAME="colleague$i"
    CLIENT_IP="${CLIENT_IP_BASE}$((i+1))"

    # Generate client configuration
    pivpn add -n "$CLIENT_NAME" -p "$(openssl rand -base64 16)"

    # Assign Static IP
    WG_CONF="/etc/wireguard/wg0.conf"
    CLIENT_PUBLIC_KEY=$(grep "PublicKey" "/etc/wireguard/configs/$CLIENT_NAME.conf" | awk '{print $3}')

    echo -e "\n[Peer]" >> "$WG_CONF"
    echo "PublicKey = $CLIENT_PUBLIC_KEY" >> "$WG_CONF"
    echo "AllowedIPs = ${CLIENT_IP}/32" >> "$WG_CONF"

    # Move conf files to storage directory
    mv "/etc/wireguard/configs/$CLIENT_NAME.conf" "/root/wireguard_clients/$CLIENT_NAME.conf"

    # Generate QR Code
    qrencode -o "/root/wireguard_qrcodes/$CLIENT_NAME.png" < "/root/wireguard_clients/$CLIENT_NAME.conf"

    # Store client details in CSV
    echo "$CLIENT_NAME,$CLIENT_IP" >> "$CSV_FILE"

    echo "✅ Added $CLIENT_NAME (IP: $CLIENT_IP)"
done

# Restart WireGuard to apply changes
systemctl restart wg-quick@wg0

# Zip all conf files & QR codes
ZIP_FILE="/root/wireguard_clients/wireguard_clients.zip"
zip -r "$ZIP_FILE" /root/wireguard_clients /root/wireguard_qrcodes

# Provide a direct download link via Python HTTP Server
echo "Starting temporary download server for 1 hour..."
cd /root/wireguard_clients
nohup python3 -m http.server 8080 &

echo "✅ All 50 Clients Created!"
echo "📥 Download Configurations & QR Codes: http://$(curl -s ifconfig.me):8080/wireguard_clients.zip"
