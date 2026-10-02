#!/usr/bin/with-contenv bashio
# otbr-mdns-guard — LAN mDNS amplification guard (validated 2026-10-02).
# Caps multicast mDNS (224.0.0.251 / ff02::fb) on the backbone interface with the
# nft `limit` ACCEPT/DROP pair, so an mDNS storm cannot starve the HA stack on this
# host. Unicast mDNS/SRP and all wpan0 Thread rules are untouched.
# Controlled by addon options: mdns_guard (bool, default true), mdns_guard_in_rate,
# mdns_guard_in_burst, mdns_guard_out_rate, mdns_guard_out_burst.

ITF=$(bashio::config 'backbone_interface' 'end0')

if bashio::config.true 'mdns_guard'; then
  IN_RATE=$(bashio::config 'mdns_guard_in_rate' '40/second')
  IN_BURST=$(bashio::config 'mdns_guard_in_burst' '120')
  OUT_RATE=$(bashio::config 'mdns_guard_out_rate' '30/second')
  OUT_BURST=$(bashio::config 'mdns_guard_out_burst' '60')

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
  bashio::log.info "otbr-mdns-guard: enabled on ${ITF} (in ${IN_RATE}/${IN_BURST}, out ${OUT_RATE}/${OUT_BURST})"
else
  nft delete table inet hermes_mdns_guard 2>/dev/null || true
  bashio::log.info "otbr-mdns-guard: disabled"
fi

exit 0
