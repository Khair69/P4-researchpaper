# Headless Ubuntu-Server P4 Demo — TESTED Setup (your exact rig)
This is the path that actually worked, with your real interface names and every
gotcha you hit along the way. Ubuntu 24.04 (noble) server, managed over Wi-Fi/SSH.

YOUR INTERFACES:
  enp3s0           = built-in Ethernet  -> Laptop A (projector)  -> IP 10.0.0.1
  enx9c69d33a9f57  = USB-Ethernet adapter -> Laptop B            -> IP 10.0.0.2
  wlp2s0           = Wi-Fi = your SSH lifeline. NEVER flush/reconfigure this one.

The switch logic = bridge_firewall.p4 (and stateful_firewall.p4 for the advanced demo).

================================================================
PHASE 1 — Install the P4 tools (Ubuntu 24.04 = use Docker)
================================================================
NOTE: the p4lang apt repo does NOT publish for Ubuntu 24.04 — `apt-get update` returns
a 404 and the packages can't be found. That's expected. We use the official Docker
images instead.

If you tried the apt repo, remove it first so apt stops erroring:
    sudo rm -f /etc/apt/sources.list.d/home:p4lang.list
    sudo rm -f /etc/apt/trusted.gpg.d/home_p4lang.gpg
    sudo apt-get update

Make sure Docker is present, then pull the images and helper tools:
    docker --version || sudo apt-get install -y docker.io
    sudo systemctl enable --now docker
    sudo apt-get install -y tmux ethtool
    sudo docker pull p4lang/p4c
    sudo docker pull p4lang/behavioral-model

================================================================
PHASE 2 — Put the P4 program on the server
================================================================
Copy bridge_firewall.p4 into your home folder (any way you like), e.g.:
    cp /media/files/p4/bridge_firewall.p4 ~
    ls ~/bridge_firewall.p4

================================================================
PHASE 3 — Compile it (with the p4c Docker image)
================================================================
    cd ~
    sudo docker run --rm -v "$PWD":/work -w /work p4lang/p4c \
      p4c --target bmv2 --arch v1model bridge_firewall.p4
    ls -l bridge_firewall.json        # success = this file exists (~12 KB)

================================================================
PHASE 4 — Plug in cables, identify the two wired NICs
================================================================
Plug: server built-in port -> Laptop A;  USB adapter -> Laptop B. Power both laptops on.
    ip -br link
    for i in $(ls /sys/class/net | grep -Ev 'lo|docker|veth|br-'); do
      echo "== $i =="; sudo ethtool "$i" 2>/dev/null | grep -E "Link detected|Speed"; done

>> GOTCHA (you hit this): a USB-Ethernet adapter often reports "Link detected: no" and
   "Speed: Unknown!" while the interface is DOWN, EVEN with its light on. Its PHY only
   powers up once you bring the interface UP (Phase 5). So don't panic if it shows "no"
   here — bring it up, then re-check.

================================================================
PHASE 5 — Prepare the two NICs (no IP, promiscuous, UP)
================================================================
    sudo ip addr flush dev enp3s0
    sudo ip addr flush dev enx9c69d33a9f57
    sudo ip link set enp3s0 up promisc on
    sudo ip link set enx9c69d33a9f57 up promisc on
    sleep 3
    sudo ethtool enx9c69d33a9f57 | grep -E "Link detected|Speed"   # now: Link detected: yes
    ip -br link show enp3s0; ip -br link show enx9c69d33a9f57       # both: ... PROMISC,UP,LOWER_UP

================================================================
PHASE 6 — Start the P4 switch (in tmux, via Docker, host networking)
================================================================
    tmux new -s p4
    cd ~
    sudo docker run --rm -it --privileged --network host -v "$PWD":/work -w /work \
      p4lang/behavioral-model \
      simple_switch -i 0@enp3s0 -i 1@enx9c69d33a9f57 bridge_firewall.json --thrift-port 9090
    # it prints logs then SITS RUNNING = your switch. Detach without stopping: Ctrl-b then d
    # reattach later: tmux attach -t p4

================================================================
PHASE 7 — Static IPs on the two client laptops
================================================================
Laptop A (enp3s0):  10.0.0.1 / 255.255.255.0 / gateway BLANK
Laptop B (enx...):  10.0.0.2 / 255.255.255.0 / gateway BLANK

>> GOTCHA (Windows 10): the modern Settings > "Edit IP" dialog often fails with
   "Can't save IP settings. Check one or more settings and try again." Use the CLASSIC
   dialog instead — it just works:
     1. Win+R -> ncpa.cpl -> Enter
     2. Right-click the ETHERNET adapter (not Wi-Fi) -> Properties
     3. Internet Protocol Version 4 (TCP/IPv4) -> Properties
     4. "Use the following IP address": IP 10.0.0.1, mask 255.255.255.0, gateway EMPTY
     5. OK -> Close
   (Fast alternative, elevated cmd:
     netsh interface ip set address name="Ethernet" static 10.0.0.1 255.255.255.0 )
   The projector laptop may keep Wi-Fi ON for SSH — 10.0.0.x lives only on its Ethernet,
   so there is no conflict.

================================================================
PHASE 8 — Test forwarding
================================================================
On Laptop A:  ping -t 10.0.0.2     (Windows)   /   ping 10.0.0.2  (Mac/Linux)
Replies = two real laptops talking through your P4 switch.

>> GOTCHA: if you see "Reply from <some other IP>: Destination host unreachable", the
   static IP did NOT get set on the Ethernet adapter (the laptop fell back to Wi-Fi).
   Re-do Phase 7 via ncpa.cpl and confirm with `ipconfig` that the Ethernet adapter
   shows 10.0.0.1 / 255.255.255.0.
>> GOTCHA: if you get "Request timed out" (not "unreachable"), packets ARE crossing but
   Laptop B isn't replying — that's Windows Firewall on B blocking ping. Set B's Ethernet
   network profile to PRIVATE, or temporarily disable Defender Firewall on that adapter.

================================================================
PHASE 9 — The live firewall
================================================================
Second terminal to the server (new SSH session, or tmux split: Ctrl-b then " ):
    sudo docker run --rm -it --network host p4lang/behavioral-model \
      simple_switch_CLI --thrift-port 9090

Block Laptop B (Laptop A's ping stops within ~2s):
    table_add MyIngress.acl MyIngress.drop 10.0.0.2&&&0xffffffff => 1
Un-block it (ping recovers):
    table_dump MyIngress.acl          # shows handle 0
    table_delete MyIngress.acl 0      # or: table_clear MyIngress.acl

================================================================
PHASE 10 — Reset / restart
================================================================
- clear all firewall rules:        table_clear MyIngress.acl   (in the CLI)
- restart the switch:               Ctrl-C in the tmux pane, then re-run the Phase 6 cmd
- NICs lost their state after reboot: re-run Phase 5 (flush/up/promisc)
- stuck simple_switch process:      sudo pkill -f simple_switch   (then re-run Phase 6)

================================================================
PHASE 11 — Quick reference (your exact commands)
================================================================
PREP:    sudo ip addr flush dev enp3s0; sudo ip addr flush dev enx9c69d33a9f57
         sudo ip link set enp3s0 up promisc on; sudo ip link set enx9c69d33a9f57 up promisc on
SWITCH:  sudo docker run --rm -it --privileged --network host -v "$PWD":/work -w /work \
           p4lang/behavioral-model simple_switch -i 0@enp3s0 -i 1@enx9c69d33a9f57 \
           bridge_firewall.json --thrift-port 9090
CLI:     sudo docker run --rm -it --network host p4lang/behavioral-model \
           simple_switch_CLI --thrift-port 9090
BLOCK:   table_add MyIngress.acl MyIngress.drop 10.0.0.2&&&0xffffffff => 1
UNBLOCK: table_clear MyIngress.acl
