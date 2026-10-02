# mcast-guard — LAN mDNS amplification guard for ts-otbr

## Why

The ts-otbr addon's firewall (`firewall: true`) gates multicast/mDNS/SRP **to and from
the Thread side (wpan0)** — correct for border routing. It does **not** gate the **LAN
side** (backbone interface, e.g. `end0`). In production a Matter-discovery mDNS loop
(`NSEC(QM)` probes for a vanished Matter node, tx-id 0) amplified on the segment by
every responder (HA stacks on all BRs) reached **~1.5–2.6 kpps**, flooding each BR's
host (NIC 1–2 kpps, supervisor 5353 socket backlog 212 KB) and worsening Thread
stability. `mcast-guard` caps **multicast** mDNS crossing the backbone interface in/out
so the storm can't saturate the host; ordinary discovery and **unicast** mDNS/SRP are
untouched, and the wpan0 Thread rules are not modified.

## Validated effect (pilot on ha-tbr-164, 2026-10-02)

| Metric (20 s window) | Before | After |
|---|---|---|
| Host mDNS emission (own 5353 frames) | ~698 pps | ~54 pps |
| Segment mDNS as seen by host | ~1,732 pps | ~27 pps |
| Multicast-mDNS dropped at OUTPUT (cumulative) | — | 413,569 pkts / 43.7 MB |

## Important build note

`hashlimit name … rate 40/second` **fails to parse on nftables v1.1.3** (this image)
with `syntax error, unexpected /`. The guard therefore uses the `limit` expression with
an **accept-within-limit → drop-excess pair** (a bare `limit … counter drop` drops the
*limited* packets and passes the storm — the classic inverted trap). Closing braces of
nft chains must sit on their own line.

## Apply now (no rebuild)

```
docker cp mcast-guard/00-mdns-guard.sh <otbr-ctr>:/tmp/mdns-guard.sh
docker exec <otbr-ctr> sh /tmp/mdns-guard.sh on end0
docker exec <otbr-ctr> sh /tmp/mdns-guard.sh counters   # watch drops
```
Undo: `sh /tmp/mdns-guard.sh off`. Host reboot clears the table (re-run `on`, or bake in).

## Bake into the addon (persistent — recommended)

The validated change is integrated as `mdns_guard` (default `true`) with tunable rates:
- `openthread_border_router/config.yaml` — new options `mdns_guard`, `mdns_guard_in_rate`,
  `mdns_guard_in_burst`, `mdns_guard_out_rate`, `mdns_guard_out_burst`
- `openthread_border_router/rootfs/etc/s6-overlay/scripts/otbr-mdns-guard.sh` — bashio
  service that installs the ruleset at addon start
- `rootfs/etc/s6-overlay/s6-rc.d/otbr-mdns-guard/{type,up}` + `user/contents.d` wiring

Rebuild the addon, bump version, deploy. Set `mdns_guard: false` to disable.

## Scope

Fixes the LAN-side amplifier on every BR. Does NOT fix the origin client: identify and
power off/update the flooding Matter client(s) (at least 172.15.1.105 / 70:70:fc:06:db:ee,
still transmitting during diagnosis) and any non-BR HAOS boxes; Thread-side RF/leader
churn is a separate mitigation (see `../rca.md` / `../journal.md`).

## Tuning & verification

`counters` shows accepted-vs-dropped per chain. If legit discovery is being clipped,
raise the rates. Confirm commissioning after deploy: Matter-over-Thread commissioning is
unicast SRP (wpan0), unaffected by this table.
