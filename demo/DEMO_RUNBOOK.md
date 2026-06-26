# Live P4 Demo — Step‑by‑Step Runbook
**Demo:** a programmable firewall on a BMv2 software switch. You make `h1 ping h2`
work, then break it with one firewall rule, then fix it — all live.

Everything below is meant to be read top‑to‑bottom the first time, then used as a
checklist on demo day. Don't skip Section 7 (rehearsal) or Section 8 (backup video).

---

## 0. What you need

- A laptop. Your old physical switch is **only a prop** (see Section 1).
- **Linux** to run the demo. Mininet needs real Linux networking, so the reliable
  options are, best first:
  1. **The official P4 tutorials VM** (everything preinstalled) — recommended.
  2. A fresh **Ubuntu 22.04 VM** in VirtualBox where you install the tools.
  3. WSL2 on Windows — works for many people but is the most likely to misbehave
     during a live demo. Avoid for the real thing.
- ~10 GB free disk, 4 GB RAM for the VM, and **VirtualBox** installed on Windows.

---

## 1. Why your old switch can't run P4 (use it as a prop)

A normal switch processes packets with a **fixed‑function ASIC** — logic frozen at
manufacture. You cannot load a P4 program onto it. P4 runs only on programmable
targets: Intel Tofino ASICs, SmartNICs/FPGAs, or the **BMv2 software switch** we use
here. So on stage:

> Hold up the old switch: "This is a traditional switch — its behaviour is frozen in
> silicon, I can't change how it treats a packet. Now watch a switch that's software."

That contrast is the heart of your paper. The old box earns its place as a prop.

---

## 2. Install the environment (recommended: P4 tutorials VM)

The maintained, known‑good environment is the **p4lang/tutorials** VM. It already has
`p4c` (compiler), `bmv2` (`simple_switch` / `simple_switch_grpc`), Mininet, and the
P4Runtime helpers wired together.

1. Install **VirtualBox** (Windows) and **Vagrant**.
2. Get the tutorials and build the VM:
   ```bash
   git clone https://github.com/p4lang/tutorials
   cd tutorials/vm-ubuntu-20.04
   vagrant up         # downloads + builds everything; takes a while the first time
   ```
   When it finishes, a Linux desktop VM opens. Log in (user `p4`, password `p4`).

   *Alternative (no Vagrant):* install on a plain Ubuntu 22.04 VM with the official
   p4lang apt packages, then `git clone https://github.com/p4lang/tutorials`. The VM
   route above is safer for a beginner — fewer ways for it to break on stage.

3. Open a terminal **inside the VM** and confirm the tools exist:
   ```bash
   p4c --version
   simple_switch --version
   mn --version
   ```
   If all three print a version, you're ready.

---

## 3. Prove the baseline works (do this once, before touching anything)

```bash
cd ~/tutorials/exercises/basic
make run
```
What this does: compiles the example P4 program, builds a small virtual network
(several switches + hosts) in Mininet, loads the forwarding rules, and drops you at a
`mininet>` prompt.

At the `mininet>` prompt:
```bash
h1 ping h2
```
You should see replies. Press **Ctrl‑C** to stop the ping. Then:
```bash
exit
```
and back in the shell:
```bash
make stop
make clean
```
If the baseline ping worked, your environment is healthy. **This is the single most
important check** — if this works, the demo will work.

---

## 4. Load the firewall demo program

You'll reuse the `basic` exercise's network, but swap in **firewall_demo.p4** (the file
I gave you — it's the basic forwarding program PLUS an `acl` firewall table).

```bash
cd ~/tutorials/exercises/basic
cp basic.p4 basic.p4.backup            # keep the original safe
cp /path/to/firewall_demo.p4 basic.p4  # overwrite with the demo program
make run                               # recompiles and relaunches Mininet
```
> Copy `firewall_demo.p4` into the VM first (shared folder, or `git clone` your repo
> inside the VM). The `/path/to/` is wherever you put it.

At the `mininet>` prompt, confirm forwarding still works (the firewall starts empty, so
nothing is blocked yet):
```bash
h1 ping h2     # should reply. Ctrl-C to stop.
```
Find and note **h2's IP address** — you'll block it in the demo:
```bash
h2 ifconfig    # look for the inet address, e.g. 10.0.2.2
```
Write that IP down. Leave Mininet running.

---

## 5. The live demo — exact commands + what to say

Keep **two terminals** open side by side:
- **Terminal A** = the `mininet>` prompt (from `make run`).
- **Terminal B** = a second VM terminal for the control plane.

### Beat 1 — "The switch forwards normally"
In **Terminal A**:
```bash
h1 ping h2
```
Replies scroll. Say: *"Two hosts, one switch running my P4 program. It forwards."*
Leave the ping **running**.

### Beat 2 — "I install a firewall rule, live"
In **Terminal B**, open the switch control plane:
```bash
simple_switch_CLI --thrift-port 9090
```
(9090 is the first switch, s1. If it refuses, see Troubleshooting for the right port.)
At the `RuntimeCmd:` prompt, add the drop rule (use h2's IP from Section 4):
```bash
table_add MyIngress.acl MyIngress.drop 10.0.2.2&&&0xffffffff => 1
```
Read this out loud as: *"Match any packet whose destination is 10.0.2.2, and drop it.
Priority 1."* The `&&&0xffffffff` means "match the address exactly"; `=>` separates the
match from the action; `1` is the rule priority.

**Switch to Terminal A**: the ping has **stopped getting replies** — the counter shows
100% loss. Say: *"The switch is now dropping those packets itself, because of the rule I
just wrote. No reboot, no new hardware."*

### Beat 3 — "I remove it, traffic returns"
Back in **Terminal B**, list the rule to get its handle, then delete it:
```bash
table_dump MyIngress.acl        # shows entry 0 (the handle number)
table_delete MyIngress.acl 0    # 0 = the handle from the dump
```
**Terminal A**: replies resume. Say: *"Rule gone, traffic flows again. That's the
programmable data plane — behaviour controlled by software, in real time."*

### Closing line
*"This switch is software. The old box in my hand is silicon. P4 is what turns the
network from frozen hardware into something I program like the rest of my stack."*

### Reset between rehearsals
```bash
# in Terminal A:
exit
# in the shell:
make stop && make clean
```

---

## 6. One‑page cheat sheet (print this)

```
SETUP (before audience):
  cd ~/tutorials/exercises/basic
  cp basic.p4 basic.p4.backup
  cp firewall_demo.p4 basic.p4
  make run
  mininet> h2 ifconfig         # note h2 IP (e.g. 10.0.2.2)

LIVE:
  A> h1 ping h2                 # works
  B> simple_switch_CLI --thrift-port 9090
     table_add MyIngress.acl MyIngress.drop 10.0.2.2&&&0xffffffff => 1
  A> (ping now 100% loss)
  B> table_dump MyIngress.acl
     table_delete MyIngress.acl 0
  A> (ping recovers)

RESET:
  A> exit
  shell> make stop && make clean
```

---

## 7. Rehearsal checklist (do the FULL run at least 3 times)

- [ ] Baseline `exercises/basic` ping works (Section 3).
- [ ] firewall_demo.p4 copied in, `make run` compiles with no errors.
- [ ] You know h2's exact IP and typed the `table_add` correctly once from memory.
- [ ] Ping visibly dies within ~2 seconds of the rule, recovers after delete.
- [ ] You can do the whole thing in under 3 minutes without notes.
- [ ] Laptop won't sleep mid‑demo (disable screen timeout / power saving).
- [ ] Font size in the terminal is BIG enough to read from the back row.

---

## 8. Backup plan — RECORD A VIDEO (do not skip)

Live demos fail at the worst moment. The night before, do one clean run and **screen‑
record it** (OBS Studio, or the VM's recorder). If anything misbehaves on stage, play
the 2‑minute video and narrate over it — the audience still sees it work. You already
have the static result charts in the slide deck as a third fallback.

---

## 9. Troubleshooting

- **`make run` errors about a port in use / leftover state:** run `make stop && make
  clean`, then `make run` again. If a `simple_switch` is stuck: `sudo pkill -f
  simple_switch`.
- **`simple_switch_CLI` says "connection refused":** you used the wrong thrift port.
  Each switch gets its own. Find it:
  ```bash
  ps aux | grep simple_switch     # look for --thrift-port NNNN on switch s1
  ```
  Use that number after `--thrift-port`. The first switch is usually 9090.
- **Ping never works even at baseline:** your environment is the problem, not the demo.
  Re‑do Section 3 in the official VM; don't debug a custom install live.
- **`table_add` says unknown table/action:** names are case‑sensitive and fully
  qualified — it's `MyIngress.acl` and `MyIngress.drop`, exactly.
- **Ping doesn't recover after delete:** you deleted the wrong handle. Run
  `table_dump MyIngress.acl` to see remaining entries, or `table_clear MyIngress.acl`
  to wipe the firewall table entirely.

---

## 10. Optional upgrade — the load balancer

Once the firewall demo is solid, your second prototype (`load_balancer.p4`) can be
shown the same way: start several backend "servers" in Mininet, send connections to the
virtual IP, and show traffic spreading evenly while each connection sticks to one
backend. It's a stronger story but more moving parts — only attempt it if you've
mastered the firewall demo first and have time. Ask me and I'll write that runbook too.
