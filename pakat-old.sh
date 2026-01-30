#!/bin/bash
set -e

INSTALL_DIR="/root/packettunnel"
SERVICE_FILE="/etc/systemd/system/packettunnel.service"
CORE_URL="https://raw.githubusercontent.com/NIKA1371/pakat-old/main/core.json"
WATERWALL_URL="https://raw.githubusercontent.com/NIKA1371/pakat-old/main/Waterwall"

log() {
    echo -e "[+] $1"
}

# uninstall
if [[ "$1" == "--uninstall" ]]; then
    systemctl stop packettunnel.service 2>/dev/null || true
    systemctl disable packettunnel.service 2>/dev/null || true
    systemctl stop packettunnel-restart.timer 2>/dev/null || true
    systemctl disable packettunnel-restart.timer 2>/dev/null || true
    pkill -f Waterwall 2>/dev/null || true
    rm -rf /root/packettunnel
    rm -f /etc/systemd/system/packettunnel*
    systemctl daemon-reexec
    systemctl daemon-reload
    echo "Removed."
    exit 0
fi

ROLE=""
IP_IRAN=""
IP_KHAREJ=""
PORTS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --role) ROLE="$2"; shift 2 ;;
        --ip-iran) IP_IRAN="$2"; shift 2 ;;
        --ip-kharej) IP_KHAREJ="$2"; shift 2 ;;
        --ports)
            shift
            while [[ "$1" =~ ^[0-9]+$ ]]; do
                PORTS+=("$1")
                shift || break
            done ;;
        *) echo "Unknown option $1"; exit 1 ;;
    esac
done

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

curl -fsSL "$WATERWALL_URL" -o Waterwall
chmod +x Waterwall
curl -fsSL "$CORE_URL" -o core.json

##################################
# IRAN CONFIG
##################################
if [[ "$ROLE" == "iran" ]]; then
cat > config.json <<EOF
{
  "name": "iran",
  "nodes": [
    { "name": "tun", "type": "TunDevice",
      "settings": { "device-name": "wtun0", "device-ip": "10.10.0.1/24" },
      "next": "srcip" },

    { "name": "srcip", "type": "IpOverrider",
      "settings": { "direction": "up", "mode": "source-ip", "ipv4": "$IP_IRAN" },
      "next": "dstip" },

    { "name": "dstip", "type": "IpOverrider",
      "settings": { "direction": "up", "mode": "dest-ip", "ipv4": "$IP_KHAREJ" },
      "next": "manip" },

    { "name": "manip", "type": "IpManipulator",
      "settings": {
        "protoswap": 253,
        "up-tcp-bit-ack": "packet->fin",
        "up-tcp-bit-fin": "packet->ack",
        "dw-tcp-bit-fin": "packet->ack",
        "dw-tcp-bit-ack": "packet->fin"
      },
      "next": "dnsrc" },

    { "name": "dnsrc", "type": "IpOverrider",
      "settings": { "direction": "down", "mode": "source-ip", "ipv4": "10.10.0.2" },
      "next": "dndst" },

    { "name": "dndst", "type": "IpOverrider",
      "settings": { "direction": "down", "mode": "dest-ip", "ipv4": "10.10.0.1" },
      "next": "stream" },

    { "name": "stream", "type": "RawSocket",
      "settings": { "capture-filter-mode": "source-ip", "capture-ip": "$IP_KHAREJ" } },
EOF

base_port=30083
skip_port=30087

for i in "${!PORTS[@]}"; do
  while [[ $base_port -eq $skip_port ]]; do ((base_port++)); done
  cat >> config.json <<EOF
    { "name": "input$((i+1))", "type": "TcpListener",
      "settings": { "address": "0.0.0.0", "port": ${PORTS[$i]}, "nodelay": true },
      "next": "hd$((i+1))" },

    { "name": "hd$((i+1))", "type": "HalfDuplexClient",
      "settings": {}, "next": "obfs_client$((i+1))" },

    { "name": "obfs_client$((i+1))", "type": "ObfuscatorClient",
      "settings": { "method": "xor", "xor_key": 123 },
      "next": "mux_out$((i+1))" },

    { "name": "mux_out$((i+1))", "type": "MuxClient",
      "settings": { "mode": "counter", "connection-capacity": 8 },
      "next": "out$((i+1))" },

    { "name": "out$((i+1))", "type": "TcpConnector",
      "settings": { "address": "10.10.0.2", "port": $base_port, "nodelay": true } },
EOF
  ((base_port++))
done

sed -i '$ s/,$//' config.json
echo "  ] }" >> config.json
fi

##################################
# KHAREJ CONFIG
##################################
if [[ "$ROLE" == "kharej" ]]; then
cat > config.json <<EOF
{
  "name": "kharej",
  "nodes": [
    { "name": "tun", "type": "TunDevice",
      "settings": { "device-name": "wtun0", "device-ip": "10.10.0.1/24" },
      "next": "srcip" },

    { "name": "srcip", "type": "IpOverrider",
      "settings": { "direction": "up", "mode": "source-ip", "ipv4": "$IP_KHAREJ" },
      "next": "dstip" },

    { "name": "dstip", "type": "IpOverrider",
      "settings": { "direction": "up", "mode": "dest-ip", "ipv4": "$IP_IRAN" },
      "next": "manip" },

    { "name": "manip", "type": "IpManipulator",
      "settings": {
        "protoswap": 253,
        "up-tcp-bit-ack": "packet->fin",
        "up-tcp-bit-fin": "packet->ack",
        "dw-tcp-bit-fin": "packet->ack",
        "dw-tcp-bit-ack": "packet->fin"
      },
      "next": "dnsrc" },

    { "name": "dnsrc", "type": "IpOverrider",
      "settings": { "direction": "down", "mode": "source-ip", "ipv4": "10.10.0.2" },
      "next": "dndst" },

    { "name": "dndst", "type": "IpOverrider",
      "settings": { "direction": "down", "mode": "dest-ip", "ipv4": "10.10.0.1" },
      "next": "stream" },

    { "name": "stream", "type": "RawSocket",
      "settings": { "capture-filter-mode": "source-ip", "capture-ip": "$IP_IRAN" } },
EOF

base_port=30083
skip_port=30087

for i in "${!PORTS[@]}"; do
  while [[ $base_port -eq $skip_port ]]; do ((base_port++)); done
  cat >> config.json <<EOF
    { "name": "input$((i+1))", "type": "TcpListener",
      "settings": { "address": "0.0.0.0", "port": $base_port, "nodelay": true },
      "next": "mux_in$((i+1))" },

    { "name": "mux_in$((i+1))", "type": "MuxServer",
      "settings": {}, "next": "hd$((i+1))" },

    { "name": "hd$((i+1))", "type": "HalfDuplexServer",
      "settings": {}, "next": "obfs_server$((i+1))" },

    { "name": "obfs_server$((i+1))", "type": "ObfuscatorServer",
      "settings": { "method": "xor", "xor_key": 123 },
      "next": "out$((i+1))" },

    { "name": "out$((i+1))", "type": "TcpConnector",
      "settings": { "address": "127.0.0.1", "port": ${PORTS[$i]}, "nodelay": true } },
EOF
  ((base_port++))
done

sed -i '$ s/,$//' config.json
echo "  ] }" >> config.json
fi

##################################
# SERVICE
##################################
cat > /etc/systemd/system/packettunnel.service <<EOF
[Unit]
Description=PacketTunnel
After=network.target

[Service]
ExecStartPre=/bin/bash -c "ip link delete wtun0 || true"
ExecStart=$INSTALL_DIR/Waterwall
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now packettunnel.service
echo "PacketTunnel running."
