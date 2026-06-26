#!/usr/bin/env bash
# UNBLOCK (remove all firewall rules). Run:  sudo ./unblock.sh
echo "table_clear MyIngress.acl" \
| docker run --rm -i --network host p4lang/behavioral-model \
    simple_switch_CLI --thrift-port 9090 >/dev/null
echo ">> UNBLOCKED — traffic flows again"
