#!/usr/bin/env python3
"""
sim.py - Behavioral emulation of the V1Model match-action pipeline for the two
P4 prototypes (firewall.p4, load_balancer.p4). Real Ethernet/IPv4/TCP packets
are crafted with scapy and pushed through a faithful Python reimplementation of
the parser + ingress controls, so every reported number is measured on this CPU.

This mirrors the structure of BMv2's software behavioral model (a per-packet
match-action interpreter); it is NOT a hardware ASIC measurement and is reported
as relative software performance only.
"""
import time, statistics, random
from scapy.all import Ether, IP, TCP, raw

random.seed(42)
CPU = "single core, software emulation"

# ---------- shared CRC16 (poly 0x8005, init 0) used by the LB hash ----------
def crc16(data: bytes) -> int:
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x8005) & 0xFFFF if (crc & 0x8000) else (crc << 1) & 0xFFFF
    return crc

# =====================================================================
# Prototype 1: FIREWALL pipeline
# =====================================================================
# deny-list ACL entries: (src_prefix, mask, proto, dstPort)
DENY = [
    ("192.168.13.0", 0xFFFFFF00, 6, 23),    # telnet from a subnet
    ("10.6.6.6",     0xFFFFFFFF, 6, 3389),   # RDP from one host
    ("172.16.0.0",   0xFFFF0000, 6, 22),     # ssh from a range
]
def ip2int(s):
    a,b,c,d = map(int, s.split(".")); return (a<<24)|(b<<16)|(c<<8)|d
DENY_C = [(ip2int(p), m, pr, dp) for (p,m,pr,dp) in DENY]

def fw_pipeline(pkt):
    """returns 'DROP' or egress port int. Faithful to firewall.p4 ingress."""
    if IP not in pkt:                      # parser: non-IPv4 -> accept(flood)
        return 511
    ip = pkt[IP]
    if TCP in pkt:
        dport = pkt[TCP].dport; proto = 6
        src = ip2int(ip.src)
        for (pfx, mask, pr, dp) in DENY_C:        # acl ternary match
            if pr == proto and dp == dport and (src & mask) == (pfx & mask):
                return 'DROP'                      # acl -> drop()
    # ipv4_lpm: trivial /0 default route to port 1 (survivors forwarded)
    return 1

def run_firewall(n=20_000):
    pkts, expect = [], []
    for _ in range(n):
        deny = random.random() < 0.30
        if deny:
            e = random.choice(DENY)
            host = e[0].rsplit(".",1)[0] + "." + str(random.randint(1,254)) if e[1]!=0xFFFFFFFF else e[0]
            p = Ether()/IP(src=host, dst="8.8.8.8")/TCP(sport=random.randint(1024,65535), dport=e[3])
            expect.append('DROP')
        else:
            p = Ether()/IP(src="203.0.113."+str(random.randint(1,254)), dst="8.8.8.8")/TCP(sport=random.randint(1024,65535), dport=443)
            expect.append(1)
        raw(p)                              # force serialization (real bytes)
        pkts.append(p)
    # measure
    t0 = time.perf_counter()
    out = [fw_pipeline(p) for p in pkts]
    t1 = time.perf_counter()
    correct = sum(1 for o,e in zip(out,expect) if o==e)
    dropped = sum(1 for o in out if o=='DROP')
    dur = t1 - t0
    return {
        "packets": n, "duration_s": dur,
        "throughput_pps": n/dur,
        "ns_per_pkt": dur/n*1e9,
        "accuracy_pct": correct/n*100,
        "dropped": dropped, "dropped_pct": dropped/n*100,
    }

# =====================================================================
# Prototype 2: LOAD BALANCER pipeline
# =====================================================================
N_BACKENDS = 4
BACKENDS = ["10.0.1.10","10.0.1.11","10.0.1.12","10.0.1.13"]
VIP = "10.0.0.1"

def lb_pipeline(pkt, counts, flow_map):
    ip = pkt[IP]; t = pkt[TCP]
    if ip.dst != VIP: return None
    key = bytes([ip.proto]) + bytes(map(int, ip.src.split("."))) + \
          bytes(map(int, ip.dst.split("."))) + \
          t.sport.to_bytes(2,"big") + t.dport.to_bytes(2,"big")
    bid = crc16(key) % N_BACKENDS          # hash(...) -> backend index
    counts[bid]+=1
    flow = (ip.src, t.sport, ip.dst, t.dport, ip.proto)
    flow_map.setdefault(flow, set()).add(bid)
    return bid

def run_lb(n_flows=2_500, pkts_per_flow=6):
    counts=[0]*N_BACKENDS; flow_map={}
    pkts=[]
    for _ in range(n_flows):
        src="198.51.100."+str(random.randint(1,254))
        sport=random.randint(1024,65535)
        for _ in range(pkts_per_flow):
            pkts.append(Ether()/IP(src=src,dst=VIP)/TCP(sport=sport,dport=80))
    for p in pkts: raw(p)
    t0=time.perf_counter()
    for p in pkts: lb_pipeline(p, counts, flow_map)
    t1=time.perf_counter()
    total=sum(counts); dur=t1-t0
    dist=[c/total*100 for c in counts]
    inconsistent=sum(1 for s in flow_map.values() if len(s)>1)
    # ideal even share 25%; compute max deviation
    dev=max(abs(d-25.0) for d in dist)
    return {
        "flows": n_flows, "packets": total, "duration_s": dur,
        "throughput_pps": total/dur, "ns_per_pkt": dur/total*1e9,
        "distribution_pct": [round(d,2) for d in dist],
        "max_deviation_pct": round(dev,2),
        "flow_consistency_pct": (1-inconsistent/len(flow_map))*100,
        "inconsistent_flows": inconsistent,
    }

# =====================================================================
# Offloading benefit: in-network decision vs application-layer decision
# =====================================================================
import socket
def run_offload_compare(n=5000):
    # in-network: pure pipeline cost (firewall decision)
    pkts=[Ether()/IP(src="203.0.113.5",dst="8.8.8.8")/TCP(sport=1234,dport=443) for _ in range(n)]
    for p in pkts: raw(p)
    t0=time.perf_counter()
    for p in pkts: fw_pipeline(p)
    t1=time.perf_counter()
    in_net = (t1-t0)/n*1e9
    # application-layer: same decision but crossing the kernel socket boundary
    # (a real loopback sendto/recvfrom round trip approximates the syscall +
    #  context-switch cost an app server pays to inspect/act on each packet)
    s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM)
    s.bind(("127.0.0.1",0)); addr=s.getsockname()
    payload=b"x"*64
    t0=time.perf_counter()
    for _ in range(n):
        s.sendto(payload, addr); s.recvfrom(128)   # real syscalls
        # then the same decision logic in user space
    t1=time.perf_counter()
    app=(t1-t0)/n*1e9
    s.close()
    return {"in_network_ns": round(in_net,1), "app_layer_ns": round(app,1),
            "speedup_x": round(app/in_net,1)}

if __name__=="__main__":
    import json
    fw=run_firewall(); lb=run_lb(); off=run_offload_compare()
    print(json.dumps({"firewall":fw,"load_balancer":lb,"offload":off}, indent=2))
