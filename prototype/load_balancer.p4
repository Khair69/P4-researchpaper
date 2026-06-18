/* load_balancer.p4 - L4 stateless ECMP-style load balancer (V1Model / BMv2).
 * Author: Mohammad Khair Al-Hourani.
 * Hashes the 5-tuple to pick one of N backend servers so that every packet
 * of a flow lands on the same backend (per-connection consistency), while
 * different flows spread evenly. This is a "virtual IP" (VIP) front end.   */
#include <core.p4>
#include <v1model.p4>

const bit<16> TYPE_IPV4 = 0x0800;
const bit<8>  PROTO_TCP = 6;
const bit<32> VIP       = 0x0A000001;   // 10.0.0.1 - the service virtual IP

header ethernet_t { bit<48> dstAddr; bit<48> srcAddr; bit<16> etherType; }
header ipv4_t {
    bit<4> version; bit<4> ihl; bit<8> diffserv; bit<16> totalLen;
    bit<16> id; bit<3> flags; bit<13> fragOffset; bit<8> ttl; bit<8> proto;
    bit<16> hdrChecksum; bit<32> srcAddr; bit<32> dstAddr;
}
header tcp_t {
    bit<16> srcPort; bit<16> dstPort; bit<32> seqNo; bit<32> ackNo;
    bit<4> dataOffset; bit<3> res; bit<9> flags; bit<16> window;
    bit<16> checksum; bit<16> urgentPtr;
}
struct headers  { ethernet_t ethernet; ipv4_t ipv4; tcp_t tcp; }
struct metadata { bit<16> backend_id; }

parser MyParser(packet_in pkt, out headers hdr, inout metadata meta,
                inout standard_metadata_t std) {
    state start          { transition parse_ethernet; }
    state parse_ethernet { pkt.extract(hdr.ethernet);
        transition select(hdr.ethernet.etherType){ TYPE_IPV4: parse_ipv4; default: accept; } }
    state parse_ipv4     { pkt.extract(hdr.ipv4);
        transition select(hdr.ipv4.proto){ PROTO_TCP: parse_tcp; default: accept; } }
    state parse_tcp      { pkt.extract(hdr.tcp); transition accept; }
}
control MyVerifyChecksum(inout headers hdr, inout metadata meta) { apply { } }

control MyIngress(inout headers hdr, inout metadata meta,
                  inout standard_metadata_t std) {
    action drop() { mark_to_drop(std); }
    action set_backend(bit<32> dip, bit<48> dmac, bit<9> port) {
        hdr.ipv4.dstAddr     = dip;          // DNAT to the chosen backend
        hdr.ethernet.dstAddr = dmac;
        std.egress_spec      = port;
        hdr.ipv4.ttl         = hdr.ipv4.ttl - 1;
    }
    table backend_pool {
        key = { meta.backend_id: exact; }
        actions = { set_backend; drop; }
        size = 256; default_action = drop();
    }
    apply {
        if (hdr.ipv4.isValid() && hdr.ipv4.dstAddr == VIP) {
            // hash the 5-tuple -> stable backend index in [0, 3]
            hash(meta.backend_id, HashAlgorithm.crc16,
                 (bit<16>)0,
                 { hdr.ipv4.srcAddr, hdr.ipv4.dstAddr,
                   hdr.ipv4.proto, hdr.tcp.srcPort, hdr.tcp.dstPort },
                 (bit<16>)4);
            backend_pool.apply();
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
