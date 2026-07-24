#!/usr/bin/with-contenv bashio
# vim: ft=bash
# shellcheck shell=bash
# ==============================================================================
# otbr-wpan-sysctl
# Waits until the Thread interface is fully ready, then applies IPv6 hardening.
# ==============================================================================

THREAD_IF="${thread_if:-wpan0}"

bashio::log.info "otbr-wpan-sysctl: waiting for ${THREAD_IF} to become ready..."

MAX_WAIT=90
elapsed=0

# Wait until:
#   1. the sysctl directory exists, AND
#   2. we can actually read the accept_ra value, AND
#   3. (optional but recommended) the interface is operationally up
while true; do
    if [ -d "/proc/sys/net/ipv6/conf/${THREAD_IF}" ] && \
       sysctl -n "net.ipv6.conf.${THREAD_IF}.accept_ra" >/dev/null 2>&1; then

        # Extra safety: prefer the interface to be UP
        operstate=$(cat "/sys/class/net/${THREAD_IF}/operstate" 2>/dev/null || echo "unknown")
        if [ "${operstate}" = "up" ] || [ "${operstate}" = "unknown" ]; then
            # "unknown" is accepted because some virtual interfaces never report "up"
            break
        fi
    fi

    if [ "${elapsed}" -ge "${MAX_WAIT}" ]; then
        bashio::log.error "otbr-wpan-sysctl: timed out after ${MAX_WAIT}s waiting for ${THREAD_IF} to become ready"
        exit 1
    fi

    sleep 1
    elapsed=$((elapsed + 1))
done

bashio::log.info "otbr-wpan-sysctl: ${THREAD_IF} is ready (operstate=$(cat /sys/class/net/${THREAD_IF}/operstate 2>/dev/null || echo unknown)) – applying hardening"

# Apply the hardening
sysctl -w "net.ipv6.conf.${THREAD_IF}.accept_ra=0"        >/dev/null 2>&1 || true
sysctl -w "net.ipv6.conf.${THREAD_IF}.accept_ra_defrtr=0" >/dev/null 2>&1 || true
sysctl -w "net.ipv6.conf.${THREAD_IF}.accept_ra_pinfo=0"  >/dev/null 2>&1 || true
sysctl -w "net.ipv6.conf.${THREAD_IF}.forwarding=1"       >/dev/null 2>&1 || true

# Verify
accept_ra=$(sysctl -n "net.ipv6.conf.${THREAD_IF}.accept_ra" 2>/dev/null || echo "unknown")
bashio::log.info "otbr-wpan-sysctl: ${THREAD_IF}.accept_ra = ${accept_ra}"

if [ "${accept_ra}" = "0" ]; then
    bashio::log.info "otbr-wpan-sysctl: hardening applied successfully"
    exit 0
else
    bashio::log.error "otbr-wpan-sysctl: failed to set accept_ra=0 (got '${accept_ra}')"
    exit 1
fi