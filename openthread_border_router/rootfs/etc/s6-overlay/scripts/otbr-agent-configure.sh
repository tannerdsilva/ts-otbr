#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Configure OTBR – DHCPv6-PD driven OMR prefix
# ==============================================================================

ot-ctl trel enable

if bashio::config.true 'nat64'; then
    bashio::log.info "Enabling NAT64."
    ot-ctl nat64 enable
    ot-ctl dns server upstream enable
fi

mdns_localhostname="$(hostname)-otbr"
bashio::log.info "Setting OpenThread mDNS local hostname to ${mdns_localhostname}."
ot-ctl mdns localhostname "${mdns_localhostname}"
ot-ctl mdns enable

# Keep TX power conservative so we don't create asymmetric links
ot-ctl txpower 6

# ==============================================================================
# Wait until ot-ctl is ready
# ==============================================================================
for i in {1..40}; do
    if ot-ctl state >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ==============================================================================
# Route preference (applies to external routes published by the BR)
# ==============================================================================
ROUTE_PRF=$(bashio::config 'custom_route_preference' 'med')
bashio::log.info "Setting Border Router route preference to ${ROUTE_PRF}"
ot-ctl br routeprf "${ROUTE_PRF}" || bashio::log.warning "Failed to set br routeprf"

# Also make RIOs on the infrastructure side preferred
ot-ctl br rioprf high || bashio::log.warning "Failed to set br rioprf"

# ==============================================================================
# Enable DHCPv6 Prefix Delegation
# This is the primary way we obtain a ULA (or GUA) prefix from the DHCP server
# ==============================================================================
bashio::log.info "Enabling DHCPv6-PD client"
if ot-ctl br pd enable; then
    bashio::log.info "✅ DHCPv6-PD enabled"
else
    bashio::log.error "❌ Failed to enable DHCPv6-PD – is the feature compiled in?"
fi

# ==============================================================================
# Let the Routing Manager automatically manage the OMR prefix
# In "auto" mode it will prefer a DHCPv6-PD prefix when one is available
# ==============================================================================
bashio::log.info "Setting OMR configuration to auto (will use PD prefix when available)"
ot-ctl br omrconfig auto || bashio::log.warning "Failed to set br omrconfig auto"

# Publish any Network Data changes
ot-ctl netdata register || bashio::log.warning "netdata register failed"

# ==============================================================================
# Wait for a PD prefix and give visibility
# ==============================================================================
bashio::log.info "Waiting for DHCPv6-PD prefix (up to ~60 seconds)..."

PD_SUCCESS=false
for i in {1..30}; do
    PD_STATE=$(ot-ctl br pd state 2>/dev/null | head -n1 || echo "unknown")
    PD_PREFIX=$(ot-ctl br pd omrprefix 2>/dev/null | head -n1 || true)

    if [[ -n "${PD_PREFIX}" && "${PD_PREFIX}" != *"error"* ]]; then
        bashio::log.info "✅ DHCPv6-PD prefix obtained: ${PD_PREFIX}"
        PD_SUCCESS=true
        break
    fi

    if [[ $((i % 5)) -eq 0 ]]; then
        bashio::log.info "Still waiting... (pd state: ${PD_STATE})"
    fi
    sleep 2
done

if [[ "${PD_SUCCESS}" != "true" ]]; then
    bashio::log.warning "⚠️  No DHCPv6-PD prefix received within timeout."
    bashio::log.warning "    Check that:"
    bashio::log.warning "    1. Your DHCP server is configured to delegate a prefix (/48, /56 or /60) to this host"
    bashio::log.warning "    2. The backbone interface can send/receive DHCPv6 (UDP 546/547)"
    bashio::log.warning "    3. Firewall rules allow DHCPv6 between OTBR and the server"
    bashio::log.warning "    4. OPENTHREAD_CONFIG_BORDER_ROUTING_DHCP6_PD_ENABLE is enabled in the build"
fi

# Small settle time
sleep 2

# ==============================================================================
# Final visibility
# ==============================================================================
bashio::log.info "Current DHCPv6-PD state:"
ot-ctl br pd state || true
bashio::log.info "Current PD OMR prefix:"
ot-ctl br pd omrprefix || true
bashio::log.info "Current OMR / on-link view:"
ot-ctl br omrprefix || true
ot-ctl br onlinkprefix || true
bashio::log.info "Current Network Data:"
ot-ctl netdata show || true