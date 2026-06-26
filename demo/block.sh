#!/usr/bin/env bash
# BLOCK traffic to Laptop B (10.0.0.2). Run:  sudo ./block.sh
echo "table_add MyIngress.acl MyIngress.drop 10.0.0.2&&&0xffffffff => 1" \
| docker run --rm -i --network host p4lang/behavioral-model \
    simple_switch_CLI --thrift-port 9090 | grep -i "entry\|error" || true
echo ">> BLOCKED 10.0.0.2"
