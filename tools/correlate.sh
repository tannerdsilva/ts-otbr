#!/bin/bash
# correlate.sh — every 5 min, sample switch 1/0/3 flap state + Pi BR traffic + Mac sFlow
# Append a TSV row to correlate.tsv; print an alert line ONLY on anomalies (watchdog pattern).
TS=$(date '+%Y-%m-%d %H:%M:%S')
TFILE="/Users/tannerdsilva/workspace/Netgear-controlplane-stabilize/correlate.tsv"
SWKEY=~/.ssh/netgear_switch
PIKEY=~/.ssh/threadbr

SWOUT=$(printf 'enable\nterminal length 0\nshow interfaces diag 1/0/3\nshow logging buffered | include "Link Down: 1/0/3"\nquit\n' \
  | ssh -o LogLevel=ERROR -i "$SWKEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no admin@10.16.1.11 2>/dev/null)

LDD=$(echo "$SWOUT" | grep -o 'Link Down Event Counter : *[0-9]*' | grep -o '[0-9]*')
RATE=$(echo "$SWOUT" | grep -o 'input rate is *[0-9]*' | grep -o '[0-9]*$')
LASTFLAP=$(echo "$SWOUT" | grep -oE 'Oct +[0-9]+ [0-9:]+ .*Link Down: 1/0/3.*' | head -1 | tr -d '\r' | awk '{print $1, $2, $3, $9, $10}')

PI=$(ssh -o LogLevel=ERROR -i "$PIKEY" -o ConnectTimeout=10 -o StrictHostKeyChecking=no root@172.15.1.107 \
  'TOT=$(timeout 8 tcpdump -i end0 -nn -c 150000 2>/dev/null | wc -l); MD=$(timeout 8 tcpdump -i end0 -nn -c 150000 "port 5353" 2>/dev/null | wc -l); echo "$TOT $MD"' 2>/dev/null)
PPS=$(echo "$PI" | awk '{printf "%.0f", $1/8}')
MDPPS=$(echo "$PI" | awk '{printf "%.0f", $2/8}')

SFLOW=$(tail -1 /Users/tannerdsilva/workspace/Netgear-controlplane-stabilize/sflow.log 2>/dev/null | head -c 200)

echo -e "$TS\tldd=${LDD:-NA}\tin_pps=${RATE:-NA}\tlastflap=${LASTFLAP:-none}\tpi_pps=${PPS:-NA}\tpi_mdns=${MDPPS:-NA}" >> "$TFILE"

ALERT=""
PREV=$(tail -2 "$TFILE" 2>/dev/null | head -1 | grep -o 'ldd=[0-9]*' | cut -d= -f2)
if [ -n "$LDD" ] && [ -n "$PREV" ] && [ "$LDD" -gt "$PREV" ] 2>/dev/null; then
  ALERT="1/0/3 FLAP (link-down counter ${PREV}->${LDD})"
fi
if [ -n "$MDPPS" ] && [ "$MDPPS" -gt 4000 ] 2>/dev/null; then
  ALERT="$ALERT | Pi mDNS spike ${MDPPS} pps"
fi
if [ -n "$ALERT" ]; then
  echo "[$TS] $ALERT   (1/0/3 in=${RATE:-?} pps; sFlow: $SFLOW)"
fi
