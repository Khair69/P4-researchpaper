#!/usr/bin/env python3
"""Clean isolation of the match-action logic cost: packets are pre-parsed into
field tuples ONCE (parser stage), then only the ingress match-action logic is
timed. This reports decisions/second for the data-plane logic on a single core,
free of scapy/serialization overhead."""
import time, random
random.seed(7)

def ip2int(s):
    a,b,c,d=map(int,s.split(".")); return (a<<24)|(b<<16)|(c<<8)|d

DENY=[(ip2int("192.168.13.0"),0xFFFFFF00,6,23),
      (ip2int("10.6.6.6"),0xFFFFFFFF,6,3389),
      (ip2int("172.16.0.0"),0xFFFF0000,6,22)]

def crc16(data):
    crc=0
    for b in data:
        crc^=b<<8
        for _ in range(8):
            crc=((crc<<1)^0x8005)&0xFFFF if crc&0x8000 else (crc<<1)&0xFFFF
    return crc

# ---- pre-parsed field tuples (parser already done) ----
N=300_000
fw=[]
for _ in range(N):
    if random.random()<0.3:
        e=random.choice(DENY); src=(e[0]&e[1])|random.randint(1,254); fw.append((src,6,e[3]))
    else:
        fw.append((ip2int("203.0.113."+str(random.randint(1,254))),6,443))

def fw_logic(src,proto,dport):
    for pfx,mask,pr,dp in DENY:
        if pr==proto and dp==dport and (src&mask)==(pfx&mask): return 0  # drop
    return 1  # forward

t0=time.perf_counter()
drop=0
for src,proto,dport in fw: 
    if fw_logic(src,proto,dport)==0: drop+=1
t1=time.perf_counter()
fw_dur=t1-t0
print(f"FIREWALL match-action: {N} decisions in {fw_dur*1000:.1f} ms -> "
      f"{N/fw_dur/1e6:.2f} M decisions/s/core ({fw_dur/N*1e9:.0f} ns/decision), dropped={drop}")

# load balancer logic
lbkeys=[bytes([6])+random.randbytes(4)+bytes([10,0,0,1])+random.randbytes(4) for _ in range(N)]
counts=[0]*4
t0=time.perf_counter()
for k in lbkeys: counts[crc16(k)%4]+=1
t1=time.perf_counter()
lb_dur=t1-t0
print(f"LOADBAL  match-action: {N} decisions in {lb_dur*1000:.1f} ms -> "
      f"{N/lb_dur/1e6:.2f} M decisions/s/core ({lb_dur/N*1e9:.0f} ns/decision)")
print(f"LB distribution over {N}: {[round(c/N*100,2) for c in counts]} %")
