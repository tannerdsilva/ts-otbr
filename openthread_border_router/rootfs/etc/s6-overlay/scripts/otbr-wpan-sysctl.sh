#!/usr/bin/with-contenv bashio
# vim: ft=bash
# shellcheck shell=bash
# ==============================================================================
# otbr-wpan-sysctl
# Waits for the Thread interface to appear, then applies IPv6 hardening
# with retries. Designed for the real behaviour of wpan0 in OTBR containers.
# ==============================================================================

THREAD_IF="${thread_if:-wpan0}"

bashio::log.info "otbr-wpan-sysctl: waiting for ${THREAD_IF} directory to appear..."

MAX_WAIT=60
elapsed=0

# The interface directory can exist before its IPv6 sysctl files are
# populated; wait for the actual knob so the writes below cannot vanish.
while [ ! -r "/proc/sys/net/ipv6/conf/${THREAD_IF}/accept_ra" ]; do
    if [ "${elapsed}" -ge "${MAX_WAIT}" ]; then
        bashio::log.error "otbr-wpan-sysctl: timed out after ${MAX_WAIT}s waiting for ${THREAD_IF} IPv6 sysctls"
        exit 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

bashio::log.info "otbr-wpan-sysctl: ${THREAD_IF} present – current values:"

for key in accept_ra accept_ra_defrtr accept_ra_pinfo forwarding; do
    val=$(sysctl -n "net.ipv6.conf.${THREAD_IF}.${key}" 2>/dev/null || echo "unreadable")
    bashio::log.info "  ${key} = ${val}"
done

# Re-apply until the kernel confirms the values; otbr-agent can re-initialise
# the interface while this oneshot is running.
applied=false
for attempt in $(seq 1 15); do
    sysctl -w "net.ipv6.conf.${THREAD_IF}.accept_ra=0"        >/dev/null 2>&1 || true
    sysctl -w "net.ipv6.conf.${THREAD_IF}.accept_ra_defrtr=0" >/dev/null 2>&1 || true
    sysctl -w "net.ipv6.conf.${THREAD_IF}.accept_ra_pinfo=0"  >/dev/null 2>&1 || true
    sysctl -w "net.ipv6.conf.${THREAD_IF}.forwarding=1"       >/dev/null 2>&1 || true

    if [ "$(sysctl -n "net.ipv6.conf.${THREAD_IF}.accept_ra" 2>/dev/null)" = "0" ] \
       && [ "$(sysctl -n "net.ipv6.conf.${THREAD_IF}.forwarding" 2>/dev/null)" = "1" ]; then
        applied=true
        break
    fi
    sleep 1
done

if [ "${applied}" = true ]; then
    bashio::log.info "otbr-wpan-sysctl: IPv6 hardening applied"
else
    bashio::log.warning "otbr-wpan-sysctl: could not confirm IPv6 hardening"
fi

exit 0   # always succeed