#!/bin/sh
# 00-mdns-guard.sh — LAN multicast-storm guard for ts-otbr (VALIDATED 2026-10-02).
# Caps multicast mDNS (224.0.0.251 / ff02::fb) and, with extra=yes (default), LLMNR
# (224.0.0.252 / ff02::1:3:5355) + SSDP (239.255.255.250 / ff02::c:1900) in+out over
# the backbone interface. nft `limit` ACCEPT-within-limit / DROP-excess pair.
# Do NOT use `hashlimit rate N/second` (broken on nft 1.1.3); closing braces own line.
#
# Usage: 00-mdns-guard.sh on|off|status|counters [iface] [extra]
#   extra: yes|no  (default yes) — include LLMNR/SSDP caps
#
# Standard apply (inside OTBR container, NET_ADMIN + host netns):
#   docker exec <otbr-ctr> sh /tmp/mdns-guard.sh on end0

ITF="${2:-end0}"
EXTRA="${3:-yes}"
IN_RATE="${4:-40/second}"; IN_BURST="${5:-120}"
OUT_RATE="${6:-30/second}"; OUT_BURST="${7:-60}"

nft --version >/dev/null 2>&1 || { echo "nft not found" >&2; exit 1; }

install() {
  nft delete table inet hermes_mdns_guard 2>/dev/null || true
  (
    printf 'table inet hermes_mdns_guard {\n'
    # ingress v4
    printf '  chain mg_in4 {\n    type filter hook input priority 0; policy accept;\n'
    printf '    iifname "%s" ip daddr 224.0.0.251 udp dport 5353 limit rate %s burst %s packets counter accept\n' "$ITF" "$IN_RATE" "$IN_BURST"
    printf '    iifname "%s" ip daddr 224.0.0.251 udp dport 5353 counter drop\n' "$ITF"
    if [ "$EXTRA" = "yes" ]; then
      printf '    iifname "%s" ip daddr 224.0.0.252 udp dport 5355 limit rate %s burst %s packets counter accept\n' "$ITF" "$IN_RATE" "$IN_BURST"
      printf '    iifname "%s" ip daddr 224.0.0.252 udp dport 5355 counter drop\n' "$ITF"
      printf '    iifname "%s" ip daddr 239.255.255.250 udp dport 1900 limit rate %s burst %s packets counter accept\n' "$ITF" "$IN_RATE" "$IN_BURST"
      printf '    iifname "%s" ip daddr 239.255.255.250 udp dport 1900 counter drop\n' "$ITF"
    fi
    printf '  }\n'
    # ingress v6
    printf '  chain mg_in6 {\n    type filter hook input priority 0; policy accept;\n'
    printf '    iifname "%s" ip6 daddr ff02::fb udp dport 5353 limit rate %s burst %s packets counter accept\n' "$ITF" "$IN_RATE" "$IN_BURST"
    printf '    iifname "%s" ip6 daddr ff02::fb udp dport 5353 counter drop\n' "$ITF"
    if [ "$EXTRA" = "yes" ]; then
      printf '    iifname "%s" ip6 daddr ff02::1:3 udp dport 5355 limit rate %s burst %s packets counter accept\n' "$ITF" "$IN_RATE" "$IN_BURST"
      printf '    iifname "%s" ip6 daddr ff02::1:3 udp dport 5355 counter drop\n' "$ITF"
      printf '    iifname "%s" ip6 daddr ff02::c udp dport 1900 limit rate %s burst %s packets counter accept\n' "$ITF" "$IN_RATE" "$IN_BURST"
      printf '    iifname "%s" ip6 daddr ff02::c udp dport 1900 counter drop\n' "$ITF"
    fi
    printf '  }\n'
    # egress v4
    printf '  chain mg_out4 {\n    type filter hook output priority 0; policy accept;\n'
    printf '    oifname "%s" ip daddr 224.0.0.251 udp sport 5353 limit rate %s burst %s packets counter accept\n' "$ITF" "$OUT_RATE" "$OUT_BURST"
    printf '    oifname "%s" ip daddr 224.0.0.251 udp sport 5353 counter drop\n' "$ITF"
    if [ "$EXTRA" = "yes" ]; then
      printf '    oifname "%s" ip daddr 224.0.0.252 udp sport 5355 limit rate %s burst %s packets counter accept\n' "$ITF" "$OUT_RATE" "$OUT_BURST"
      printf '    oifname "%s" ip daddr 224.0.0.252 udp sport 5355 counter drop\n' "$ITF"
      printf '    oifname "%s" ip daddr 239.255.255.250 udp sport 1900 limit rate %s burst %s packets counter accept\n' "$ITF" "$OUT_RATE" "$OUT_BURST"
      printf '    oifname "%s" ip daddr 239.255.255.250 udp sport 1900 counter drop\n' "$ITF"
    fi
    printf '  }\n'
    # egress v6
    printf '  chain mg_out6 {\n    type filter hook output priority 0; policy accept;\n'
    printf '    oifname "%s" ip6 daddr ff02::fb udp sport 5353 limit rate %s burst %s packets counter accept\n' "$ITF" "$OUT_RATE" "$OUT_BURST"
    printf '    oifname "%s" ip6 daddr ff02::fb udp sport 5353 counter drop\n' "$ITF"
    if [ "$EXTRA" = "yes" ]; then
      printf '    oifname "%s" ip6 daddr ff02::1:3 udp sport 5355 limit rate %s burst %s packets counter accept\n' "$ITF" "$OUT_RATE" "$OUT_BURST"
      printf '    oifname "%s" ip6 daddr ff02::1:3 udp sport 5355 counter drop\n' "$ITF"
      printf '    oifname "%s" ip6 daddr ff02::c udp sport 1900 limit rate %s burst %s packets counter accept\n' "$ITF" "$OUT_RATE" "$OUT_BURST"
      printf '    oifname "%s" ip6 daddr ff02::c udp sport 1900 counter drop\n' "$ITF"
    fi
    printf '  }\n'
    printf '}\n'
  ) | nft -f -
  echo "mcast-guard ON ($ITF, extra=$EXTRA, in=${IN_RATE}/${IN_BURST}, out=${OUT_RATE}/${OUT_BURST})"
}

off() { nft delete table inet hermes_mdns_guard 2>/dev/null || true; echo "mcast-guard OFF"; }
status() { nft list table inet hermes_mdns_guard >/dev/null 2>&1 && echo ON || echo OFF; }
counters() { nft list table inet hermes_mdns_guard 2>/dev/null | grep -E "chain mg_|limit rate|udp (dsport|sport) (5353|5355|1900) counter" | sed 's/^[[:space:]]*//' || echo "no rules"; }

case "$1" in
  on) install ;;
  off) off ;;
  status) status ;;
  counters) counters ;;
  *) echo "usage: $0 on|off|status|counters [iface [extra [in_rate [in_burst [out_rate [out_burst]]]]]]" >&2; exit 2 ;;
esac
