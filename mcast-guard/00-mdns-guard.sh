#!/bin/sh
# 00-mdns-guard.sh — LAN mDNS amplification guard for ts-otbr (VALIDATED 2026-10-02).
# Caps multicast mDNS (224.0.0.251 / ff02::fb) in/out over the backbone interface using
# the nft `limit` expression with an ACCEPT-within-limit / DROP-excess pair of rules,
# so an mDNS storm can no longer saturate the BR host HA stack, while normal discovery
# (occasional queries/announcements) and ALL unicast mDNS/SRP keep flowing.
#
# NOTE: do NOT use `hashlimit rate X/second` on this build (nftables v1.1.3) — it fails
# with "syntax error, unexpected /". The `limit` idiom below is the validated one.
#
# Usage:  00-mdns-guard.sh on|off|status|counters [iface [in_rate [in_burst [out_rate [out_burst]]]]]
#   e.g.  00-mdns-guard.sh on end0             (defaults: in 40/s b120, out 30/s b60)
#         00-mdns-guard.sh counters
# Run inside the OTBR container (has nft + NET_ADMIN + host netns):
#   docker exec -it <otbr-ctr> sh -c "$(cat ./00-mdns-guard.sh)" on end0
# Host reboot clears the table — re-run `on`, or bake into the addon (see README).

ITF="${2:-end0}"
IN_RATE="${3:-40/second}";  IN_BURST="${4:-120}"
OUT_RATE="${5:-30/second}"; OUT_BURST="${6:-60}"

nft --version >/dev/null 2>&1 || { echo "nft not found" >&2; exit 1; }

install() {
  nft delete table inet hermes_mdns_guard 2>/dev/null || true
  nft -f - <<EOF
table inet hermes_mdns_guard {
  chain mg_in4 {
    type filter hook input priority 0; policy accept;
    iifname "$ITF" ip daddr 224.0.0.251 udp dport 5353 limit rate $IN_RATE burst $IN_BURST packets counter accept
    iifname "$ITF" ip daddr 224.0.0.251 udp dport 5353 counter drop
  }
  chain mg_in6 {
    type filter hook input priority 0; policy accept;
    iifname "$ITF" ip6 daddr ff02::fb udp dport 5353 limit rate $IN_RATE burst $IN_BURST packets counter accept
    iifname "$ITF" ip6 daddr ff02::fb udp dport 5353 counter drop
  }
  chain mg_out4 {
    type filter hook output priority 0; policy accept;
    oifname "$ITF" ip daddr 224.0.0.251 udp sport 5353 limit rate $OUT_RATE burst $OUT_BURST packets counter accept
    oifname "$ITF" ip daddr 224.0.0.251 udp sport 5353 counter drop
  }
  chain mg_out6 {
    type filter hook output priority 0; policy accept;
    oifname "$ITF" ip6 daddr ff02::fb udp sport 5353 limit rate $OUT_RATE burst $OUT_BURST packets counter accept
    oifname "$ITF" ip6 daddr ff02::fb udp sport 5353 counter drop
  }
}
EOF
  echo "mcast-guard ON ($ITF in=${IN_RATE}/${IN_BURST} out=${OUT_RATE}/${OUT_BURST})"
}

off() { nft delete table inet hermes_mdns_guard 2>/dev/null || true; echo "mcast-guard OFF"; }

status() { if nft list table inet hermes_mdns_guard >/dev/null 2>&1; then echo ON; else echo OFF; fi; }

counters() {
  nft list table inet hermes_mdns_guard 2>/dev/null | grep -E "chain mg_|limit rate|udp (dsport|sport) 5353 counter" | sed 's/^[[:space:]]*//' || echo "no rules"
}

case "$1" in
  on) install ;;
  off) off ;;
  status) status ;;
  counters) counters ;;
  *) echo "usage: $0 on|off|status|counters [iface [in_rate [in_burst [out_rate [out_burst]]]]]" >&2; exit 2 ;;
esac
