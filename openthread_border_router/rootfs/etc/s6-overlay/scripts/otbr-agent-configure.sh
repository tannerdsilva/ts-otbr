#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Helper: run an ot-ctl command and return success only when it prints "Done"
# ==============================================================================
otctl() {
    local output
    output=$(ot-ctl "$@" 2>&1)
    local rc=$?

    # Success only if exit code is 0 AND the reply contains "Done"
    if [[ $rc -eq 0 && "$output" == *"Done"* && "$output" != *"Error"* ]]; then
        echo "$output"
        return 0
    fi

    # Failure – show the real error
    echo "$output" >&2
    return 1
}

# ==============================================================================
# Wait until the Border Routing Manager is ready
# ==============================================================================
bashio::log.info "Waiting for OpenThread Border Routing Manager to become ready..."

READY=false
for i in {1..60}; do
    # First make sure the basic CLI is alive
    if ! ot-ctl state >/dev/null 2>&1; then
        sleep 1
        continue
    fi

    # Now wait until a Border-Routing command actually works
    if ot-ctl br state >/dev/null 2>&1; then
        # Extra safety: also check that omrprefix responds without InvalidCommand
        if ot-ctl br omrprefix >/dev/null 2>&1; then
            READY=true
            break
        fi
    fi

    if [[ $((i % 5)) -eq 0 ]]; then
        bashio::log.info "Still waiting for Border Routing Manager... ($i/60)"
    fi
    sleep 1
done

if [[ "$READY" != "true" ]]; then
    bashio::log.error "Border Routing Manager never became ready. Aborting configuration."
    exit 1
fi

bashio::log.info "Border Routing Manager is ready."

# ==============================================================================
# Basic services
# ==============================================================================
otctl trel enable || bashio::log.warning "Failed to enable TREL"

if bashio::config.true 'nat64'; then
    bashio::log.info "Enabling NAT64."
    otctl nat64 enable || bashio::log.warning "Failed to enable NAT64"
    otctl dns server upstream enable || true
fi

mdns_localhostname="$(hostname)-otbr"
bashio::log.info "Setting OpenThread mDNS local hostname to ${mdns_localhostname}."
otctl mdns localhostname "${mdns_localhostname}" || true
otctl mdns enable || true

# Conservative TX power
otctl txpower 6 || true

# ==============================================================================
# Route preferences
# ==============================================================================
ROUTE_PRF=$(bashio::config 'custom_route_preference' 'med')
bashio::log.info "Setting Border Router route preference to ${ROUTE_PRF}"
otctl br routeprf "${ROUTE_PRF}" || bashio::log.warning "Failed to set br routeprf"

otctl br rioprf high || bashio::log.warning "Failed to set br rioprf"

# ==============================================================================
# DHCPv6-PD
# ==============================================================================
bashio::log.info "Attempting to enable DHCPv6-PD..."

if otctl br pd enable; then
    bashio::log.info "✅ DHCPv6-PD enabled"

    # Prefer automatic OMR selection so the PD prefix can be used
    otctl br omrconfig auto || bashio::log.warning "Failed to set br omrconfig auto"
    otctl netdata register || true

    bashio::log.info "Waiting for a DHCPv6-PD prefix (up to 60 s)..."
    PD_SUCCESS=false
    for i in {1..30}; do
        if PD_PREFIX=$(otctl br pd omrprefix 2>/dev/null); then
            # Clean the "Done" line if present
            PD_PREFIX=$(echo "$PD_PREFIX" | grep -v '^Done$' | head -n1)
            if [[ -n "$PD_PREFIX" ]]; then
                bashio::log.info "✅ DHCPv6-PD prefix obtained: ${PD_PREFIX}"
                PD_SUCCESS=true
                break
            fi
        fi

        if [[ $((i % 5)) -eq 0 ]]; then
            STATE=$(ot-ctl br pd state 2>/dev/null | head -n1 || echo "unknown")
            bashio::log.info "Still waiting... (pd state: ${STATE})"
        fi
        sleep 2
    done

    if [[ "$PD_SUCCESS" != "true" ]]; then
        bashio::log.warning "⚠️  No DHCPv6-PD prefix received within timeout."
        bashio::log.warning "    Check DHCP server, firewall (UDP 546/547), and backbone interface."
    fi
else
    bashio::log.error "❌ DHCPv6-PD is not available in this build (Error 35: InvalidCommand)."
    bashio::log.error "   The binary was compiled without OPENTHREAD_CONFIG_BORDER_ROUTING_DHCP6_PD_ENABLE."
    bashio::log.error "   You must rebuild OTBR with that flag set to 1 if you want PD support."
fi

# ==============================================================================
# Final status
# ==============================================================================
sleep 2

bashio::log.info "=== Final status ==="
bashio::log.info "br state:"
ot-ctl br state || true
bashio::log.info "OMR / on-link:"
ot-ctl br omrprefix || true
ot-ctl br onlinkprefix || true
bashio::log.info "Network Data:"
ot-ctl netdata show || true