#!/usr/bin/env bash
# SHOW the switch's live counters + remembered state. Run:  sudo ./stats.sh
printf 'counter_read MyIngress.port_pkts 0\ncounter_read MyIngress.port_pkts 1\nregister_read MyIngress.fw_count 0\n' \
| docker run --rm -i --network host p4lang/behavioral-model \
    simple_switch_CLI --thrift-port 9090 | grep -iE "MyIngress|packets|=" || true
