# DEMO DAY — One Command to Start, Two to Remember
No Wi-Fi, no SSH needed. You type everything on the SERVER LAPTOP's own keyboard/screen
(log in locally). The judges watch Laptop A on the projector — they don't see the server.

================================================================
ONE-TIME SETUP (do this once at home, with internet)
================================================================
Copy the whole demo folder onto the server (e.g. to /home/mkh/p4demo) so these are
together:  bridge_firewall.p4  stateful_firewall.p4  *.sh

Then, on the server, prepare the scripts ONCE:
    cd ~/p4demo                      # wherever you put them
    sed -i 's/\r$//' *.sh            # fix Windows line endings (IMPORTANT or scripts fail)
    chmod +x *.sh                    # make them runnable
    sudo ./start_demo.sh             # test run; it compiles + starts the switch

If that prints "P4 switch is UP", you're golden. (Internet is only needed the first time,
to pull Docker images / compile. After that it works offline.)

================================================================
ON THE DAY — BASIC FIREWALL DEMO
================================================================
On the SERVER (one command):
    sudo ./start_demo.sh

On LAPTOP A:
    ping -t 10.0.0.2

The only two commands to MEMORIZE (run on the server):
    sudo ./block.sh        # ping stops
    sudo ./unblock.sh      # ping resumes

That's it. Start once, then just block / unblock.

================================================================
ON THE DAY — ADVANCED (STATEFUL) DEMO
================================================================
On the SERVER (one command):
    sudo ./start_advanced.sh

On LAPTOP A:
    ping -t 10.0.0.2

Memorize:
    sudo ./stats.sh        # show live counters + remembered count
    sudo ./reset.sh        # clear memory so the auto-blocked ping resumes
(The block happens BY ITSELF after ~20 packets — you don't type anything for that.)

================================================================
TIPS
================================================================
- Want NO "sudo" each time? Run ONCE:  sudo usermod -aG docker $USER  then log out/in.
  After that just:  ./start_demo.sh  ./block.sh  ./unblock.sh
- Switch the demo type: just run the other start script — it cleanly replaces the switch.
- Restart everything if anything misbehaves: re-run the start script. It resets the NICs
  and relaunches the switch container from scratch.
- See switch logs:  docker logs p4sw
- Stop the switch:  docker rm -f p4sw

================================================================
IF A SCRIPT WON'T RUN
================================================================
- "bad interpreter" or "\r": you skipped the line-ending fix. Run: sed -i 's/\r$//' *.sh
- "permission denied": run  chmod +x *.sh   (one-time)
- "Cannot connect ... 9090" from block/stats: the switch isn't running — re-run the start
  script and check  docker ps  shows a container named  p4sw.
- Laptop A says "Destination host unreachable": its Ethernet lost the static IP
  (10.0.0.1) — re-set it (ncpa.cpl). "Request timed out" before you blocked = Laptop B
  firewall; set its network to Private.
