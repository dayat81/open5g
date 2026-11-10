#!/bin/sh
# Shared nft statement text for render-cgnat.sh and android-ue-add-ue.sh.
# Source this file. It does not change shell options.

cgnat_ue_filter_lines() {
  ip_addr=$1
  limit=$2
  sgi_if=$3
  egress_if=$4
  printf '%s\n' \
    "        ip saddr ${ip_addr} ct count over ${limit} drop" \
    "        ip saddr ${ip_addr} iifname \"${sgi_if}\" oifname \"${egress_if}\" accept"
}

cgnat_ue_nat_lines() {
  ip_addr=$1
  snat_addr=$2
  port_block=$3
  egress_if=$4
  printf '%s\n' \
    "        ip saddr ${ip_addr} oifname \"${egress_if}\" tcp dport 0-65535 snat to ${snat_addr}:${port_block}" \
    "        ip saddr ${ip_addr} oifname \"${egress_if}\" udp dport 0-65535 snat to ${snat_addr}:${port_block}" \
    "        ip saddr ${ip_addr} oifname \"${egress_if}\" ip protocol icmp snat to ${snat_addr}"
}
