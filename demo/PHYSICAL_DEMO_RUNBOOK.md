# Physical Live P4 Demo — Real Laptops + a "P4 Box"
**What it shows:** two real laptops talk through a switch you built from a regular
computer running P4. You toggle a firewall rule live and the connection dies/recovers.

> Read Section 0 first — it explains, honestly, what is and isn't possible, so your
> demo (and your answers to questions) are bulletproof.

---

## 0. The honest framing (memorize this)

P4 does **not** reprogram your old switch. A fixed-function switch's logic is etched in
silicon and can never be changed by software. P4 needs hardware *designed* to be
programmable (Tofino, FPGA, SmartNIC) **or** the BMv2 software switch running on a PC.

So in this demo, **the programmable switch is a regular computer running BMv2.** You are
literally building a programmable switch out of a PC. Say exactly that on stage — it's
true and it's impressive. Your old switch, if you use it, is a plain connector, not the
P4 element.

If anyone asks "why not the real switch?": *"Because its chip is fixed-function — that's
the entire problem P4 solves by moving to programmable targets. This PC is one of those
targets."*

---

## 1. The topology

Basic (two laptops):
```
  Laptop A  ──cable──►  NIC1            NIC2  ◄──cable──  Laptop B
 10.0.0.1/24            └──  P4 BOX (Ubuntu + BMv2)  ──┘   10.0.0.2/24
                              running bridge_firewall.p4
```
- **P4 BOX** = a laptop running Ubuntu Linux with TWO wired NICs (built-in Ethernet +
  one USB-Ethernet adapter, or two USB adapters).
- **Laptop A / Laptop B** = any OS. Each needs an Ethernet port (or its own USB adapter).
- All three are in the same subnet `10.0.0.0/24`. The P4 box itself has **no IP** on the
  two bridge NICs — it's a transparent switch, not a host.

Optional (use your old switch as a fan-out for several clients):
```
  Laptop A ─► NIC1  P4 BOX  NIC2 ─► [ OLD SWITCH ] ─► Laptop B, Laptop C, ...
```
The old switch just spreads NIC2 to several client laptops. Firewall still runs on the
P4 box.

---

## 2. Hardware checklist

- [ ] 1 laptop that can run Ubuntu (installed, or a Live USB — see Section 3).
- [ ] 2 wired Ethernet ports on the P4 box → buy USB-Ethernet adapters as needed.
- [ ] 2 client laptops, each with an Ethernet port or USB adapter.
- [ ] 2 Ethernet cables (more if using the old switch).
- [ ] (optional) your old switch + extra cables for the multi-client version.

---

## 3. Prepare the P4 box (Ubuntu)

You need Ubuntu on the P4 box. Two ways:
- **Installed Ubuntu 22.04** (best, most stable), OR
- **Ubuntu Live USB**: flash Ubuntu to a USB stick with Rufus/balenaEtcher, boot the
  laptop from it, choose "Try Ubuntu". Tools installed in a live session vanish on
  reboot — fine for a demo, but reinstall each boot, so rehearse the install steps.

Install the P4 tools on the P4 box:
```bash
sudo apt-get update
# Add the official p4lang package repository (Ubuntu 22.04 shown):
. /etc/os-release
echo "deb http://download.opensuse.org/repositories/home:/p4lang/xUbuntu_${VERSION_ID}/ /" \
  | sudo tee /etc/apt/sources.list.d/home:p4lang.list
curl -fsSL "https://download.opensuse.org/repositories/home:p4lang/xUbuntu_${VERSION_ID}/Release.key" \
  | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/home_p4lang.gpg > /dev/null
sudo apt-get update
sudo apt-get install -y p4lang-p4c p4lang-bmv2 ethtool
```
Verify:
```bash
p4c --version
simple_switch --version
```
Both printing a version = good. (If the apt repo gives trouble on the day, the fallback
is the p4lang **tutorials VM** from the other runbook — but for *physical* NICs you want
BMv2 installed on real Ubuntu as above, not inside a nested VM.)

Copy `bridge_firewall.p4` onto the P4 box (USB stick or `git clone` your repo).

---

## 4. Identify and prepare the two NICs

Plug in both USB-Ethernet adapters (and cables to the laptops) FIRST, then:
```bash
ip link            # list interfaces; find your two wired NICs
```
Wired NICs are named like `enp0s25`, `eth0`, or `enx00e04c680001` (USB ones are usually
the long `enx...` names). Pick the two you'll use and note them. In commands below they
are **IF1** and **IF2** — replace with your real names.

Stop the OS from using them and bring them up in promiscuous mode (no IP — the bridge is
transparent):
```bash
sudo ip addr flush dev IF1
sudo ip addr flush dev IF2
sudo ip link set IF1 up promisc on
sudo ip link set IF2 up promisc on
```
(If NetworkManager keeps re-adding addresses, run: `nmcli dev set IF1 managed no` and the
same for IF2.)

---

## 5. Compile and run your P4 switch on the real NICs

```bash
# compile your program to BMv2 JSON
p4c --target bmv2 --arch v1model bridge_firewall.p4
#   -> produces bridge_firewall.json

# run the software switch, binding the two real NICs as port 0 and port 1
sudo simple_switch -i 0@IF1 -i 1@IF2 bridge_firewall.json
```
Leave this terminal running — this **is** your switch. It also opens a control port
(Thrift, default 9090) that you'll use to add firewall rules.

---

## 6. Configure the two client laptops (static IPs)

Give each client a static IP in `10.0.0.0/24`, no gateway, and turn **Wi-Fi off** so
traffic can only go over the cable.

**Windows:** Settings → Network & Internet → Ethernet → Edit IP assignment → Manual →
IPv4 on. Laptop A: IP `10.0.0.1`, mask `255.255.255.0`, gateway blank. Laptop B:
`10.0.0.2`, same mask.

**macOS:** System Settings → Network → the Ethernet/USB-LAN device → Details → TCP/IP →
Configure IPv4: Manually → addresses as above.

**Linux client:** `sudo ip addr add 10.0.0.1/24 dev <eth>; sudo ip link set <eth> up`.

Verify cabling/links: on the P4 box, `ip -br link` should show both NICs `UP`.

---

## 7. The live demo — commands + narration

You need TWO terminals on the P4 box:
- **Terminal A** = the running `simple_switch` (Section 5). Leave it.
- **Terminal B** = control plane.

### Beat 1 — "Two real laptops, talking through my P4 switch"
On **Laptop A**, open a terminal/command prompt and run a continuous ping:
- Windows: `ping -t 10.0.0.2`
- Mac/Linux: `ping 10.0.0.2`

Replies appear. Say: *"Two laptops, a switch I built from a PC running my P4 program.
The packets flow through it."* Leave the ping running on the projector.

### Beat 2 — "I add a firewall rule, live"
In **Terminal B** on the P4 box:
```bash
simple_switch_CLI            # connects to the running switch on port 9090
```
At the `RuntimeCmd:` prompt:
```bash
table_add MyIngress.acl MyIngress.drop 10.0.0.2&&&0xffffffff => 1
```
Say it in plain words: *"Match any packet whose destination is Laptop B, and drop it."*
`&&&0xffffffff` = match the address exactly; `=>` separates match from action; `1` is
priority.

Look at **Laptop A**: replies have **stopped** ("Request timed out" / 100% loss). Say:
*"My switch is now dropping those packets itself — because of the rule I just wrote into
its data plane. No reboot, no new hardware."*

### Beat 3 — "I remove it, the link returns"
In **Terminal B**:
```bash
table_dump MyIngress.acl       # shows the entry and its handle (0)
table_delete MyIngress.acl 0   # delete handle 0
```
**Laptop A**'s ping resumes. Say: *"Rule gone — traffic flows again. That is a
programmable data plane: I changed how the network treats packets, in real time, with
code."*

### Closing
*"The old switch can't do this — its logic is frozen in silicon. P4 let me turn an
ordinary computer into a switch I program like the rest of my stack."*

---

## 8. Reset between rehearsals

- Firewall rule lingering? In `simple_switch_CLI`: `table_clear MyIngress.acl`.
- Restart the switch: Ctrl-C in Terminal A, then re-run the `simple_switch -i ...` line.
- NICs acting up: re-run the four `ip` commands in Section 4.

---

## 9. Troubleshooting

- **No ping even before any rule:** (a) wrong NIC bound — recheck `ip link` names; (b) a
  client still on Wi-Fi or wrong subnet — confirm `10.0.0.x/24`, Wi-Fi off; (c) NIC not
  in promisc/up — re-run Section 4; (d) cable in the wrong port. Test each cable/link
  with the switch stopped first: `ping` won't cross until BMv2 is running, but link
  lights should be on.
- **`simple_switch_CLI` connection refused:** the switch isn't running, or it's on a
  different thrift port. Check Terminal A is alive; default port is 9090.
- **`table_add` unknown table/action:** names are exact and case-sensitive —
  `MyIngress.acl`, action `MyIngress.drop`.
- **Ping doesn't recover after delete:** you removed the wrong handle. Use
  `table_dump MyIngress.acl` to see handles, or `table_clear MyIngress.acl`.
- **Works one direction only:** expected — you only blocked traffic *to* 10.0.0.2.
  Pinging from B to A still works; that's fine for the story (block one direction).
- **Intermittent drops / weird checksums:** on the P4 box try disabling NIC offloads:
  `sudo ethtool -K IF1 rx off tx off gro off; ` (and IF2). The program doesn't modify
  packets, so this is rarely needed, but it removes a class of NIC quirks.

---

## 10. Rehearsal + backup (do not skip)

- [ ] Full dry run end-to-end at least **3 times**, including cabling from scratch.
- [ ] Time it: aim for under 4 minutes.
- [ ] **Record a clean run** (OBS Studio / phone on a tripod showing both screens). If
      the live setup fails on stage, play the video and narrate. Your slide deck's result
      charts are a third fallback.
- [ ] Label your cables/adapters (NIC1, NIC2) so you wire it right under pressure.
- [ ] Bring spare cables and a spare USB-Ethernet adapter.

---

## 11. If you'd rather not carry hardware

Everything above also works **entirely inside one laptop** using Mininet (virtual hosts
+ virtual switch) — see `DEMO_RUNBOOK.md`. Same firewall, same story, zero cables. Many
people present that and keep the physical version as the ambitious option. Do the
physical one only if you can rehearse it fully beforehand.
