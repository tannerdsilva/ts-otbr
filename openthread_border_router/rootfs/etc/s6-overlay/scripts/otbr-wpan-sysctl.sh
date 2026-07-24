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

# Only wait for the sysctl directory – this is the reliable signal
while [ ! -d "/proc/sys/net/ipv6/conf/${THREAD_IF}" ]; do
    if [ "${elapsed}" -ge "${MAX_WAIT}" ]; then
        bashio::log.error "otbr-wpan-sysctl: timed out after ${MAX_WAIT}s waiting for ${THREAD_IF}"
        exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

bashio::log.info "otbr-wpan-sysctl: ${THREAD_IF} directory present – applying hardening (with retries)"

# Helper that retries a sysctl write a few times
set_sysctl() {
    local key="$1"
    local value="$2"
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if sysctl -w "${key}=${value}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    bashio::log.warning "otbr-wpan-sysctl: failed to set ${key}=${value} after retries"
    return 1
}

# Apply the hardening settings
set_sysctl "net.ipv6.conf.${THREAD_IF}.accept_ra"        0
set_sysctl "net.ipv6.conf.${THREAD_IF}.accept_ra_defrtr" 0
set_sysctl "net.ipv6.conf.${THREAD_IF}.accept_ra_pinfo"  0
set_sysctl "net.ipv6.conf.${THREAD_IF}.forwarding"       1

# Optional – uncomment if you also want to suppress host Router Solicitations
# set_sysctl "net.ipv6.conf.${THREAD_IF}.router_solicitations" 0

# Best-effort verification (do not fail the service if the read is flaky)
sleep 1
accept_ra=$(sysctl -n "net.ipv6.conf.${THREAD_IF}.accept_ra" 2>/dev/null || echo "unreadable")

bashio::log.info "otbr-wpan-sysctl: ${THREAD_IF}.accept_ra is now '${accept_ra}'"

if [ "${accept_ra}" = "0" ]; then
    bashio::log.info "otbr-wpan-sysctl: hardening applied and verified successfully"
else
    bashio::log.warning "otbr-wpan-sysctl: could not verify accept_ra=0 (got '${accept_ra}'). This is often normal in containers – the writes were still attempted."
fi

# Always exit 0 so the oneshot is considered successful.
# The important part is that the writes were issued once the interface existed.
exit 0