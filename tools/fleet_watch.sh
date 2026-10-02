#!/bin/bash
# fleet_watch.sh — per-BR control-plane telemetry for the 5-min cron.
# Samples role, BBR state, SRP server state + registered-host count, partition,
# and guard drop totals on all 6 BRs; appends to fleet_watch.tsv; alerts on drift:
#   partition change, leader/BBR-primary move, SRP state change, SRP-host asymmetry
#   (registrations on a secondary while the BBR primary has none), guard-drop spike.
# Silent when nothing notable (watchdog pattern). Used via ~/.hermes/scripts/... wrapper.
TS=$(date '+%Y-%m-%d %H:%M:%S')
DIR=/Users/tannerdsilva/workspace/Netgear-controlplane-stabilize
TSV="$DIR/fleet_watch.tsv"
ST="$DIR/fleet_watch.state"
KEY=~/.ssh/threadbr
HOSTS="172.15.1.106:ha-tbr-100 172.15.1.107:ha-tbr-164 172.15.1.164:ha-tbr-115 172.15.1.109:ha-tbr-181 172.15.1.113:ha-tbr-100e 172.15.1.120:ha-tbr-205"

probe() {
  ssh -o LogLevel=ERROR -o ConnectTimeout=8 -o StrictHostKeyChecking=no -i "$KEY" "root@$1" \
    'C=$(docker ps --format "{{.Names}}" | grep -i border)
     printf "%s|%s|%s|%s|%s|%s\n" \
       "$(docker exec $C ot-ctl state 2>/dev/null | tr -d "\r" | head -1)" \
       "$(docker exec $C ot-ctl bbr state 2>/dev/null | tr -d "\r" | head -1)" \
       "$(docker exec $C ot-ctl srp server state 2>/dev/null | tr -d "\r" | head -1)" \
       "$(docker exec $C ot-ctl srp server host 2>/dev/null | tr -d "\r" | grep -cE "^[0-9A-F]{16}\.")" \
       "$(docker exec $C ot-ctl partitionid 2>/dev/null | tr -d "\r" | head -1)" \
       "$(docker exec $C nft list table inet hermes_mdns_guard 2>/dev/null | sed -n "s/.*counter packets \([0-9]*\) bytes \([0-9]*\) drop.*/\1/p" | awk "{s+=\$1} END{print s+0}")"' 2>/dev/null
}

CUR=""
for h in $HOSTS; do
  ip=${h%%:*}; name=${h##*:}
  d=$(probe "$ip")
  [ -z "$d" ] && d="NA|NA|NA|NA|NA|NA"
  CUR="$CUR$name $(echo "$d" | tr '|' ' ' ) "   # name role bbr srp hosts part drop
done
echo -e "$TS\t$(echo "$CUR" | xargs)" >> "$TSV"

# ---- drift detection against previous pass ----
ALERT=""
if [ -f "$ST" ]; then
  while read -r name role bbr srp hosts part drop; do
    [ -z "$name" ] && continue
    old=$(grep -E "^$name " "$ST" 2>/dev/null)
    [ -z "$old" ] && continue
    o_role=$(echo "$old" | awk '{print $2}'); o_bbr=$(echo "$old" | awk '{print $3}')
    o_srp=$(echo "$old" | awk '{print $4}'); o_hosts=$(echo "$old" | awk '{print $5}')
    o_part=$(echo "$old" | awk '{print $6}'); o_drop=$(echo "$old" | awk '{print $7}')
    [ "$part" != "$o_part" ] && ALERT="$ALERT | $name partition $o_part->$part"
    [ "$role" != "$o_role" ] && ALERT="$ALERT | $name role $o_role->$role"
    [ "$bbr" != "$o_bbr" ] && ALERT="$ALERT | $name BBR $o_bbr->$bbr"
    [ "$srp" != "$o_srp" ] && ALERT="$ALERT | $name SRP $o_srp->$srp"
    [ -n "$drop" ] && [ -n "$o_drop" ] && [ $((drop - o_drop)) -gt 3000 ] 2>/dev/null \
      && ALERT="$ALERT | $name guard-drop +$((drop - o_drop))"
  done <<< "$(echo "$CUR" | xargs -n7)"
  # SRP asymmetry: registrations on a non-BBR-primary while the primary has none
  primary=$(echo "$CUR" | xargs -n7 | awk '$3=="Primary"{print $1}' | head -1)
  primary_hosts=$(echo "$CUR" | xargs -n7 | awk '$3=="Primary"{print $5}' | head -1)
  others=$(echo "$CUR" | xargs -n7 | awk -v p="$primary" '$1!=p && $4=="running" {print $1": hosts="$5}' | tr '\n' ';' | sed 's/;$//')
  primary_hosts=${primary_hosts:-0}
  if [ -n "$others" ] && [ "$primary_hosts" -eq 0 ] 2>/dev/null; then
    ALERT="$ALERT | SRP asymmetry: primary=$primary($primary_hosts), SRP also on $others"
  fi
fi
echo "$CUR" | xargs -n7 > "$ST"

if [ -n "$ALERT" ]; then
  echo "[$TS] FLEET-DRIFT:$ALERT"
fi
