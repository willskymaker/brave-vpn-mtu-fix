#!/bin/bash
# Riduce la MTU dell'interfaccia tunnel VPN per risolvere il timeout
# di Brave/Chrome sui siti interni aziendali.
#
# Uso:  sudo ./fix-mtu.sh [mtu] [interfaccia]
#   mtu          default: 1280
#   interfaccia  default: tun0

MTU="${1:-1280}"
IFACE="${2:-tun0}"

if ! ip link show "$IFACE" &>/dev/null; then
    echo "Interfaccia $IFACE non trovata. La VPN è connessa?"
    exit 1
fi

CURRENT_MTU=$(ip link show "$IFACE" | grep -oP 'mtu \K[0-9]+')
echo "MTU attuale su $IFACE: $CURRENT_MTU"

ip link set dev "$IFACE" mtu "$MTU"
echo "MTU impostata a $MTU su $IFACE"
