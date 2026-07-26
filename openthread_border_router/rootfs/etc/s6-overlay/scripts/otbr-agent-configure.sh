#!/usr/bin/with-contenv bashio
# shellcheck shell=bash

# ==============================================================================
# Configure OTBR depending on add-on settings
# ==============================================================================

# the stock border routing manager is no good. we will statically route this container ourselves.
ot-ctl br disable
ot-ctl trel enable

if bashio::config.true 'nat64'; then
    bashio::log.info "Enabling NAT64 and Border Router stack."
    
    # 1. Enable Border Routing Manager (required for NAT64 prefix management & IPv6 routing)
    ot-ctl br enable
    # 2. Publish local prefixes/routes to the Thread network
    ot-ctl netdata register
    # 3. Enable NAT64 Translator & Prefix Manager
    ot-ctl nat64 enable
    # 4. Enable SRP Server (standard companion to BR for DNS/SRP resolution)
    ot-ctl srp server enable
    # 5. Enable DNS upstream (verify exact syntax for your environment)
    ot-ctl dns server upstream enable
else
    bashio::log.info "Disabling NAT64 and Border Router stack."
    
    # 1. Disable DNS upstream first (reverse order to avoid dangling dependencies)
    ot-ctl dns server upstream disable
    # 2. Disable SRP Server
    ot-ctl srp server disable
    # 3. Disable NAT64 Translator & Prefix Manager
    ot-ctl nat64 disable
    # 4. Disable Border Routing Manager
    ot-ctl br disable
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