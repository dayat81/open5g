/* SPDX-License-Identifier: Dual BSD/GPL
 *
 * The license string above is the kernel BPF program tag. It does not set
 * the license of this repository. See /NOTICE.
 *
 * Skeleton only: it does not parse DNS, TLS, QUIC, or hostnames, and it
 * does not drop or rewrite packets. Loading and attaching are out of scope.
 */

#include <linux/bpf.h>
#include <linux/pkt_cls.h>
#include <bpf/bpf_helpers.h>

struct app_counter {
	__u64 packets;
	__u64 bytes;
};

struct {
	__uint(type, BPF_MAP_TYPE_HASH);
	__uint(max_entries, 64);
	__type(key, __u32);
	__type(value, struct app_counter);
} app_counters SEC(".maps");

SEC("tc")
int open5g_app_classifier(struct __sk_buff *skb)
{
	(void)skb;
	return TC_ACT_UNSPEC;
}

char _license[] SEC("license") = "Dual BSD/GPL";
