/* firewall.p4 - L3/L4 stateless ACL firewall for the V1Model (BMv2) architecture.
 * Author: Mohammad Khair Al-Hourani.  Target: v1model / simple_switch.
 * Drops packets that match a deny-list of (srcAddr, protocol, dstPort) entries,
 * otherwise forwards by destination IPv4 longest-prefix match.            */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x0800;
const bit<8>  PROTO_TCP = 6;

header ethernet_t {
    bit<48> dstAddr;
    bit<48> srcAddr;
    bit<16> etherType;
}
header ipv4_t {
    bit<4>  version;  bit<4> ihl;   bit<8> diffserv;
    bit<16> totalLen; bit<16> id;   bit<3> flags;  bit<13> fragOffset;
    bit<8>  ttl;      bit<8> proto; bit<16> hdrChecksum;
    bit<32> srcAddr;  bit<32> dstAddr;
}
header tcp_t {
    bit<16> srcPort; bit<16> dstPort;
    bit<32> seqNo;   bit<32> ackNo;
    bit<4>  dataOffset; bit<3> res; bit<9> flags;
    bit<16> window;  bit<16> checksum; bit<16> urgentPtr;
}
struct headers   { ethernet_t ethernet; ipv4_t ipv4; tcp_t tcp; }
struct metadata  { }

parser MyParser(packet_in pkt, out headers hdr,
                inout metadata meta, inout standard_metadata_t std) {
    state start            { transition parse_ethernet; }
    state parse_ethernet   { pkt.extract(hdr.ethernet);
                             transition select(hdr.ethernet.etherType){
                                 TYPE_IPV4: parse_ipv4; default: accept; } }
    state parse_ipv4       { pkt.extract(hdr.ipv4);
                             transition select(hdr.ipv4.proto){
                                 PROTO_TCP: parse_tcp; default: accept; } }
    state parse_tcp        { pkt.extract(hdr.tcp); transition accept; }
}

control MyVerifyChecksum(inout headers hdr, inout metadata meta) { apply { } }

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t std) {
    action drop() { mark_to_drop(std); }
    action ipv4_forward(bit<48> dmac, bit<9> port) {
        std.egress_spec = port;
        hdr.ethernet.srcAddr = hdr.ethernet.dstAddr;
        hdr.ethernet.dstAddr = dmac;
        hdr.ipv4.ttl = hdr.ipv4.ttl - 1;
    }
    table acl {                                   // the firewall deny-list
        key = { hdr.ipv4.srcAddr: ternary;
                hdr.ipv4.proto  : exact;
                hdr.tcp.dstPort : exact; }
        actions = { drop; NoAction; }
        size = 1024; default_action = NoAction();
    }
    table ipv4_lpm {                              // destination routing
        key = { hdr.ipv4.dstAddr: lpm; }
        actions = { ipv4_forward; drop; NoAction; }
        size = 1024; default_action = drop();
    }
    apply {
        if (hdr.ipv4.isValid()) {
            acl.apply();                          // deny-list first
            ipv4_lpm.apply();                     // then route survivors
        }
    }
}
control MyEgress(inout headers hdr, inout metadata meta,
                 inout standard_metadata_t std) { apply { } }
control MyComputeChecksum(inout headers hdr, inout metadata meta) { apply { } }
control MyDeparser(packet_out pkt, in headers hdr) {
    apply { pkt.emit(hdr.ethernet); pkt.emit(hdr.ipv4); pkt.emit(hdr.tcp); }
}
V1Switch(MyParser(), MyVerifyChecksum(), MyIngress(),
         MyEgress(), MyComputeChecksum(), MyDeparser()) main;
