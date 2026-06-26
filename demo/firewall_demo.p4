/* firewall_demo.p4
 * A COMPLETE, ready-to-run P4_16 program for a live demo.
 * It does two things:
 *   1) Normal IPv4 forwarding (so h1 can ping h2)   -> table ipv4_lpm
 *   2) A firewall you control at runtime            -> table acl
 * Drop a destination by adding ONE rule to `acl` from the switch CLI;
 * remove it and traffic flows again. Built for the V1Model / BMv2 target,
 * and shaped to slot into the p4lang "exercises/basic" harness unchanged.
 */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x800;

typedef bit<9>  egressSpec_t;
typedef bit<48> macAddr_t;
typedef bit<32> ip4Addr_t;

header ethernet_t {
    macAddr_t dstAddr;
    macAddr_t srcAddr;
    bit<16>   etherType;
}
header ipv4_t {
    bit<4>    version;   bit<4>  ihl;     bit<8>  diffserv;
    bit<16>   totalLen;  bit<16> identification;
    bit<3>    flags;     bit<13> fragOffset;
    bit<8>    ttl;       bit<8>  protocol; bit<16> hdrChecksum;
    ip4Addr_t srcAddr;   ip4Addr_t dstAddr;
}
struct metadata { }
struct headers  { ethernet_t ethernet; ipv4_t ipv4; }

/*** PARSER ***/
parser MyParser(packet_in packet, out headers hdr,
                inout metadata meta, inout standard_metadata_t std) {
    state start            { transition parse_ethernet; }
    state parse_ethernet   { packet.extract(hdr.ethernet);
                             transition select(hdr.ethernet.etherType) {
                                 TYPE_IPV4: parse_ipv4; default: accept; } }
    state parse_ipv4       { packet.extract(hdr.ipv4); transition accept; }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) { apply { } }

/*** INGRESS: where the firewall + forwarding decisions happen ***/
control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t std) {

    action drop() { mark_to_drop(std); }

    action ipv4_forward(macAddr_t dstAddr, egressSpec_t port) {
        std.egress_spec      = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dstAddr;
        hdr.ipv4.ttl         = hdr.ipv4.ttl - 1;
    }

    // Normal routing table (filled at startup by sX-runtime.json)
    table ipv4_lpm {
        key = { hdr.ipv4.dstAddr: lpm; }
        actions = { ipv4_forward; drop; NoAction; }
        size = 1024;
        default_action = NoAction();
    }

    // THE FIREWALL. Empty by default (everything allowed). You add a rule live.
    table acl {
        key = { hdr.ipv4.dstAddr: ternary; }
        actions = { drop; NoAction; }
        size = 1024;
        default_action = NoAction();
    }

    apply {
        if (hdr.ipv4.isValid()) {
            acl.apply();        // 1) check the firewall first
            ipv4_lpm.apply();   // 2) then forward whatever survived
        }
    }
}

control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t std) { apply { } }

/*** Recompute the IPv4 checksum after we changed the TTL ***/
control MyComputeChecksum(inout headers hdr, inout metadata meta) {
    apply {
        update_checksum(hdr.ipv4.isValid(),
            { hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv,
              hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags,
              hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol,
              hdr.ipv4.srcAddr, hdr.ipv4.dstAddr },
            hdr.ipv4.hdrChecksum, HashAlgorithm.csum16);
    }
}

control MyDeparser(packet_out packet, in headers hdr) {
    apply { packet.emit(hdr.ethernet); packet.emit(hdr.ipv4); }
}

V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(),
         MyEgress(), MyComputeChecksum(), MyDeparser()) main;
