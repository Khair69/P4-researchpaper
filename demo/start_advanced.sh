#!/usr/bin/env bash
# ONE command for the stateful (auto-block + telemetry) demo.
# Run on the server:   sudo ./start_advanced.sh
set -e
IF1=enp3s0
IF2=enx9c69d33a9f57
DIR="$(cd "$(dirname "$0")" && pwd)"; cd "$DIR"

echo "[1/3] Preparing network ports..."
ip addr flush dev "$IF1"; ip addr flush dev "$IF2"
ip link set "$IF1" up promisc on
ip link set "$IF2" up promisc on

echo "[2/3] Compiling stateful program if needed..."
if [ ! -f "$DIR/stateful_firewall.json" ]; then
  docker run --rm -v "$DIR":/work -w /work p4lang/p4c \
    p4c --target bmv2 --arch v1model stateful_firewall.p4
fi

echo "[3/3] Starting the stateful P4 switch..."
docker rm -f p4sw >/dev/null 2>&1 || true
docker run -d --name p4sw --privileged --network host -v "$DIR":/work -w /work \
  p4lang/behavioral-model \
  simple_switch -i 0@"$IF1" -i 1@"$IF2" stateful_firewall.json --thrift-port 9090 >/dev/null
sleep 2
if docker ps --format '{{.Names}}' | grep -q '^p4sw$'; then
  echo "===================================================="
  echo " Stateful switch is UP. On Laptop A run:  ping -t 10.0.0.2"
  echo "   SHOW live telemetry:   sudo ./stats.sh"
  echo "   (ping auto-blocks after ~20 packets, by itself)"
  echo "   RESET its memory:      sudo ./reset.sh   (ping resumes)"
  echo "===================================================="
else
  echo "!! switch did not start. See logs:  docker logs p4sw"
fi
