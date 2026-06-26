# Advanced Demo — A Switch That REMEMBERS and MEASURES
**Why this is better than the IP-block demo:** blocking an IP is something even a normal
managed switch can roughly do. What a fixed-function switch can NEVER do is keep *state*
across packets, make its own decisions from that state at line rate, and stream live
measurements to software. This demo shows exactly those P4-unique powers, on your same
rig. Program: `stateful_firewall.p4`.

It does three things:
  1. STATE / auto-block: counts packets going to Laptop B; after THRESHOLD (=20) it
     blocks further ones BY ITSELF — no controller command. Rate-limiting / DoS defence
     in miniature.
  2. LIVE TELEMETRY: per-port packet counters you read from the control plane while
     traffic flows — the "in-band telemetry, zero overhead" idea from your paper.
  3. PROGRAMMABLE RESET: you wipe its memory from the controller and traffic resumes.

Prerequisite: you've done the basic demo once, so the cabling, NIC prep (Phase 5) and
static IPs (10.0.0.1 / 10.0.0.2) are already known-good.

================================================================
STEP 1 — Get the program on the server and compile it
================================================================
    cp /media/files/p4/stateful_firewall.p4 ~          # or however you copy files
    cd ~
    sudo docker run --rm -v "$PWD":/work -w /work p4lang/p4c \
      p4c --target bmv2 --arch v1model stateful_firewall.p4
    ls -l stateful_firewall.json        # success = file exists

================================================================
STEP 2 — Make sure the NICs are prepped (same as before)
================================================================
    sudo ip addr flush dev enp3s0
    sudo ip addr flush dev enx9c69d33a9f57
    sudo ip link set enp3s0 up promisc on
    sudo ip link set enx9c69d33a9f57 up promisc on

================================================================
STEP 3 — Run the stateful switch (tmux)
================================================================
    tmux new -s p4     # (or reuse your session; stop any old simple_switch first)
    cd ~
    sudo docker run --rm -it --privileged --network host -v "$PWD":/work -w /work \
      p4lang/behavioral-model \
      simple_switch -i 0@enp3s0 -i 1@enx9c69d33a9f57 stateful_firewall.json --thrift-port 9090

================================================================
STEP 4 — Open the control plane (second terminal)
================================================================
    sudo docker run --rm -it --network host p4lang/behavioral-model \
      simple_switch_CLI --thrift-port 9090

================================================================
STEP 5 — Run the demo
================================================================
PART A — Live telemetry (do this first, it's calm and visual)
  On Laptop A:  ping -t 10.0.0.2
  In the CLI, read the per-port counters a few times while it pings:
      counter_read MyIngress.port_pkts 0      # packets in from Laptop A (port 0)
      counter_read MyIngress.port_pkts 1      # packets in from Laptop B (port 1)
  The numbers climb each time you read. Say: "The switch is measuring traffic itself,
  in real time, with no extra probe packets — that's in-band telemetry."

PART B — The switch blocks itself (the wow moment)
  Keep the ping running. After about 20 echo requests (~20 seconds), Laptop A's ping
  starts TIMING OUT on its own — you typed no block command. Say: "I never told it to
  block. It counted the packets, hit its threshold, and decided — stateful logic at line
  rate. A traditional switch has no memory between packets; it literally cannot do this."
  Confirm the memory from the controller:
      register_read MyIngress.fw_count 0      # shows the count, now > 20

PART C — Forgive (programmable reset)
  Wipe the switch's memory:
      register_write MyIngress.fw_count 0 0
  Laptop A's ping immediately recovers. Say: "I reset its state and it forgives — the
  data plane's behaviour is mine to program, live."

================================================================
STEP 6 — Tuning & reset
================================================================
- Change how fast it auto-blocks: edit THRESHOLD in stateful_firewall.p4 (e.g. 50 for a
  longer runway on stage), recompile (Step 1), restart the switch (Step 3).
- Reset memory anytime:           register_write MyIngress.fw_count 0 0
- Faster ping to hit threshold sooner (Windows):  ping -t -w 200 10.0.0.2

================================================================
STEP 7 — Troubleshooting
================================================================
- Ping never auto-blocks: you may be reading/sending too slowly, or THRESHOLD is high.
  Lower THRESHOLD and recompile, or send a flood briefly: on Laptop A (admin cmd)
      ping -t -l 1000 10.0.0.2
- counter_read / register_read "no such object": names are exact —
  MyIngress.port_pkts and MyIngress.fw_count.
- After it auto-blocks, reverse pings (B -> A) still work; that's expected (only A->B is
  metered). The visible ping should be the one on Laptop A toward 10.0.0.2.

================================================================
IDEA 2 (even more advanced, ask me to write it later) — CUSTOM PROTOCOL
================================================================
The single most P4-defining trick: invent a brand-new packet header that no standard
defines, and make the switch forward based on IT instead of the IP. e.g. a 2-byte
"myTunnel" header carrying a destination ID; the switch reads the ID and routes the
packet — source routing the hardware never knew about. It needs a small Python+scapy
sender on one laptop (to craft the custom packets), so it's a bit more setup. If you
want it, say the word and I'll write CUSTOM_HEADER_DEMO.md with full steps.
