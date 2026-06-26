#!/usr/bin/env bash
# RESET the switch's memory so the auto-blocked ping resumes. Run:  sudo ./reset.sh
echo "register_write MyIngress.fw_count 0 0" \
| docker run --rm -i --network host p4lang/behavioral-model \
    simple_switch_CLI --thrift-port 9090 >/dev/null
echo ">> memory cleared — traffic resumes"
