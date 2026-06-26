/* bridge_firewall.p4
 * A 2-port transparent bridge + runtime firewall, for a REAL hardware demo.
 * Run it on a Linux PC ("the P4 box") whose two NICs are bound as port 0 and
 * port 1. It simply passes traffic between the two ports (so two real laptops
 * can talk), and lets you DROP a destination IP live via one table rule.
 *
 * No routing tables, no MAC rewriting, no per-host config: the only entries you
 * ever add are firewall rules. ARP and everything non-IPv4 always passes, so the
 * laptops stay connected; only IPv4 packets are subject to the firewall.
 *
 * Target: v1model / BMv2 (simple_switch).
 */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}
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

    action drop() { mark_to_drop(std); }

    // THE FIREWALL — empty by default (nothing blocked). You add rules live.
    table acl {
        key = { hdr.ipv4.dstAddr: ternary; }
        actions = { drop; NoAction; }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        // 1) Transparent 2-port bridge for EVERY packet (incl. ARP):
        //    whatever comes in port 0 goes out port 1, and vice versa.
        if (std.ingress_port == 0) { std.egress_spec = 1; }
        else                       { std.egress_spec = 0; }

        // 2) The firewall runs only on IPv4 and can OVERRIDE the bridge with a drop.
        if (hdr.ipv4.isValid()) { acl.apply(); }
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
