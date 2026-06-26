/* stateful_firewall.p4  — the "advanced" demo program.
 * Shows THREE things a fixed-function switch cannot do:
 *   1) STATE: the switch remembers how many packets it has sent toward Laptop B,
 *      and AUTO-BLOCKS once a threshold is crossed — a decision it makes by itself,
 *      at line rate, with no controller involved (think rate-limiting / DoS defence).
 *   2) TELEMETRY: per-port packet counters the control plane can read LIVE while
 *      traffic flows (zero extra probe traffic — the in-band telemetry idea).
 *   3) PROGRAMMABILITY: you reset its memory from the controller and it "forgives".
 * Still a transparent 2-port bridge (port 0 = Laptop A, port 1 = Laptop B).
 * Target: v1model / BMv2.
 */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;
const bit<32> THRESHOLD = 20;     // after this many A->B packets, auto-block. Tune freely.

header ethernet_t { bit<48> dstAddr; bit<48> srcAddr; bit<16> etherType; }
header ipv4_t {
    bit<4>  version;  bit<4>  ihl;     bit<8>  diffserv;
    bit<16> totalLen; bit<16> identification;
    bit<3>  flags;    bit<13> fragOffset;
    bit<8>  ttl;      bit<8>  protocol; bit<16> hdrChecksum;
    bit<32> srcAddr;  bit<32> dstAddr;
}
struct metadata { }
struct headers  { ethernet_t ethernet; ipv4_t ipv4; }

parser MyParser(packet_in packet, out headers hdr,
                inout metadata meta, inout standard_metadata_t std) {
    state start          { transition parse_ethernet; }
    state parse_ethernet { packet.extract(hdr.ethernet);
                           transition select(hdr.ethernet.etherType) {
                               TYPE_IPV4: parse_ipv4; default: accept; } }
    state parse_ipv4     { packet.extract(hdr.ipv4); transition accept; }
}
control MyVerifyChecksum(inout headers hdr, inout metadata meta) { apply { } }

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t std) {

    // (1) live telemetry: count packets seen on each input port (0 and 1)
    counter(2, CounterType.packets) port_pkts;

    // (2) state: how many IPv4 packets we've forwarded toward Laptop B (port 1)
    register<bit<32>>(1) fw_count;

    action drop() { mark_to_drop(std); }

    apply {
        // transparent bridge for everything (incl. ARP)
        if (std.ingress_port == 0) { std.egress_spec = 1; }
        else                       { std.egress_spec = 0; }

        // telemetry: tick the counter for whichever port this packet came in on
        port_pkts.count((bit<32>) std.ingress_port);

        // stateful auto-block: only for IPv4 packets heading to Laptop B
        if (hdr.ipv4.isValid() && std.egress_spec == 1) {
            bit<32> c;
            fw_count.read(c, 0);
            c = c + 1;
            fw_count.write(0, c);
            if (c > THRESHOLD) {
                drop();           // the switch blocks it ON ITS OWN, based on memory
            }
        }
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t std) { apply { } }
control MyComputeChecksum(inout headers hdr, inout metadata meta) { apply { } }
control MyDeparser(packet_out packet, in headers hdr) {
    apply { packet.emit(hdr.ethernet); packet.emit(hdr.ipv4); }
}

V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(),
         MyEgress(), MyComputeChecksum(), MyDeparser()) main;
