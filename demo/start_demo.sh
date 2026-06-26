#!/usr/bin/env bash
# ONE command to bring up the whole basic-firewall demo.
# Run on the server (locally, no Wi-Fi needed):   sudo ./start_demo.sh
set -e
IF1=enp3s0            # built-in Ethernet  -> Laptop A (10.0.0.1)
IF2=enx9c69d33a9f57   # USB adapter        -> Laptop B (10.0.0.2)
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$DIR"

echo "[1/3] Preparing network ports..."
ip addr flush dev "$IF1"; ip addr flush dev "$IF2"
ip link set "$IF1" up promisc on
ip link set "$IF2" up promisc on

echo "[2/3] Compiling P4 program if needed..."
if [ ! -f "$DIR/bridge_firewall.json" ]; then
  docker run --rm -v "$DIR":/work -w /work p4lang/p4c \
    p4c --target bmv2 --arch v1model bridge_firewall.p4
fi

echo "[3/3] Starting the P4 switch (background container 'p4sw')..."
docker rm -f p4sw >/dev/null 2>&1 || true
docker run -d --name p4sw --privileged --network host -v "$DIR":/work -w /work \
  p4lang/behavioral-model \
  simple_switch -i 0@"$IF1" -i 1@"$IF2" bridge_firewall.json --thrift-port 9090 >/dev/null
sleep 2
if docker ps --format '{{.Names}}' | grep -q '^p4sw$'; then
  echo "===================================================="
  echo " P4 switch is UP. On Laptop A run:  ping -t 10.0.0.2"
  echo "   BLOCK   the ping:   sudo ./block.sh"
  echo "   UNBLOCK the ping:   sudo ./unblock.sh"
  echo "===================================================="
else
  echo "!! switch did not start. See logs:  docker logs p4sw"
fi
